import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';



/// Withdrawal request model
class WithdrawalRequest {
  final String id;
  final int coinAmount;
  final int rupeeAmount;
  final String status;
  final DateTime requestedAt;
  final DateTime? processedAt;

  int get roseAmount => coinAmount;

  WithdrawalRequest({
    required this.id,
    required this.coinAmount,
    required this.rupeeAmount,
    required this.status,
    required this.requestedAt,
    this.processedAt,
  });

  factory WithdrawalRequest.fromJson(Map<String, dynamic> json) {
    final rawAmount = (json['coin_amount'] ?? json['rose_amount'] ?? json['amount'] ?? 0) as num;
    return WithdrawalRequest(
      id: json['id'] as String,
      coinAmount: rawAmount.toInt(),
      rupeeAmount: (json['rupee_amount'] as num?)?.toInt() ?? rawAmount.toInt(),
      status: json['status'] as String? ?? 'pending',
      requestedAt: DateTime.parse(json['requested_at'] as String),
      processedAt: json['processed_at'] != null
          ? DateTime.parse(json['processed_at'] as String)
          : null,
    );
  }
}

/// Fetches withdrawal history
final withdrawalHistoryProvider = FutureProvider<List<WithdrawalRequest>>((ref) async {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  if (user == null) return [];

  try {
    final apiClient = ref.watch(apiClientProvider);
    final response = await apiClient.dio.get('/api/withdrawals');
    if (response.data != null && response.data['withdrawals'] != null) {
      final list = response.data['withdrawals'] as List;
      return list
          .map((e) => WithdrawalRequest.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  } catch (e) {
    // Return empty on error
  }
  return [];
});
