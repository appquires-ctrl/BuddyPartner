import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

// ── Dashboard Stats Provider ────────────────────────────────────────────────
final dashboardStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ApiService.get('/stats');
  return res['stats'] as Map<String, dynamic>;
});

// ── Users Management State & Provider ────────────────────────────────────────
class UsersState {
  final bool isLoading;
  final List<dynamic> users;
  final int total;
  final int page;
  final int totalPages;
  final String search;
  final String gender;
  final String isBanned;
  final String? error;

  const UsersState({
    this.isLoading = false,
    this.users = const [],
    this.total = 0,
    this.page = 1,
    this.totalPages = 1,
    this.search = '',
    this.gender = 'all',
    this.isBanned = 'all',
    this.error,
  });

  UsersState copyWith({
    bool? isLoading,
    List<dynamic>? users,
    int? total,
    int? page,
    int? totalPages,
    String? search,
    String? gender,
    String? isBanned,
    String? error,
  }) {
    return UsersState(
      isLoading: isLoading ?? this.isLoading,
      users: users ?? this.users,
      total: total ?? this.total,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      search: search ?? this.search,
      gender: gender ?? this.gender,
      isBanned: isBanned ?? this.isBanned,
      error: error,
    );
  }
}

class UsersNotifier extends StateNotifier<UsersState> {
  UsersNotifier() : super(const UsersState()) {
    fetchUsers();
  }

  Future<void> fetchUsers() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await ApiService.get('/users', queryParams: {
        'search': state.search,
        'gender': state.gender,
        'isBanned': state.isBanned,
        'page': state.page.toString(),
        'limit': '15',
      });
      state = state.copyWith(
        isLoading: false,
        users: res['users'] as List<dynamic>,
        total: res['total'] as int,
        totalPages: res['totalPages'] as int,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setSearch(String query) {
    state = state.copyWith(search: query, page: 1);
    fetchUsers();
  }

  void setGender(String gender) {
    state = state.copyWith(gender: gender, page: 1);
    fetchUsers();
  }

  void setIsBanned(String isBanned) {
    state = state.copyWith(isBanned: isBanned, page: 1);
    fetchUsers();
  }

  void setPage(int page) {
    if (page >= 1 && page <= state.totalPages) {
      state = state.copyWith(page: page);
      fetchUsers();
    }
  }

  Future<bool> toggleBan(String userId, bool currentBanStatus) async {
    try {
      final endpoint = currentBanStatus ? '/users/$userId/unban' : '/users/$userId/ban';
      await ApiService.post(endpoint);
      await fetchUsers();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final usersProvider = StateNotifierProvider<UsersNotifier, UsersState>((ref) {
  return UsersNotifier();
});

final userDetailProvider = FutureProvider.family.autoDispose<Map<String, dynamic>?, String>((ref, userId) async {
  try {
    final res = await ApiService.get('/users/$userId/detail');
    return res['user'] as Map<String, dynamic>;
  } catch (e) {
    return null;
  }
});

// ── Reports Queue State & Provider ──────────────────────────────────────────
class ReportsState {
  final bool isLoading;
  final List<dynamic> reports;
  final int total;
  final int page;
  final int totalPages;
  final String? error;

  const ReportsState({
    this.isLoading = false,
    this.reports = const [],
    this.total = 0,
    this.page = 1,
    this.totalPages = 1,
    this.error,
  });

  ReportsState copyWith({
    bool? isLoading,
    List<dynamic>? reports,
    int? total,
    int? page,
    int? totalPages,
    String? error,
  }) {
    return ReportsState(
      isLoading: isLoading ?? this.isLoading,
      reports: reports ?? this.reports,
      total: total ?? this.total,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      error: error,
    );
  }
}

class ReportsNotifier extends StateNotifier<ReportsState> {
  ReportsNotifier() : super(const ReportsState()) {
    fetchReports();
  }

  Future<void> fetchReports() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await ApiService.get('/reports', queryParams: {
        'page': state.page.toString(),
        'limit': '15',
      });
      state = state.copyWith(
        isLoading: false,
        reports: res['reports'] as List<dynamic>,
        total: res['total'] as int,
        totalPages: res['totalPages'] as int,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setPage(int page) {
    if (page >= 1 && page <= state.totalPages) {
      state = state.copyWith(page: page);
      fetchReports();
    }
  }
}

final reportsProvider = StateNotifierProvider<ReportsNotifier, ReportsState>((ref) {
  return ReportsNotifier();
});

// ── Withdrawal Requests State & Provider ─────────────────────────────────────
class WithdrawalsState {
  final bool isLoading;
  final List<dynamic> withdrawals;
  final int total;
  final int page;
  final int totalPages;
  final String status;
  final String? error;

  const WithdrawalsState({
    this.isLoading = false,
    this.withdrawals = const [],
    this.total = 0,
    this.page = 1,
    this.totalPages = 1,
    this.status = 'all',
    this.error,
  });

  WithdrawalsState copyWith({
    bool? isLoading,
    List<dynamic>? withdrawals,
    int? total,
    int? page,
    int? totalPages,
    String? status,
    String? error,
  }) {
    return WithdrawalsState(
      isLoading: isLoading ?? this.isLoading,
      withdrawals: withdrawals ?? this.withdrawals,
      total: total ?? this.total,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      status: status ?? this.status,
      error: error,
    );
  }
}

class WithdrawalsNotifier extends StateNotifier<WithdrawalsState> {
  WithdrawalsNotifier() : super(const WithdrawalsState()) {
    fetchWithdrawals();
  }

  Future<void> fetchWithdrawals() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await ApiService.get('/withdrawals', queryParams: {
        'status': state.status,
        'page': state.page.toString(),
        'limit': '15',
      });
      state = state.copyWith(
        isLoading: false,
        withdrawals: res['withdrawals'] as List<dynamic>,
        total: res['total'] as int,
        totalPages: res['totalPages'] as int,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setStatus(String status) {
    state = state.copyWith(status: status, page: 1);
    fetchWithdrawals();
  }

  void setPage(int page) {
    if (page >= 1 && page <= state.totalPages) {
      state = state.copyWith(page: page);
      fetchWithdrawals();
    }
  }

  Future<bool> updateStatus(String id, String newStatus) async {
    try {
      await ApiService.patch('/withdrawals/$id/status', body: {'status': newStatus});
      await fetchWithdrawals();
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

final withdrawalsProvider = StateNotifierProvider<WithdrawalsNotifier, WithdrawalsState>((ref) {
  return WithdrawalsNotifier();
});

// ── Transactions Provider ───────────────────────────────────────────────────
final transactionsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  final res = await ApiService.get('/transactions');
  return res['transactions'] as List<dynamic>;
});

// ── App Config / Version Management Provider ──────────────────────────────
final appConfigProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await ApiService.get('/app-config');
  return res['config'] as Map<String, dynamic>;
});
