/// The contract for loading and saving groups.
///
/// Screens only talk to [GroupService.instance], never to Firestore
/// directly. Two implementations exist:
/// * [FirestoreGroupService]: the real app (set in main.dart).
/// * [InMemoryGroupService]: sample data for widget tests, which can't
///   use Firebase. It's the default until main() swaps in Firestore.
///
/// Reads return Streams, so screens update automatically when data
/// changes, even when another member edits the group on their phone.
library;

import 'dart:async';
import 'dart:math';

import 'package:bahinko/data/in_memory_group_service.dart';
import 'package:bahinko/models/group.dart';
import 'package:bahinko/models/person.dart';
import 'package:bahinko/models/recurring_bill.dart';
import 'package:bahinko/utils/settle_calculator.dart';
import 'package:bahinko/utils/stream_utils.dart';
import 'package:bahinko/utils/notifications.dart';
import 'package:bahinko/services/settings_service.dart';

abstract class GroupService {
  /// The service the whole app uses. main() replaces it with Firestore.
  static GroupService instance = InMemoryGroupService();

  /// All groups the current user is a member of, newest first.
  Stream<List<Group>> watchMyGroups();

  /// One group. Emits a [GroupFailure] error if it doesn't exist.
  Stream<Group> watchGroup(String groupId);

  /// A group's expenses, newest first.
  Stream<List<GroupExpense>> watchExpenses(String groupId);

  /// Creates a group with the current user plus [others] as members.
  Future<Group> createGroup({
    required String name,
    required GroupCategory category,
    required List<Person> others,
  });

  /// Adds a guest (someone without the app) to a group by name.
  Future<void> addGuest(String groupId, String name);

  /// Joins the group with this invite [code] as [yourName].
  /// Returns the group's ID. If you're already a member, just returns it.
  Future<String> joinGroup(String code, String yourName);

  /// Makes sure the group's invite code can be looked up (for groups
  /// created before invite codes were published). Safe to call often.
  Future<void> ensureInvite(Group group);

  /// The current user's member ID: compare with Person.id / Payment.toId
  /// to show "You", and use it as the payer/receiver of your own payments.
  String get myId;

  // ---------- Expenses (M2 scanner, M3 Add Expense / Split Summary) ----------

  /// One expense, live (e.g. for Split Summary).
  Stream<GroupExpense> watchExpense(String groupId, String expenseId);

  /// Saves a new expense, adds it to the group's totals, and logs it in the
  /// activity feed. Build it with [GroupExpense.create]. Throws a
  /// [GroupFailure] if it's invalid (see [checkExpense]). Returns its ID.
  Future<String> addExpense(String groupId, GroupExpense expense);

  /// Replaces expense [old] with [updated] (same ID), fixes the group's
  /// total, and logs "Renz edited Samgyup House" (with old → new amount).
  /// Balances recalculate by themselves. Throws [GroupFailure] if invalid.
  Future<void> updateExpense(
    String groupId,
    GroupExpense old,
    GroupExpense updated,
  );

  /// Deletes [expense], takes it out of the group's totals, and logs it.
  /// Payments already recorded are kept (they are real money that moved).
  Future<void> deleteExpense(String groupId, GroupExpense expense);

  // ---------- Payments (M4 Settle Up) ----------

  /// All payments in the group, newest first.
  Stream<List<Payment>> watchPayments(String groupId);

  /// Saves a payment ("Yes, I paid" / "Paid in cash") and logs it.
  /// Status 'pending' = waiting for the receiver to confirm.
  /// A receiver recording cash they got may save it as 'confirmed'.
  Future<void> recordPayment(String groupId, Payment payment);

  /// The receiver confirms they got the money. If [fullShare] is true and
  /// the payment is for an expense, that member no longer counts as unpaid.
  Future<void> confirmPayment(
    String groupId,
    Payment payment, {
    bool fullShare = true,
  });

  // ---------- Activity feed (M5 Activity History) ----------

  /// The group's activity, newest first.
  Stream<List<ActivityEvent>> watchActivity(String groupId);

  /// Adds an event the service doesn't log by itself: reminders sent,
  /// items flagged, prices edited.
  Future<void> logActivity(String groupId, ActivityEvent event);

  // ---------- Recurring bills (M5 Frames 16–17) ----------

