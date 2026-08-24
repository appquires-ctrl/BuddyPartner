import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

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

class LastCallSummaryNotifier extends Notifier<CallSummaryInfo?> {
  @override
  CallSummaryInfo? build() {
    ref.listen(authStateProvider, (prev, next) {
      if (next.value == null || (prev?.value != null && prev?.value?.id != next.value?.id)) {
        state = null;
      }
    });
    return null;
  }

  void setSummary(CallSummaryInfo? summary) {
    state = summary;
  }
}

final lastCallSummaryProvider = NotifierProvider<LastCallSummaryNotifier, CallSummaryInfo?>(
  LastCallSummaryNotifier.new,
);

