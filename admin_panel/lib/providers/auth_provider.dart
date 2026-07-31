import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    checkAuthStatus();
  }

  Future<void> checkAuthStatus() async {
    state = state.copyWith(isLoading: true);
    final token = await ApiService.getToken();
    if (token != null && token.isNotEmpty) {
      state = state.copyWith(isAuthenticated: true, isLoading: false);
    } else {
      state = state.copyWith(isAuthenticated: false, isLoading: false);
    }
  }

  /// Handles password verification with mandatory client-side `_` prefix gate
  Future<bool> login(String password) async {
    state = state.copyWith(isLoading: true, error: null);

    // Client-side prefix gate rule per Section 2
    if (!password.startsWith('_')) {
      // 0 network requests triggered
      state = state.copyWith(
        isLoading: false,
        isAuthenticated: false,
        error: 'Wrong password',
      );
      return false;
    }

    // Strip leading '_' prefix before sending to backend
    final strippedPassword = password.substring(1);

    try {
      final res = await ApiService.post('/login', body: {'password': strippedPassword});
      if (res != null && res['token'] != null) {
        final token = res['token'] as String;
        await ApiService.saveToken(token);
        state = state.copyWith(isAuthenticated: true, isLoading: false, error: null);
        return true;
      } else {
        state = state.copyWith(isLoading: false, error: 'Invalid response from server');
        return false;
      }
    } catch (e) {
      final cleanError = e.toString().replaceAll('Exception: ', '');
      state = state.copyWith(isLoading: false, error: cleanError);
      return false;
    }
  }

  Future<void> logout() async {
    await ApiService.clearToken();
    state = const AuthState(isAuthenticated: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