  Stream<List<RecurringBill>> watchRecurring(String groupId);
  Future<void> addRecurring(String groupId, RecurringBill bill);
  Future<void> setRecurringEnabled(String groupId, String billId, bool enabled);
  Future<void> deleteRecurring(String groupId, String billId);

  // ---------- Delete my data (Privacy) ----------

  /// Removes me from every group: my name and account leave the member
  /// list. Groups where I was the last app user and the creator are
  /// deleted. Past expenses/payments stay so the others' balances add up.
  Future<void> leaveAllGroups();

  // ---------- Offline mode (Profile, Frame 24) ----------

  /// Offline: stop talking to the server. Changes are kept on the phone
  /// and sent when you go back online. Does nothing where unsupported.
  Future<void> setOffline(bool offline) async {}

  /// Pull-to-refresh: checks the server for the latest data. Screens then
  /// re-open their live streams. Throws [GroupFailure] if it can't connect.
  /// Does nothing where there's no server (the in-memory sample data).
  Future<void> refresh() async {}

  // ---------- Balances (Settle Up, Home, Group Detail) ----------

  /// Saves how many members still owe money (the "N unpaid" on cards).
  /// Screens that have the full ledger call this when it's out of date.
  Future<void> setUnpaidCount(String groupId, int count);

  /// The group, its expenses and its payments, together and live: what
  /// balances and smart settle are computed from.
  Stream<GroupLedger> watchLedger(String groupId) => combineLatest3(
    watchGroup(groupId),
    watchExpenses(groupId),
    watchPayments(groupId),
    GroupLedger.new,
  );

  /// Live data from EVERY group I'm in: [per] is called once for each
  /// group (e.g. its ledger or activity), and the results are emitted as one
  /// list, in the same order as [watchMyGroups]. Groups that join or leave
  /// are picked up automatically. Used by Home, Statistics, Personal Ledger
  /// and Activity History, so they always agree with each other.
  ///
  /// Waits until every group has sent its first value (so screens don't
  /// flash half-loaded numbers). A group that fails is skipped, not fatal.
  Stream<List<T>> watchAcrossMyGroups<T>(Stream<T> Function(Group g) per) {
    late final StreamController<List<T>> out;
    StreamSubscription<List<Group>>? groupsSub;
    final subs = <String, StreamSubscription<T>>{};
    final latest = <String, T>{};
    final waiting = <String>{}; // groups that haven't sent anything yet
    var order = <String>[];

    void emit() {
      if (waiting.isNotEmpty) return;
      out.add([
        for (final id in order)
          if (latest.containsKey(id)) latest[id] as T,
      ]);
    }

    out = StreamController(
      onListen: () {
        groupsSub = watchMyGroups().listen((groups) {
          order = [for (final g in groups) g.id];
          final ids = order.toSet();
          // Stop listening to groups I left.
          for (final id in subs.keys.toList()) {
            if (!ids.contains(id)) {
              subs.remove(id)!.cancel();
              latest.remove(id);
              waiting.remove(id);
            }
          }
          // Start on new ones.
          for (final g in groups) {
            if (subs.containsKey(g.id)) continue;
            waiting.add(g.id);
            subs[g.id] = per(g).listen(
              (value) {
                latest[g.id] = value;
                waiting.remove(g.id);
                emit();
              },
              onError: (Object error) {
                waiting.remove(g.id);
                emit();
              },
            );
          }
          emit(); // e.g. no groups at all, or a group was removed
        }, onError: out.addError);
      },
      onCancel: () async {
        await groupsSub?.cancel();
        await Future.wait(subs.values.map((s) => s.cancel()));
      },
    );
    return out.stream;
  }

  /// Every group's ledger, live (Statistics, Personal Ledger).
  Stream<List<GroupLedger>> watchAllLedgers() =>
      watchAcrossMyGroups((g) => watchLedger(g.id));

  /// Across ALL my groups: how much others owe me, and how much I owe
  /// (the Home header). Updates live as any group changes.
  Stream<({int owedToYou, int youOwe})> watchMyTotals() =>
      watchAllLedgers().map((ledgers) {
        var owed = 0, owe = 0;
        for (final ledger in ledgers) {
          final mine = ledger.balances[myId] ?? 0;
          if (mine > 0) owed += mine;
          if (mine < 0) owe -= mine;
        }
        return (owedToYou: owed, youOwe: owe);
      });

