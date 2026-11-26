/// The bell on Home: which activity is news FOR ME, how to word it, and
/// the badge text ("3", "9+").
///
/// A notification is either
/// * an activity entry someone ELSE made that names me in
///   [ActivityEvent.forIds]:
///     payment  → "Jun says they paid you ₱845.00. Tap to confirm."
///                (or, if the receiver recorded it: "Mia recorded your
///                ₱450.00 payment")
///     confirm  → "Mia confirmed your ₱450.00 payment"
///     reminder → "Leo reminded you to pay ₱395.00"
///     expense / edit → "Ana added Samgyup", "Jun edited Soju"
///     join     → "Rico joined the group"
/// * or a recurring bill that is due soon ([dueSoonNotice]), using the
///   "remind N days before" setting from Profile.
///
/// Unread = newer than the last time the bell was opened (saved on the
/// phone in SettingsService.notificationsSeenAt).
library;

import 'package:bahinko/models/group.dart';
import 'package:bahinko/models/recurring_bill.dart';
import 'package:bahinko/utils/currency.dart';

typedef GroupEvent = ({Group group, ActivityEvent event});

/// The actor id used for notices the app makes itself (bills due).
const systemActor = 'bahinko';

/// True if [e] is about me and was done by someone else.
bool isNotificationFor(ActivityEvent e, String myId) =>
    e.forIds.contains(myId) && e.actorId.isNotEmpty && e.actorId != myId;

/// When I (last) joined each group, from my own "join" entry there.
/// Groups I created have none, so nothing is hidden there.
Map<String, DateTime> joinedAtByGroup(List<GroupEvent> all, String myId) {
  final joined = <String, DateTime>{};
  for (final item in all) {
    final e = item.event;
    final at = e.createdAt;
    if (e.type != 'join' || e.actorId != myId || at == null) continue;
    final prev = joined[item.group.id];
    if (prev == null || at.isAfter(prev)) joined[item.group.id] = at;
  }
  return joined;
}

/// Drops what happened in a group BEFORE I joined it. Used by the bell and
/// by Activity History, so a new member doesn't see the group's past.
List<GroupEvent> sinceJoining(List<GroupEvent> all, String myId) {
  final joinedAt = joinedAtByGroup(all, myId);
  if (joinedAt.isEmpty) return all;
  return [
    for (final item in all)
      if (!_beforeJoining(item, joinedAt)) item,
  ];
}

/// Only my notifications, keeping the newest-first order (and nothing from
/// before I joined the group).
List<GroupEvent> notificationsFor(List<GroupEvent> all, String myId) => [
  for (final item in sinceJoining(all, myId))
    if (isNotificationFor(item.event, myId)) item,
];

bool _beforeJoining(GroupEvent item, Map<String, DateTime> joinedAt) {
  final joined = joinedAt[item.group.id];
  final at = item.event.createdAt;
  return joined != null && at != null && at.isBefore(joined);
}

/// Newest first (entries still being saved count as "now").
void sortNewestFirst(List<GroupEvent> list) => list.sort(
  (a, b) => (b.event.createdAt ?? DateTime.now()).compareTo(
    a.event.createdAt ?? DateTime.now(),
  ),
);

/// How many are newer than [seenAt] (all of them if never opened).
int unreadCount(List<GroupEvent> mine, DateTime? seenAt) => mine
    .where(
      (n) =>
          seenAt == null ||
          (n.event.createdAt ?? DateTime.now()).isAfter(seenAt),
    )
    .length;

/// Badge text: nothing for 0, "1"–"9", then "9+".
String? badgeLabel(int count) => count <= 0
    ? null
    : count > 9
    ? '9+'
    : '$count';

/// "WiFi is due in 2 days (₱1,500)" once a bill is within [daysBefore]
/// days of its due date, else null. Paused bills never notify.
/// Its time is the start of that window, so it counts as new once.
ActivityEvent? dueSoonNotice(
  RecurringBill bill,
  String myId, {
  required DateTime now,
  required int daysBefore,
}) {
  if (!bill.enabled) return null;
  final due = bill.nextDue(now);
  final today = DateTime(now.year, now.month, now.day);
  final days = due.difference(today).inDays;
  if (days > daysBefore) return null;
  final when = switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    _ => 'in $days days',
  };
  final windowStart = due.subtract(Duration(days: daysBefore));
  return ActivityEvent(
    id: 'due-${bill.id}-${due.year}-${due.month}',
    type: 'due',
    text: '${bill.name} is due $when (${bill.amount})',
    actorId: systemActor,
    forIds: [myId],
    amountCents: bill.amountCents,
    createdAt: windowStart.isAfter(today) ? windowStart : today,
  );
}

/// The sentence shown in the list, written to me.
String notificationText(ActivityEvent e, String myId) {
  final who = e.actorName.isEmpty ? 'Someone' : e.actorName;
  final amount = e.amountCents == null ? '' : formatMoney(e.amountCents!);
  // Payments list [payer, receiver] in forIds.
  final iAmPayer = e.forIds.length > 1 && e.forIds.first == myId;
  return switch (e.type) {
    'reminder' =>
      amount.isEmpty
          ? '$who sent you a payment reminder'
          : '$who reminded you to pay $amount',
    'payment' when iAmPayer => '$who recorded your $amount payment',
    'payment' => '$who says they paid you $amount. Tap to confirm.',
    'confirm' => '$who confirmed your $amount payment',
    _ => e.text,
  };
}
