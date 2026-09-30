import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../providers/admin_providers.dart';
import '../../../../theme/admin_colors.dart';
import '../../../../theme/admin_theme.dart';

class RechargesPage extends ConsumerStatefulWidget {
  const RechargesPage({super.key});

  @override
  ConsumerState<RechargesPage> createState() => _RechargesPageState();
}

class _RechargesPageState extends ConsumerState<RechargesPage> {
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    ref.read(rechargesProvider.notifier).setSearch(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rechargesProvider);
    final stats = state.stats;
    final totalCash = (stats['totalCashRevenue'] as num?)?.toDouble() ?? 0;
    final todayCash = (stats['todayCashRevenue'] as num?)?.toDouble() ?? 0;
    final coinCash = (stats['totalCoinCash'] as num?)?.toDouble() ?? 0;
    final coinsSold = (stats['totalCoinsSold'] as num?)?.toInt() ?? 0;
    final coinOrders = (stats['totalCoinOrders'] as num?)?.toInt() ?? 0;
    final subCash = (stats['totalSubCash'] as num?)?.toDouble() ?? 0;
    final paidSubs = (stats['totalPaidSubs'] as num?)?.toInt() ?? 0;
    final adminGrants = (stats['totalAdminGrants'] as num?)?.toInt() ?? 0;
    final allCount = coinOrders + paidSubs + adminGrants;

