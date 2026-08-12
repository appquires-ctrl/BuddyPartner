import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/widgets/feedback/app_empty_state.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/app/router/route_names.dart';

class SubscriptionItem {
  final String id;
  final int planDurationDays;
  final int amountPaid;
  final DateTime startedAt;
  final DateTime expiresAt;
  final String? paymentReference;
  final DateTime createdAt;

  SubscriptionItem({
    required this.id,
    required this.planDurationDays,
    required this.amountPaid,
    required this.startedAt,
    required this.expiresAt,
    this.paymentReference,
    required this.createdAt,
  });

  factory SubscriptionItem.fromJson(Map<String, dynamic> json) {
    return SubscriptionItem(
      id: json['id'] as String? ?? '',
      planDurationDays: (json['plan_duration_days'] as num?)?.toInt() ??
          (json['planDurationDays'] as num?)?.toInt() ??
          1,
      amountPaid: (json['amount_paid'] as num?)?.toInt() ??
          (json['amountPaid'] as num?)?.toInt() ??
          0,
      startedAt: json['started_at'] != null
          ? DateTime.tryParse(json['started_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      paymentReference: json['payment_reference'] as String? ??
          json['paymentReference'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String get planLabel {
    if (planDurationDays == 1) return '1 Day Plan';
    if (planDurationDays == 7) return '7 Days Plan';
    if (planDurationDays == 30) return '1 Month (30 Days) Plan';
    if (planDurationDays == 365) return '1 Year (365 Days) Plan';
    return '$planDurationDays Days Subscription';
  }

  bool get isActive => expiresAt.isAfter(DateTime.now());
}

final subscriptionHistoryProvider = StateNotifierProvider.autoDispose<
    SubscriptionHistoryNotifier, AsyncValue<List<SubscriptionItem>>>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return SubscriptionHistoryNotifier(apiClient);
});

class SubscriptionHistoryNotifier
    extends StateNotifier<AsyncValue<List<SubscriptionItem>>> {
  final ApiClient _apiClient;

  SubscriptionHistoryNotifier(this._apiClient)
      : super(const AsyncValue.loading()) {
    loadInitial();
  }

  Future<void> loadInitial() async {
    state = const AsyncValue.loading();
    try {
      final response = await _apiClient.dio.get('/api/subscriptions/history');
      if (response.data != null && response.data['subscriptions'] != null) {
        final list = (response.data['subscriptions'] as List)
            .map((e) => SubscriptionItem.fromJson(e as Map<String, dynamic>))
            .toList();
        state = AsyncValue.data(list);
        return;
      }
    } catch (_) {
      // Graceful fallback for local dev / unauthenticated state
    }
    state = const AsyncValue.data([]);
  }
}

class TransactionHistoryPage extends ConsumerWidget {
  const TransactionHistoryPage({super.key});

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final historyState = ref.watch(subscriptionHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => context.pop(),
        ),
        centerTitle: true,
        title: Column(
          children: [
            Text(
              'Subscription History',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'View your payment history',
              style: typography.bodySmall.copyWith(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
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
                  'Failed to load subscription history',
                  style: typography.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref
                      .read(subscriptionHistoryProvider.notifier)
                      .loadInitial(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (subscriptions) {
          if (subscriptions.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref
                  .read(subscriptionHistoryProvider.notifier)
                  .loadInitial(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  AppEmptyState(
                    title: 'No Active Subscriptions',
                    description:
                        'Subscribe now to enjoy unlimited voice & video calls, matchmaking, and chat.',
                    icon: Icons.card_membership_rounded,
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () => context.push(RouteNames.subscribe),
                      icon: const Icon(Icons.star_rounded, color: Colors.white),
                      label: const Text('View Subscription Plans'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B4EFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(subscriptionHistoryProvider.notifier).loadInitial(),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.space16),
              itemCount: subscriptions.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final sub = subscriptions[index];
                final isActive = sub.isActive;
                final statusBg = isActive
                    ? colors.success.withValues(alpha: 0.12)
                    : colors.textSecondary.withValues(alpha: 0.12);
                final statusColor =
                    isActive ? colors.success : colors.textSecondary;

                return Container(
                  padding: const EdgeInsets.all(AppSpacing.space16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: AppRadius.lg,
                    border: Border.all(
                      color: isActive
                          ? colors.success.withValues(alpha: 0.4)
                          : colors.border.withValues(alpha: 0.5),
                    ),
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
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6B4EFF).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF6B4EFF),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  sub.planLabel,
                                  style: typography.bodyMedium.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusBg,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    isActive ? 'ACTIVE' : 'EXPIRED',
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Purchased ${_formatRelativeTime(sub.createdAt)}',
                              style: typography.bodySmall.copyWith(
                                color: colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${sub.amountPaid}',
                        style: typography.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                          fontSize: 16,
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
