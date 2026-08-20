import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/withdraw/application/rose_providers.dart';

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
  WithdrawState build() => const WithdrawState();

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
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Network or server error: $e',
      );
      return false;
    }
  }
}

final withdrawControllerProvider = NotifierProvider<WithdrawController, WithdrawState>(
  WithdrawController.new,
);
