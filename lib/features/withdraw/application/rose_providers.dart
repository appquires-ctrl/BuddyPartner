import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/core/services/api_client.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';



/// Withdrawal request model
class WithdrawalRequest {
  final String id;
  final int roseAmount;
  final int rupeeAmount;
  final String status;
  final DateTime requestedAt;
  final DateTime? processedAt;

  WithdrawalRequest({
    required this.id,
    required this.roseAmount,
    required this.rupeeAmount,
    required this.status,
    required this.requestedAt,
    this.processedAt,
  });

  factory WithdrawalRequest.fromJson(Map<String, dynamic> json) {
    return WithdrawalRequest(
      id: json['id'] as String,
      roseAmount: (json['rose_amount'] as num).toInt(),
      rupeeAmount: (json['rupee_amount'] as num).toInt(),
      status: json['status'] as String,
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
