import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../theme/admin_colors.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final formatter = NumberFormat('#,##0');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Dashboard Overview',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Real-time stats and metrics across BuddyPartner platform',
                    style: TextStyle(
                      fontSize: 13,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () {
                  ref.invalidate(dashboardStatsProvider);
                  ref.invalidate(appConfigProvider);
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh Data'),
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

          // Version Gate Management Card
          // const VersionManagementCard(),
          // const SizedBox(height: 24),

          // Stat Cards Grid
          statsAsync.when(
            data: (stats) {
              final totalUsers = stats['totalUsers'] as int? ?? 0;
              final maleUsers = stats['maleUsers'] as int? ?? 0;
              final femaleUsers = stats['femaleUsers'] as int? ?? 0;
              final pendingWithdrawals = stats['pendingWithdrawals'] as int? ?? 0;
              final reportsToday = stats['reportsToday'] as int? ?? 0;
              final reportsWeek = stats['reportsThisWeek'] as int? ?? 0;
              final coinsRecharged = stats['totalCoinsRecharged'] as int? ?? 0;
              final rosesPaid = stats['totalRosesPaidOut'] as int? ?? 0;

              return LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount = constraints.maxWidth > 1100
                      ? 3
                      : constraints.maxWidth > 700
                          ? 2
                          : 1;

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    childAspectRatio: 1.8,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      StatCard(
                        title: 'Total Users',
                        value: formatter.format(totalUsers),
                        trendLabel: 'Active Base',
                        subtitle: '$maleUsers M / $femaleUsers F',
                        icon: Icons.people_alt_rounded,
                        iconColor: AdminColors.primary,
                        iconBgColor: AdminColors.activePillBg,
                      ),
                      StatCard(
                        title: 'Pending Withdrawals',
                        value: formatter.format(pendingWithdrawals),
                        trendLabel: 'Action Required',
                        subtitle: 'Payout requests',
                        icon: Icons.account_balance_wallet_rounded,
                        iconColor: AdminColors.warning,
                        iconBgColor: AdminColors.warningBg,
                      ),
                      StatCard(
                        title: 'Reports Queue',
                        value: formatter.format(reportsToday),
                        trendLabel: 'Today',
                        subtitle: '$reportsWeek this week',
                        icon: Icons.shield_rounded,
                        iconColor: AdminColors.danger,
                        iconBgColor: AdminColors.dangerBg,
                      ),
                      StatCard(
                        title: 'Coins Recharged',
                        value: '🪙 ${formatter.format(coinsRecharged)}',
                        trendLabel: 'Revenue Proxy',
                        subtitle: 'In-app purchases',
                        icon: Icons.monetization_on_rounded,
                        iconColor: const Color(0xFFF59E0B),
                        iconBgColor: const Color(0xFFFEF3C7),
                      ),
                      StatCard(
                        title: 'Roses Paid Out',
                        value: '🌹 ${formatter.format(rosesPaid)}',
                        trendLabel: 'Approved Payouts',
                        subtitle: 'Creator earnings',
                        icon: Icons.local_florist_rounded,
                        iconColor: const Color(0xFFEC4899),
                        iconBgColor: const Color(0xFFFCE7F3),
                      ),
                    ],
                  );
                },
              );
            },
            loading: () => const SizedBox(
              height: 250,
              child: Center(
                child: CircularProgressIndicator(color: AdminColors.primary),
              ),
            ),
            error: (err, stack) => Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AdminColors.dangerBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Failed to load dashboard metrics: $err',
                style: const TextStyle(color: AdminColors.danger, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
