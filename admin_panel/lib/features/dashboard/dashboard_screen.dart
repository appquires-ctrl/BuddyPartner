import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../theme/admin_colors.dart';
import '../../providers/admin_providers.dart';
import '../../widgets/stat_card.dart';
import 'version_management_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final telemetryAsync = ref.watch(liveTelemetryProvider);
    final formatter = NumberFormat('#,##0');
    final currencyFormatter = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    final telemetry = telemetryAsync.valueOrNull;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Platform Telemetry & Command Center',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AdminColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Live 5,000 CCU concurrent user tracking, active in-call channels, and circulating ledger balance',
                      style: TextStyle(
                        fontSize: 13,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
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

          // ── Real-Time 5,000 CCU Pulse Cards ──────────────────────────────
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 1100
                  ? 4
                  : constraints.maxWidth > 750
                      ? 2
                      : 1;

              final liveCcu = telemetry?['ccu'] ?? 0;
              final activeCalls = telemetry?['activeCalls'] ?? 0;
              final subRevToday = telemetry?['subRevenueToday'] ?? 0;
              final subsSoldToday = telemetry?['subsSoldToday'] ?? 0;
              final system = telemetry?['system'] as Map<String, dynamic>?;
              final memRss = system?['memoryRssMb'] ?? 0;
              final dbPoolWaiting = system?['dbPoolWaiting'] ?? 0;

              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2.1,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Live CCU Card
                  _buildLiveCard(
                    title: 'Live Concurrent Users (CCU)',
                    value: formatter.format(liveCcu),
                    subtitle: 'Real-time WebSocket & lease active',
                    icon: Icons.speed_rounded,
                    accentColor: const Color(0xFF10B981),
                    badge: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'LIVE PULSE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF10B981),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // In-Call Channels Card
                  _buildLiveCard(
                    title: 'In-Call Agora Channels',
                    value: formatter.format(activeCalls),
                    subtitle: 'Active simultaneous audio/video calls',
                    icon: Icons.phone_in_talk_rounded,
                    accentColor: const Color(0xFF6366F1),
                    badge: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'UNLIMITED VIP',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6366F1),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  // Today's Subscriptions Revenue
                  _buildLiveCard(
                    title: "Today's Sub Revenue",
                    value: currencyFormatter.format(subRevToday),
                    subtitle: '$subsSoldToday memberships activated today',
                    icon: Icons.workspace_premium_rounded,
                    accentColor: const Color(0xFFF59E0B),
                    badge: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'CASH REVENUE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF59E0B),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  // Cluster Memory & DB Pool Health
                  _buildLiveCard(
                    title: 'Cluster Node Health',
                    value: '${memRss}MB RSS',
                    subtitle: dbPoolWaiting > 0
                        ? '⚠️ $dbPoolWaiting queries waiting pool'
                        : 'PostgreSQL pool healthy (0 waiting)',
                    icon: Icons.dns_rounded,
                    accentColor: const Color(0xFF8B5CF6),
                    badge: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'REDIS CLUSTER',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8B5CF6),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // ── Dual-Balance Circulating Ledger Overview ──────────────────────
          Container(
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
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AdminColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.account_balance_rounded, color: AdminColors.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Circulating Dual-Balance Ledger Audit',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AdminColors.textPrimary,
                                ),
                              ),
                              Text(
                                'Separate tracking of purchased spendable coins vs earned withdrawable Buddy meetup rewards',
                                style: TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AdminColors.activePillBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'AUDITED REAL-TIME',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AdminColors.activePillText),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      // Spendable Balance
                      Expanded(
                        child: _buildLedgerItem(
                          title: 'Circulating Spendable Coins',
                          value: '🪙 ${formatter.format(telemetry?['circulatingSpendable'] ?? 0)}',
                          note: 'Purchased coins & promotional bonuses (Non-withdrawable)',
                          badgeColor: const Color(0xFF3B82F6),
                        ),
                      ),
                      Container(width: 1, height: 60, color: AdminColors.border),
                      // Earned Balance
                      Expanded(
                        child: _buildLedgerItem(
                          title: 'Circulating Earned Coins',
                          value: '🪙 ${formatter.format(telemetry?['circulatingEarned'] ?? 0)}',
                          note: 'Buddy meetup rewards (50 coins per verified OTP meetup)',
                          badgeColor: const Color(0xFF10B981),
                        ),
                      ),
                      Container(width: 1, height: 60, color: AdminColors.border),
                      // Pending Payout Liability
                      Expanded(
                        child: _buildLedgerItem(
                          title: 'Pending Withdrawal Liability',
                          value: currencyFormatter.format(telemetry?['pendingWithdrawalsAmount'] ?? 0),
                          note: '${telemetry?['pendingWithdrawalsCount'] ?? 0} withdrawal requests awaiting approval',
                          badgeColor: const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

          // ── Stat Cards Grid ───────────────────────────────────────────────
          statsAsync.when(
            data: (stats) {
              num parseNum(dynamic val) {
                if (val == null) return 0;
                if (val is num) return val;
                if (val is String) return num.tryParse(val) ?? 0;
                return 0;
              }

              final totalUsers = parseNum(stats['totalUsers']);
              final maleUsers = parseNum(stats['maleUsers']);
              final femaleUsers = parseNum(stats['femaleUsers']);
              final pendingWithdrawals = parseNum(stats['pendingWithdrawals']);
              final reportsToday = parseNum(stats['reportsToday']);
              final reportsWeek = parseNum(stats['reportsThisWeek']);
              final coinsRecharged = parseNum(stats['totalCoinsRecharged']);
              final coinsPaid = parseNum(stats['totalPayoutsPaidOut'] ?? stats['totalRosesPaidOut']);

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
                    childAspectRatio: 2.2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      StatCard(
                        title: 'Total Users Base',
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
                        subtitle: 'Payout queue',
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
                        trendLabel: 'Revenue Units',
                        subtitle: 'Coin pack purchases',
                        icon: Icons.currency_rupee_rounded,
                        iconColor: const Color(0xFFF59E0B),
                        iconBgColor: const Color(0xFFFEF3C7),
                      ),
                      StatCard(
                        title: 'Coins Paid Out',
                        value: '🪙 ${formatter.format(coinsPaid)}',
                        trendLabel: 'Approved Payouts',
                        subtitle: 'Buddy meeting rewards redeemed',
                        icon: Icons.payments_rounded,
                        iconColor: const Color(0xFF10B981),
                        iconBgColor: const Color(0xFFD1FAE5),
                      ),
                    ],
                  );
                },
              );
            },
            loading: () => const SizedBox(
              height: 200,
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
          const SizedBox(height: 28),

          // ── App Version Management Section ────────────────────────────────
          const VersionManagementCard(),
        ],
      ),
    );
  }

  Widget _buildLiveCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Widget badge,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              badge,
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AdminColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AdminColors.textSecondary,
                ),
              ),
            ],
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AdminColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerItem({
    required String title,
    required String value,
    required String note,
    required Color badgeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AdminColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AdminColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: const TextStyle(fontSize: 11, color: AdminColors.textMuted),
          ),
        ],
      ),
    );
  }
}
