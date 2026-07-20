import 'package:flutter_riverpod/flutter_riverpod.dart';

class CallSummaryInfo {
  final String matchedUserId;
  final String matchedUserName;
  final String? matchedUserAvatar;
  final int durationSeconds;
  final int totalCost;

  CallSummaryInfo({
    required this.matchedUserId,
    required this.matchedUserName,
    this.matchedUserAvatar,
    required this.durationSeconds,
    required this.totalCost,
  });
}

final lastCallSummaryProvider = StateProvider<CallSummaryInfo?>((ref) => null);
