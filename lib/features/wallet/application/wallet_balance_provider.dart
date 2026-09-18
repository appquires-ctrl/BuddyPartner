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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserWalletState &&
          runtimeType == other.runtimeType &&
          spendableBalance == other.spendableBalance &&
          earnedBalance == other.earnedBalance &&
          balance == other.balance;

  @override
  int get hashCode =>
      spendableBalance.hashCode ^ earnedBalance.hashCode ^ balance.hashCode;
}

class DualWalletNotifier extends AsyncNotifier<UserWalletState> {
  Future<UserWalletState>? _inFlightFetch;
  DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(seconds: 15);

  @override
  Future<UserWalletState> build() async {
    final authUser = ref.watch(authStateProvider).value;
    if (authUser == null) return const UserWalletState();
    return fetchWallet();
  }

  Future<UserWalletState> fetchWallet({bool force = false}) async {
    final authUser = ref.read(authStateProvider).value;
    if (authUser == null) {
      state = const AsyncData(UserWalletState());
      return const UserWalletState();
    }

    final now = DateTime.now();
    if (!force &&
        state.hasValue &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!) < _cacheDuration) {
      return state.value!;
    }

    if (_inFlightFetch != null) {
      return _inFlightFetch!;
    }

    _inFlightFetch = _executeFetchWallet();
    try {
      return await _inFlightFetch!;
    } finally {
      _inFlightFetch = null;
    }
  }

  Future<UserWalletState> _executeFetchWallet() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get('/api/wallet/balance');
      if (response.statusCode == 200 && response.data != null) {
        final wallet = UserWalletState.fromJson(Map<String, dynamic>.from(response.data));
        _lastFetchTime = DateTime.now();
        state = AsyncData(wallet);
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

    if (cur.spendableBalance == s && cur.earnedBalance == e && cur.balance == b) {
      return;
    }

    state = AsyncData(UserWalletState(spendableBalance: s, earnedBalance: e, balance: b));
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
    // Directly await dualWalletProvider future to stay in sync without a parallel network call
    final dualWallet = await ref.watch(dualWalletProvider.future);
    return dualWallet.balance;
  }

  Future<int> fetchBalance({bool force = false}) async {
    final wallet = await ref.read(dualWalletProvider.notifier).fetchWallet(force: force);
    state = AsyncData(wallet.balance);
    return wallet.balance;
  }

  void setBalance(int newBalance) {
    if (state.value == newBalance) return;
    state = AsyncData(newBalance);
    final curDual = ref.read(dualWalletProvider).value;
    if (curDual == null || curDual.balance != newBalance) {
      ref.read(dualWalletProvider.notifier).updateBalances(total: newBalance);
    }
  }
}

final walletBalanceProvider = AsyncNotifierProvider<WalletBalanceNotifier, int>(
  WalletBalanceNotifier.new,
);
