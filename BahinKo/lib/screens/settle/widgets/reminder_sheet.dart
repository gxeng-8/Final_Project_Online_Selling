/// Bottom sheet for sending payment reminders.
library;

import 'package:flutter/material.dart';

import 'package:bahinko/services/settings_service.dart';
import 'package:bahinko/utils/currency.dart';
import 'package:bahinko/models/person.dart';
import 'package:bahinko/widgets/avatar.dart';

/// The starting reminder text for each tone. Always kind: no amounts in
/// big letters, no shaming (the user can still edit it before sending).
String reminderMessage(String name, String tone) => switch (tone) {
  'Friendly' =>
    'Hey $name! Quick nudge to settle your share in BahinKo '
        'when you get the chance. Salamat!',
  'Direct' => 'Hi $name, please settle your share in BahinKo today. Thanks.',
  _ =>
    'Hi $name! Just a friendly reminder to settle your share when you '
        'can. Thank you!',
};

class ReminderSheet extends StatefulWidget {
  const ReminderSheet({
    super.key,
    required this.member,
    required this.payer,
    required this.amountInCents,
    required this.groupName,
  });

  final Person member;
  final Person payer;
  final int amountInCents;

  /// The group this reminder is about, shown under the member's name.
  final String groupName;

  @override
  State<ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<ReminderSheet> {
  bool _includeDetails = true;
  bool _sent = false;
  late final TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(
      // Tone chosen in Profile → Reminder settings.
      text: reminderMessage(
        widget.member.name,
        SettingsService.instance.reminderTone,
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Send a friendly reminder',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Avatar(widget.member, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'To: ${widget.member.name}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${widget.groupName} · ${formatMoney(widget.amountInCents)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('reminder-message'),
            controller: _messageController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const ValueKey('reminder-details-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Include payment details',
              style: TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              _includeDetails
                  ? 'Remind ${widget.member.name} to pay ${widget.payer.name}'
                  : 'Send only the friendly reminder',
              style: const TextStyle(fontSize: 11),
            ),
            value: _includeDetails,
            onChanged: (value) => setState(() => _includeDetails = value),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('send-reminder-submit'),
              onPressed: () {
                setState(() => _sent = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Reminder sent to ${widget.member.name}'),
                  ),
                );
                Navigator.pop(context);
              },
              child: Text(_sent ? 'Reminder sent' : 'Send reminder'),
            ),
          ),
        ],
      ),
    ),
  );
}
