import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

class UserWalletState {
  final int spendableBalance;
  final int earnedBalance;
  final int balance;

  const UserWalletState({
    this.spendableBalance = 0,
    this.earnedBalance = 0,
    this.balance = 0,
  });

  factory UserWalletState.fromJson(Map<String, dynamic> json) {
    final s = (json['spendableBalance'] as num?)?.toInt() ?? 0;
    final e = (json['earnedBalance'] as num?)?.toInt() ?? 0;
    final b = (json['balance'] as num?)?.toInt() ?? (s + e);
    return UserWalletState(
      spendableBalance: s,
      earnedBalance: e,
      balance: b,
    );
  }
}

class DualWalletNotifier extends AsyncNotifier<UserWalletState> {
  @override
  Future<UserWalletState> build() async {
    final authUser = ref.watch(authStateProvider).value;
    if (authUser == null) return const UserWalletState();
    return fetchWallet();
  }

  Future<UserWalletState> fetchWallet() async {
    final authUser = ref.read(authStateProvider).value;
    if (authUser == null) {
      state = const AsyncData(UserWalletState());
      return const UserWalletState();
    }

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get('/api/wallet/balance');
      if (response.statusCode == 200 && response.data != null) {
        final wallet = UserWalletState.fromJson(Map<String, dynamic>.from(response.data));
        state = AsyncData(wallet);
        // Also keep legacy total balance in sync
        ref.read(walletBalanceProvider.notifier).setBalance(wallet.balance);
        return wallet;
      }
    } catch (_) {}
    return state.value ?? const UserWalletState();
  }

  void updateBalances({int? spendable, int? earned, int? total}) {
    final cur = state.value ?? const UserWalletState();
    final s = spendable ?? cur.spendableBalance;
    final e = earned ?? cur.earnedBalance;
    final b = total ?? (s + e);
    final next = UserWalletState(spendableBalance: s, earnedBalance: e, balance: b);
    state = AsyncData(next);
    ref.read(walletBalanceProvider.notifier).setBalance(b);
  }
}

final dualWalletProvider = AsyncNotifierProvider<DualWalletNotifier, UserWalletState>(
  DualWalletNotifier.new,
);

class WalletBalanceNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final authUser = ref.watch(authStateProvider).value;
    if (authUser == null) return 0;
    return fetchBalance();
  }

  Future<int> fetchBalance() async {
    final authUser = ref.read(authStateProvider).value;
    if (authUser == null) {
      state = const AsyncData(0);
      return 0;
    }

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get('/api/wallet/balance');
      if (response.statusCode == 200 && response.data != null) {
        final wallet = UserWalletState.fromJson(Map<String, dynamic>.from(response.data));
        state = AsyncData(wallet.balance);
        // Update dualWalletProvider if not loading
        ref.read(dualWalletProvider.notifier).state = AsyncData(wallet);
        return wallet.balance;
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
