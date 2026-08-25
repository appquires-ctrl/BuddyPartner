import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/wallet/domain/wallet_transaction.dart';

/// Fetches user's wallet / coin transactions history
final walletTransactionsProvider =
    FutureProvider.autoDispose<List<WalletTransaction>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);

  try {
    final response = await apiClient.dio.get('/api/wallet/transactions');
    if (response.statusCode == 200 && response.data != null) {
      final data = response.data;
      final List list = (data is List)
          ? data
          : (data['transactions'] as List? ??
              data['history'] as List? ??
              data['data'] as List? ??
              []);
      return list
          .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  } catch (_) {
    // Attempt fallback endpoint /api/wallet/history
    try {
      final response = await apiClient.dio.get('/api/wallet/history');
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final List list = (data is List)
            ? data
            : (data['transactions'] as List? ??
                data['history'] as List? ??
                data['data'] as List? ??
                []);
        return list
            .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
  }

  return const <WalletTransaction>[];
});
