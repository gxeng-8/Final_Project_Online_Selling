/// Figma Frame 11 "Split Summary": a saved expense shown as a receipt,
/// with what each person pays. Loaded live from [GroupService], so edits
/// and new members show up immediately.
///
/// ✎ Edit opens the expense in Add Expense (edit mode); 🗑 Delete removes it
/// after a confirmation. Both are logged in the activity feed, so the group
/// can always see who changed what.
library;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:bahinko/data/in_memory_group_service.dart' show demoGroupId;
import 'package:bahinko/models/group.dart';
import 'package:bahinko/models/person.dart';
import 'package:bahinko/screens/bill/add_expense_screen.dart';
import 'package:bahinko/screens/settle/settle_up_screen.dart';
import 'package:bahinko/services/group_service.dart';
import 'package:bahinko/theme/app_colors.dart';
import 'package:bahinko/theme/app_theme.dart';
import 'package:bahinko/utils/currency.dart';
import 'package:bahinko/utils/navigation.dart';
import 'package:bahinko/widgets/app_page.dart';
import 'package:bahinko/widgets/app_toast.dart';
import 'package:bahinko/widgets/async_state_view.dart';
import 'package:bahinko/widgets/avatar.dart';
import 'package:bahinko/widgets/btn.dart';
import 'package:bahinko/widgets/pill.dart';

class SplitSummary extends StatefulWidget {
  const SplitSummary({super.key, this.groupId = demoGroupId, this.expenseId});

  final String groupId;

  /// The expense to show. If null, shows the group's newest expense.
  final String? expenseId;

  @override
  State<SplitSummary> createState() => _SplitSummaryState();
}

class _SplitSummaryState extends State<SplitSummary> {
  late Stream<Group> _group;
  late Stream<GroupExpense> _expense;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    final service = GroupService.instance;
    _group = service.watchGroup(widget.groupId);
    final id = widget.expenseId;
    _expense = id != null
        ? service.watchExpense(widget.groupId, id)
        : service.watchExpenses(widget.groupId).map((list) {
            if (list.isEmpty) {
              throw const GroupFailure('No expenses in this group yet.');
            }
            return list.first;
          });
  }

  void _reload() => setState(_listen);

  /// Plain-text summary for the group chat (share sheet).
  Future<void> _share(Group group, GroupExpense e) async {
    final lines = [
      '${e.title}: ${formatMoney(e.amountCents)} (paid by ${e.paidBy})',
      for (final s in e.shares.entries)
        if (s.key != e.paidById)
          '• ${group.memberById(s.key)?.name ?? 'Member'} pays '
              '${formatMoney(s.value)}',
      'Settle up in BahinKo.',
    ];
    try {
      await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
    } catch (_) {
      if (mounted) showAppToast(context, "Couldn't open sharing here.");
    }
  }

  /// Asks first, then deletes and goes back.
  Future<void> _delete(GroupExpense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${e.title}?'),
        content: Text(
          'This removes the ${formatMoney(e.amountCents)} expense for '
          'everyone in the group and recalculates who owes what. Payments '
          'already recorded are kept. The group will see that you deleted it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: errorFg),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await GroupService.instance.deleteExpense(widget.groupId, e);
      if (!mounted) return;
      Navigator.pop(context);
      showAppToast(context, 'Deleted ${e.title}');
    } on GroupFailure catch (err) {
      if (mounted) showAppToast(context, err.message);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Group>(
    stream: _group,
    builder: (context, groupSnap) => StreamBuilder<GroupExpense>(
      stream: _expense,
      builder: (context, expenseSnap) {
        final group = groupSnap.data;
        final expense = expenseSnap.data;
        // Show an error from either stream; load until both arrive.
        final AsyncSnapshot<GroupExpense> combined = groupSnap.hasError
            ? AsyncSnapshot.withError(ConnectionState.done, groupSnap.error!)
            : (group == null ? const AsyncSnapshot.waiting() : expenseSnap);
        return AppPage(
          'Split Summary',
          onRefresh: () => setState(_listen),
          AsyncStateView<GroupExpense>(
            snapshot: combined,
            onRetry: _reload,
            builder: (e) => _ReceiptCard(group: group!, expense: e),
          ),
          actions: [
            if (group != null && expense != null)
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.share_outlined),
                onPressed: () => _share(group, expense),
              ),
            if (group != null && expense != null && expense.id.isNotEmpty)
              PopupMenuButton<String>(
                key: const ValueKey('expense-menu'),
                tooltip: 'Edit or delete',
                onSelected: (action) => action == 'edit'
                    ? go(
                        context,
                        AddExpense(groupId: widget.groupId, editing: expense),
                      )
                    : _delete(expense),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit expense'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline, color: errorFg),
                      title: Text(
                        'Delete expense',
                        style: TextStyle(color: errorFg),
                      ),
                    ),
                  ),
                ],
              ),
          ],
          bottom: group == null
              ? null
              : Btn(
                  'Settle Up',
                  () => go(context, SettleUp(groupId: widget.groupId)),
                ),
        );
      },
    ),
  );
}