    final dateFormat = DateFormat('dd MMM yyyy • hh:mm a');

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Section ────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Recharges & Orders Hub',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Live audit of Google Play coin recharges, VIP memberships, and granted benefits',
                    style: TextStyle(
                      fontSize: 13,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => ref.read(rechargesProvider.notifier).fetchRecharges(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh Orders'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.surface,
                  foregroundColor: AdminColors.primary,
                  side: const BorderSide(color: AdminColors.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Summary Cards ─────────────────────────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final double cardWidth = (constraints.maxWidth - 48) / 4;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildStatCard(
                    title: 'Total Inflow Revenue',
                    value: _currencyFormatter.format(totalCash),
                    subtitle: 'All-time verified payments',
                    icon: Icons.payments_rounded,
                    accentColor: const Color(0xFF10B981),
                    width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  ),
                  _buildStatCard(
                    title: 'Today\'s Cash Inflow',
                    value: _currencyFormatter.format(todayCash),
                    subtitle: 'Recorded transactions today',
                    icon: Icons.trending_up_rounded,
                    accentColor: const Color(0xFF3B82F6),
                    width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  ),
                  _buildStatCard(
                    title: 'Coin Packs Cash',
                    value: _currencyFormatter.format(coinCash),
                    subtitle: '${NumberFormat('#,##0').format(coinsSold)} coins ($coinOrders orders)',
                    icon: Icons.monetization_on_rounded,
                    accentColor: const Color(0xFFF59E0B),
                    width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  ),
                  _buildStatCard(
                    title: 'VIP Subscriptions Cash',
                    value: _currencyFormatter.format(subCash),
                    subtitle: '$paidSubs paid memberships sold',
                    icon: Icons.workspace_premium_rounded,
                    accentColor: const Color(0xFF8B5CF6),
                    width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // ── Search & Filter Controls ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminColors.border),
            ),
            child: Row(
              children: [
                // Search Input
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: _onSearch,
                    decoration: InputDecoration(
                      hintText: 'Search by user name, phone, or GPA order ID...',
                      hintStyle: const TextStyle(fontSize: 13, color: AdminColors.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AdminColors.textSecondary),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _onSearch('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AdminColors.surfaceMuted,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Filter Buttons Bar
                _buildFilterButton('all', allCount > 0 ? 'All ($allCount)' : 'All', state.filter),
                const SizedBox(width: 8),
                _buildFilterButton('coins', coinOrders > 0 ? '🪙 Coin Packs ($coinOrders)' : '🪙 Coin Packs', state.filter),
                const SizedBox(width: 8),
                _buildFilterButton('subscriptions', paidSubs > 0 ? '👑 Subscriptions ($paidSubs)' : '👑 Subscriptions', state.filter),
                const SizedBox(width: 8),
                _buildFilterButton('admin_grants', adminGrants > 0 ? '🎁 Admin Grants ($adminGrants)' : '🎁 Admin Grants', state.filter),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Recharges Data Table ──────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AdminColors.border),
            ),
            child: state.isLoading
                ? const Padding(
                    padding: EdgeInsets.all(60.0),
                    child: Center(child: CircularProgressIndicator(color: AdminColors.primary)),
                  )
                : state.error != null
                    ? Padding(
                        padding: const EdgeInsets.all(40.0),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 36, color: AdminColors.danger),
                              const SizedBox(height: 8),
                              Text(state.error!, style: const TextStyle(color: AdminColors.danger, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => ref.read(rechargesProvider.notifier).fetchRecharges(),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : state.recharges.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(60.0),
                            child: Center(
                              child: Text(
                                'No recharge or subscription orders found matching your filters.',
                                style: TextStyle(color: AdminColors.textSecondary),
                              ),
                            ),
                          )
                        : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(AdminColors.surfaceMuted),
                                horizontalMargin: 20,
                                columnSpacing: 24,
                                columns: const [
                                  DataColumn(label: Text('User', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Plan / Product', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Amount Paid', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Credits / Value', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Order ID / Reference', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Purchased At', style: TextStyle(fontWeight: FontWeight.bold))),
                                  DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                                ],
                                rows: state.recharges.map((r) {
                                  final userName = r['user_name'] ?? 'User';
                                  final phone = r['phone'] ?? '';
                                  final type = r['recharge_type'] ?? 'coin_pack';
                                  final displayName = r['display_name'] ?? r['product_id'] ?? '';
                                  final amount = (r['amount_paid'] as num?)?.toDouble() ?? 0;
                                  final benefit = r['benefit_label'] ?? '';
                                  final orderId = r['order_id'] ?? '-';
                                  final status = r['status'] ?? 'COMPLETED';
                                  final createdAtStr = r['created_at'];
                                  DateTime? createdDate;
                                  if (createdAtStr != null) {
                                    createdDate = DateTime.tryParse(createdAtStr);
                                  }

                                  return DataRow(
                                    cells: [
                                      // USER
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircleAvatar(
                                              radius: 16,
                                              backgroundColor: AdminColors.primary.withValues(alpha: 0.1),
                                              child: Text(
                                                userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: AdminColors.primary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  userName,
                                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AdminColors.textPrimary),
                                                ),
                                                if (phone.isNotEmpty)
                                                  Text(
                                                    phone,
                                                    style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      // TYPE
                                      DataCell(_buildTypeBadge(type)),

                                      // PLAN / PRODUCT
                                      DataCell(
                                        Text(
                                          displayName,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                      ),

                                      // AMOUNT PAID
                                      DataCell(
                                        Text(
                                          amount > 0 ? _currencyFormatter.format(amount) : 'FREE',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: amount > 0 ? AdminColors.textPrimary : const Color(0xFF10B981),
                                          ),
                                        ),
                                      ),

                                      // CREDITS / VALUE
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: type == 'coin_pack'
                                                ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                                                : const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            benefit,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: type == 'coin_pack'
                                                  ? const Color(0xFFD97706)
                                                  : const Color(0xFF7C3AED),
                                            ),
                                          ),
                                        ),
                                      ),

                                      // ORDER ID
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              orderId.length > 20 ? '${orderId.substring(0, 18)}...' : orderId,
                                              style: AdminTheme.tabularNumeralStyle.copyWith(
                                                fontSize: 12,
                                                color: AdminColors.textSecondary,
                                              ),
                                            ),
                                            if (orderId != '-' && orderId != 'ADMIN_GRANT')
                                              IconButton(
                                                icon: const Icon(Icons.copy_rounded, size: 14, color: AdminColors.textMuted),
                                                tooltip: 'Copy Order ID ($orderId)',
                                                onPressed: () {
                                                  Clipboard.setData(ClipboardData(text: orderId));
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text('Order ID copied: $orderId'),
                                                      duration: const Duration(seconds: 2),
                                                    ),
                                                  );
                                                },
                                              ),
                                          ],
                                        ),
                                      ),

                                      // DATE
                                      DataCell(
                                        Text(
                                          createdDate != null ? dateFormat.format(createdDate.toLocal()) : '-',
                                          style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                                        ),
                                      ),

                                      // STATUS
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AdminColors.successBg,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            status.toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: AdminColors.success,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),

                          // ── Pagination Bar ────────────────────────────────
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: AdminColors.border)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Showing ${state.recharges.length} of ${state.total} recharges',
                                  style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                                ),
                                Row(
                                  children: [
                                    OutlinedButton(
                                      onPressed: state.page > 1
                                          ? () => ref.read(rechargesProvider.notifier).setPage(state.page - 1)
                                          : null,
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      ),
                                      child: const Text('Previous'),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Page ${state.page} of ${state.totalPages}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: state.page < state.totalPages
                                          ? () => ref.read(rechargesProvider.notifier).setPage(state.page + 1)
                                          : null,
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      ),
                                      child: const Text('Next'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AdminColors.textSecondary),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AdminColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: AdminColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton(String key, String label, String currentFilter) {
    final bool isSelected = currentFilter == key;
    return ElevatedButton(
      onPressed: () => ref.read(rechargesProvider.notifier).setFilter(key),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? AdminColors.primary : AdminColors.surfaceMuted,
        foregroundColor: isSelected ? Colors.white : AdminColors.textPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    if (type == 'coin_pack') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.monetization_on_rounded, size: 13, color: Color(0xFFD97706)),
            SizedBox(width: 4),
            Text(
              'COINS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
            ),
          ],
        ),
      );
    } else if (type == 'subscription') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.workspace_premium_rounded, size: 13, color: Color(0xFF7C3AED)),
            SizedBox(width: 4),
            Text(
              'VIP SUB',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED)),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0D9488).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.card_giftcard_rounded, size: 13, color: Color(0xFF0F766E)),
            SizedBox(width: 4),
            Text(
              'GIFT',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
            ),
          ],
        ),
      );
    }
  }
}
