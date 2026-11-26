/// Pure functions that compute each member's share of a bill.
library;

import 'package:bahinko/data/mock_data.dart';
import 'package:bahinko/utils/currency.dart';

String formatShareRange(int totalInCents, int count) {
  final lowestShare = totalInCents ~/ count;
  final highestShare = lowestShare + (totalInCents % count == 0 ? 0 : 1);
  if (lowestShare == highestShare) return formatCurrency(lowestShare);
  return '${formatCurrency(lowestShare)}–${formatCurrency(highestShare)}';
}

List<int> calculateMemberShares(
  int totalInCents,
  int memberCount, {
  bool useSampleShares = false,
}) {
  if (memberCount <= 0) return const [];
  if (useSampleShares && memberCount == shares.length) return shares;

  final baseShare = totalInCents ~/ memberCount;
  final remainder = totalInCents % memberCount;
  return List<int>.generate(
    memberCount,
    (index) => baseShare + (index < remainder ? 1 : 0),
  );
}