  /// Activity from all my groups, newest first, each with its group
  /// (Activity History).
  Stream<List<({Group group, ActivityEvent event})>> watchAllActivity() =>
      watchAcrossMyGroups(
        (g) => watchActivity(g.id)
            .map((events) => [for (final e in events) (group: g, event: e)]),
      ).map((perGroup) {
        final all = [for (final list in perGroup) ...list];
        all.sort(
          (a, b) => (b.event.createdAt ?? DateTime.now()).compareTo(
            a.event.createdAt ?? DateTime.now(),
          ),
        );
        // A new member doesn't see what happened before they joined.
        return sinceJoining(all, myId);
      });

  /// The bell, newest first (see utils/notifications.dart):
  /// activity from all my groups that is about me and made by someone
  /// else, plus recurring bills due within [daysBefore] days.
  Stream<List<GroupEvent>> watchNotifications({
    int? daysBefore,
    DateTime Function() clock = DateTime.now,
  }) {
    final activity = watchAllActivity().map(
      (all) => notificationsFor(all, myId),
    );
    final dueSoon = watchAcrossMyGroups(
      (g) => watchRecurring(g.id).map(
        (bills) => <GroupEvent>[
          for (final bill in bills)
            if (dueSoonNotice(
                  bill,
                  myId,
                  now: clock(),
                  daysBefore:
                      daysBefore ?? SettingsService.instance.reminderDaysBefore,
                )
                case final notice?)
              (group: g, event: notice),
        ],
      ),
    ).map((perGroup) => [for (final list in perGroup) ...list]);
    return combineLatest2(activity, dueSoon, (a, b) {
      final all = [...a, ...b];
      sortNewestFirst(all);
      return all;
    });
  }
}

/// Checks an expense before saving. Throws [GroupFailure] with a message
/// the screen can show. (Screens should also validate their forms; this
/// is the last safety net so bad data never reaches the database.)
void checkExpense(GroupExpense e) {
  if (e.title.trim().isEmpty) {
    throw const GroupFailure('Give the expense a name.');
  }
  if (e.amountCents <= 0) {
    throw const GroupFailure('The amount must be more than ₱0.');
  }
  if (e.paidById.isEmpty) throw const GroupFailure('Choose who paid.');
  if (e.shares.isEmpty) {
    throw const GroupFailure('Choose who shares this expense.');
  }
  if (e.shares.values.any((s) => s < 0)) {
    throw const GroupFailure('Shares cannot be negative.');
  }
  final sum = e.shares.values.fold(0, (a, b) => a + b);
  if (sum != e.amountCents) {
    throw GroupFailure(
      "Shares add up to ${_peso(sum)}, but the total is "
      "${_peso(e.amountCents)}.",
    );
  }
}

/// Checks a payment before saving.
void checkPayment(Payment p) {
  if (p.amountCents <= 0) {
    throw const GroupFailure('The amount must be more than ₱0.');
  }
  if (p.fromId.isEmpty || p.toId.isEmpty || p.fromId == p.toId) {
    throw const GroupFailure('Choose who paid and who received it.');
  }
}

String _peso(int cents) =>
    '₱${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

/// Error with a message that's safe to show the user.
class GroupFailure implements Exception {
  const GroupFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The current user as a group member, shown with their real name.
Person appUserPerson(String uid, String? name, {String role = 'App user'}) =>
    personFromName(
      (name == null || name.trim().isEmpty) ? 'You' : name,
      id: uid,
      pay: role,
    );

/// Characters used in invite codes: no look-alikes (0/O, 1/I).
const inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const inviteCodeLength = 5;

/// Random 5-character invite code, e.g. "DJ7Q2".
String generateInviteCode() {
  final rng = Random.secure();
  return List.generate(
    inviteCodeLength,
    (_) => inviteAlphabet[rng.nextInt(inviteAlphabet.length)],
  ).join();
}

/// Reads an invite code from what the user typed, pasted, or scanned:
/// a bare code ("dj7q2"), a link ("https://bahinko-303f2.web.app/j/DJ7Q2"),
/// or the app link ("bahinko://join/DJ7Q2").
/// Returns the code in capitals, or null if it isn't a valid code.
String? parseInviteCode(String input) {
  var text = input.trim().toUpperCase();
  // A link: take the part after the last "/".
  if (text.contains('/')) {
    text = text.split('/').where((s) => s.isNotEmpty).last;
  }
  final valid =
      text.length == inviteCodeLength &&
      text.split('').every(inviteAlphabet.contains);
  return valid ? text : null;
}
