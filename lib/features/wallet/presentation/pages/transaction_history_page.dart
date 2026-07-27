import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/core/services/api_client.dart';
import 'package:dating_app/core/widgets/feedback/app_empty_state.dart';
import 'package:dating_app/core/widgets/feedback/app_loading_indicator.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';
import 'package:dating_app/features/wallet/domain/wallet_transaction.dart';

final transactionHistoryProvider = StateNotifierProvider.autoDispose<
    TransactionHistoryNotifier, AsyncValue<List<WalletTransaction>>>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final user = ref.watch(authStateProvider).value;
  final isFemale = user?.gender.toLowerCase() == 'female';
  return TransactionHistoryNotifier(apiClient, isFemale);
});

class TransactionHistoryNotifier
    extends StateNotifier<AsyncValue<List<WalletTransaction>>> {
  final ApiClient _apiClient;
  final bool _isFemale;
  String? _nextCursor;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  TransactionHistoryNotifier(this._apiClient, this._isFemale)
      : super(const AsyncValue.loading()) {
    loadInitial();
  }

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;

  Future<void> loadInitial() async {
    state = const AsyncValue.loading();
    try {
      final endpoint =
          _isFemale ? '/api/roses/transactions' : '/api/wallet/transactions';
      final response = await _apiClient.dio.get(endpoint, queryParameters: {
        'limit': 20,
      });

      final list = (response.data['transactions'] as List)
          .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
          .toList();

      _nextCursor = response.data['nextCursor'] as String?;
      _hasMore = _nextCursor != null;
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore || state.value == null) return;
    _isLoadingMore = true;

    try {
      final endpoint =
          _isFemale ? '/api/roses/transactions' : '/api/wallet/transactions';
      final response = await _apiClient.dio.get(endpoint, queryParameters: {
        'limit': 20,
        if (_nextCursor != null) 'cursor': _nextCursor,
      });

      final newList = (response.data['transactions'] as List)
          .map((e) => WalletTransaction.fromJson(e as Map<String, dynamic>))
          .toList();

      _nextCursor = response.data['nextCursor'] as String?;
      _hasMore = _nextCursor != null;

      final current = state.value!;
      state = AsyncValue.data([...current, ...newList]);
    } catch (_) {
      // Keep existing list on loadMore failure
    } finally {
      _isLoadingMore = false;
    }
  }
}

class TransactionHistoryPage extends ConsumerStatefulWidget {
  const TransactionHistoryPage({super.key});

  @override
  ConsumerState<TransactionHistoryPage> createState() =>
      _TransactionHistoryPageState();
}

class _TransactionHistoryPageState
    extends ConsumerState<TransactionHistoryPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(transactionHistoryProvider.notifier).loadMore();
    }
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final user = ref.watch(authStateProvider).value;
    final isFemale = user?.gender.toLowerCase() == 'female';
    final currencyName = isFemale ? 'Roses' : 'Coins';

    final historyState = ref.watch(transactionHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Transaction History',
          style: typography.titleCard.copyWith(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colors.surface,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: historyState.when(
        loading: () => Center(
          child: AppLoadingIndicator(color: colors.primary),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: colors.danger),
                const SizedBox(height: 16),
                Text(
                  'Failed to load transaction history',
                  style: typography.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref
                      .read(transactionHistoryProvider.notifier)
                      .loadInitial(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (transactions) {
          if (transactions.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref
                  .read(transactionHistoryProvider.notifier)
                  .loadInitial(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 100),
                  AppEmptyState(
                    title: 'No Transactions Yet',
                    description:
                        'Your past $currencyName recharge, earnings, and spends will appear here.',
                    icon: Icons.receipt_long_rounded,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(transactionHistoryProvider.notifier).loadInitial(),
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppSpacing.space16),
              itemCount: transactions.length + 1,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index == transactions.length) {
                  final notifier =
                      ref.read(transactionHistoryProvider.notifier);
                  if (notifier.hasMore) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: AppLoadingIndicator(
                            size: 24, color: colors.primary),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }

                final tx = transactions[index];
                final isCredit = tx.type == 'credit';
                final iconData = isCredit
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded;
                final iconBg = isCredit
                    ? colors.success.withValues(alpha: 0.12)
                    : colors.danger.withValues(alpha: 0.12);
                final iconColor = isCredit ? colors.success : colors.danger;

                return Container(
                  padding: const EdgeInsets.all(AppSpacing.space16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: AppRadius.lg,
                    border: Border.all(
                        color: colors.border.withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: colors.textPrimary.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: iconBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(iconData, color: iconColor, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tx.reasonLabel,
                              style: typography.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatRelativeTime(tx.createdAt),
                              style: typography.bodySmall.copyWith(
                                color: colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${isCredit ? '+' : '-'}${tx.amount} $currencyName',
                        style: typography.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: iconColor,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