/// The white receipt with zigzag edges (Figma 11).
class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.group, required this.expense});

  final Group group;
  final GroupExpense expense;

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final myId = GroupService.instance.myId;
    const mono = TextStyle(fontSize: 13, letterSpacing: 0.3);
    // The date picked on Add Expense (falls back to when it was saved).
    final date = e.date;
    final subtitle = [
      group.name,
      if (date != null) '${_months[date.month - 1]} ${date.day}, ${date.year}',
      'Paid by ${e.paidById == myId ? 'You' : e.paidBy}',
    ].join(' · ');

    return ClipPath(
      clipper: _ZigzagClipper(),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        child: Column(
          children: [
            Text(e.title.toUpperCase(), style: AppText.display(20, color: ink)),
            const SizedBox(height: 2),
            Text(subtitle, textAlign: TextAlign.center, style: AppText.caption),
            if (e.fromAi) ...[
              const SizedBox(height: 6),
              const Pill('Items found by AI', icon: Icons.auto_awesome),
            ],
            const _Dashes(),
            for (var i = 0; i < e.items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 22, child: Text('${i + 1}', style: mono)),
                    Expanded(
                      child: Text(e.items[i].name.toUpperCase(), style: mono),
                    ),
                    Text(formatMoney(e.items[i].amountCents), style: mono),
                  ],
                ),
              ),
            if (e.items.isEmpty) Text(e.title, style: mono),
            const _Dashes(),
            Row(
              children: [
                Text('TOTAL', style: AppText.section),
                const Spacer(),
                Text(
                  formatMoney(e.amountCents),
                  style: AppText.money(22, color: green),
                ),
              ],
            ),
            const _Dashes(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    // Equal split: everyone pays the same; otherwise not.
                    e.splitMode == 'equal'
                        ? 'Each person pays'
                        : 'Who pays what',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: muted,
                    ),
                  ),
                ),
                Text(
                  '${e.shares.length} people sharing',
                  style: AppText.caption,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final share in e.shares.entries)
              _ShareRow(
                person: group.memberById(share.key),
                isMe: share.key == myId,
                paidTheBill: share.key == e.paidById,
                amountCents: share.value,
              ),
            const _Dashes(),
            const Text(
              'THANK YOU!',
              style: TextStyle(letterSpacing: 2, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

/// One "each person pays" line: avatar, name, amount.
class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.person,
    required this.isMe,
    required this.paidTheBill,
    required this.amountCents,
  });

  final Person? person;
  final bool isMe, paidTheBill;
  final int amountCents;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        if (person != null) Avatar(person!, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            isMe ? 'You' : (person?.name ?? 'Former member'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (paidTheBill) ...[
          const Pill.paid(text: 'Paid the bill'),
          const SizedBox(width: 8),
        ],
        Text(
          formatMoney(amountCents),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

/// Dashed divider, like on a printed receipt.
class _Dashes extends StatelessWidget {
  const _Dashes();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: LayoutBuilder(
      builder: (context, c) => Row(
        children: List.generate(
          (c.maxWidth / 8).floor(),
          (_) => Container(
            width: 4,
            height: 1,
            margin: const EdgeInsets.only(right: 4),
            color: border,
          ),
        ),
      ),
    ),
  );
}

/// Cuts small triangles into the top and bottom edges (torn-paper look).
class _ZigzagClipper extends CustomClipper<Path> {
  static const _tooth = 10.0;

  @override
  Path getClip(Size size) {
    final path = Path()..moveTo(0, _tooth);
    // Top edge: up and down teeth from left to right.
    for (var x = 0.0; x < size.width; x += _tooth) {
      path
        ..lineTo(x + _tooth / 2, 0)
        ..lineTo(x + _tooth, _tooth);
    }
    path.lineTo(size.width, size.height - _tooth);
    // Bottom edge: teeth from right to left.
    for (var x = size.width; x > 0; x -= _tooth) {
      path
        ..lineTo(x - _tooth / 2, size.height)
        ..lineTo(x - _tooth, size.height - _tooth);
    }
    return path..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
