/// Dialogs shown while opening and confirming a payment.
library;

import 'package:flutter/material.dart';
import 'package:bahinko/utils/currency.dart';
import 'package:bahinko/models/person.dart';
import 'package:bahinko/theme/app_colors.dart';
import 'package:bahinko/widgets/wallet_logo.dart';

class PaymentOpeningDialog extends StatelessWidget {
  const PaymentOpeningDialog({
    super.key,
    required this.provider,
    required this.member,
    required this.payer,
    required this.amountInCents,
  });

  final String provider;
  final Person member;
  final Person payer;
  final int amountInCents;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: mint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: WalletLogo(provider, size: provider == 'Maya' ? 26 : 44),
          ),
          const SizedBox(height: 20),
          Text(
            'Opening $provider...',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hang on, we’re handing you over to the app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          const CircularProgressIndicator(color: green),
          const SizedBox(height: 20),
          Text(
            '${member.name} pays ${payer.name}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            formatMoney(amountInCents),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('continue-payment-confirmation'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}

class PaymentConfirmationDialog extends StatelessWidget {
  const PaymentConfirmationDialog({
    super.key,
    required this.provider,
    required this.amountInCents,
  });

  final String provider;
  final int amountInCents;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: mint,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: green, size: 42),
          ),
          const SizedBox(height: 18),
          const Text(
            'Did you complete the payment?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Tell us if the $provider payment is complete.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          Text(
            formatMoney(amountInCents),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('payment-confirmed-yes'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, I paid'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const ValueKey('payment-confirmed-no'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not yet'),
            ),
          ),
        ],
      ),
    ),
  );
}
