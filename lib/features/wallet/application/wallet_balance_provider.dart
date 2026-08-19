import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

class WalletBalanceNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final authUser = ref.watch(authStateProvider).value;
    if (authUser == null) return 0;
    return fetchBalance();
  }

  Future<int> fetchBalance() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get('/api/wallet/balance');
      if (response.statusCode == 200 && response.data != null) {
        final balance = (response.data['balance'] as num?)?.toInt() ?? 0;
        state = AsyncData(balance);
        return balance;
      }
    } catch (_) {}
    return state.value ?? 0;
  }

  void setBalance(int newBalance) {
    state = AsyncData(newBalance);
  }
}

final walletBalanceProvider = AsyncNotifierProvider<WalletBalanceNotifier, int>(
  WalletBalanceNotifier.new,
);
