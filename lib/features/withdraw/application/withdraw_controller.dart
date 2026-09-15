import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/withdraw/application/withdraw_providers.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';

class WithdrawState {
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const WithdrawState({
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  WithdrawState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
  }) {
    return WithdrawState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

class WithdrawController extends Notifier<WithdrawState> {
  @override
  WithdrawState build() {
    ref.listen(authStateProvider, (prev, next) {
      if (next.value == null || (prev?.value != null && prev?.value?.id != next.value?.id)) {
        state = const WithdrawState();
      }
    });
    return const WithdrawState();
  }

  Future<bool> requestWithdrawal(int amount) async {
    state = state.copyWith(isLoading: true, errorMessage: null, successMessage: null);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.post(
        '/api/withdrawals',
        data: {'amount': amount, 'coinAmount': amount, 'roseAmount': amount},
      );

      if (response.statusCode == 200 && response.data != null && response.data['success'] == true) {
        ref.invalidate(withdrawalHistoryProvider);
        ref.invalidate(dualWalletProvider);
        ref.invalidate(walletBalanceProvider);

        state = state.copyWith(
          isLoading: false,
          successMessage: 'Withdrawal request submitted successfully!',
        );
        return true;
      } else {
        final err = response.data?['error']?.toString() ?? 'Failed to submit withdrawal request.';
        state = state.copyWith(isLoading: false, errorMessage: err);
        return false;
      }
    } on DioException catch (e) {
      final serverErr = e.response?.data?['error']?.toString() ?? e.response?.data?['message']?.toString();
      state = state.copyWith(
        isLoading: false,
        errorMessage: serverErr ?? e.message ?? 'Failed to submit withdrawal request.',
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }
}


final withdrawControllerProvider = NotifierProvider<WithdrawController, WithdrawState>(
  WithdrawController.new,
);
