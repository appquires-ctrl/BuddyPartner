import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../theme/admin_colors.dart';
import '../../theme/admin_theme.dart';
import '../../providers/admin_providers.dart';

class WithdrawalsScreen extends ConsumerWidget {
  const WithdrawalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final withdrawalsState = ref.watch(withdrawalsProvider);
    final withdrawalsNotifier = ref.read(withdrawalsProvider.notifier);
    final currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Withdrawal Requests',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AdminColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Review and process creator earned coin payout requests',
                    style: TextStyle(
                      fontSize: 13,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => withdrawalsNotifier.fetchWithdrawals(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Refresh'),
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
          const SizedBox(height: 20),

          // Status Filter Tabs
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminColors.border),
            ),
            child: Row(
              children: [
                _buildFilterTab(context, ref, title: 'All Requests', status: 'all', current: withdrawalsState.status),
                const SizedBox(width: 8),
                _buildFilterTab(context, ref, title: 'Pending Only', status: 'pending', current: withdrawalsState.status),
                const SizedBox(width: 8),
                _buildFilterTab(context, ref, title: 'Approved', status: 'approved', current: withdrawalsState.status),
                const SizedBox(width: 8),
                _buildFilterTab(context, ref, title: 'Paid Out', status: 'paid', current: withdrawalsState.status),
                const SizedBox(width: 8),
                _buildFilterTab(context, ref, title: 'Rejected', status: 'rejected', current: withdrawalsState.status),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Table Container
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AdminColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminColors.border),
            ),
            child: withdrawalsState.isLoading
                ? const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator(color: AdminColors.primary)),
                  )
                : withdrawalsState.withdrawals.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(48),
                        alignment: Alignment.center,
                        child: Column(
                          children: const [
                            Icon(Icons.payments_outlined, size: 48, color: AdminColors.textMuted),
                            SizedBox(height: 12),
                            Text(
                              'No withdrawal requests found',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AdminColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth > 950 ? constraints.maxWidth : 950.0;
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: width,
                                  child: Table(
                                    columnWidths: const {
                                      0: FlexColumnWidth(3.0), // USER
                                      1: FlexColumnWidth(2.0), // ROSES
                                      2: FlexColumnWidth(2.2), // RUPEE AMOUNT
                                      3: FlexColumnWidth(3.0), // REQUESTED DATE
                                      4: FlexColumnWidth(2.0), // STATUS
                                      5: FlexColumnWidth(2.0), // ACTION
                                    },
                                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                                    children: [
                                      // Table Header
                                      TableRow(
                                        decoration: const BoxDecoration(
                                          color: AdminColors.surfaceMuted,
                                        ),
                                        children: [
                                          _buildHeaderCell('USER'),
                                          _buildHeaderCell('EARNED COINS'),
                                          _buildHeaderCell('RUPEE AMOUNT'),
                                          _buildHeaderCell('REQUESTED DATE'),
                                          _buildHeaderCell('STATUS'),
                                          _buildHeaderCell('ACTION'),
                                        ],
                                      ),

                                      // Data Rows
                                      ...withdrawalsState.withdrawals.map((item) {
                                        final id = item['id'];
                                        final userName = item['user_name'] ?? 'Unknown Creator';
                                        final userPhone = item['user_phone'] ?? '';
                                        final coinAmount = item['rose_amount'] ?? item['coin_amount'] ?? 0;
                                        final rupeeAmount = item['rupee_amount'] ?? 0;
                                        final status = (item['status'] ?? 'pending').toString().toLowerCase();
                                        final dateStr = item['requested_at'] != null
                                            ? DateFormat('MMM dd, yyyy • hh:mm a').format(DateTime.parse(item['requested_at']))
                                            : 'N/A';

                                        return TableRow(
                                          decoration: const BoxDecoration(
                                            border: Border(bottom: BorderSide(color: AdminColors.border, width: 1)),
                                          ),
                                          children: [
                                            // USER
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                                  Text(userPhone, style: AdminTheme.tabularNumeralStyle.copyWith(fontSize: 11, color: AdminColors.textSecondary)),
                                                ],
                                              ),
                                            ),

                                            // COINS
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Text('🪙 $coinAmount earned', style: AdminTheme.tabularNumeralStyle.copyWith(color: const Color(0xFFD97706), fontWeight: FontWeight.bold)),
                                            ),

                                            // RUPEE AMOUNT
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Text(currencyFormat.format(rupeeAmount), style: AdminTheme.tabularNumeralStyle.copyWith(color: AdminColors.success)),
                                            ),

                                            // REQUESTED DATE
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Text(dateStr, style: const TextStyle(fontSize: 13)),
                                            ),

                                            // STATUS
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: _buildStatusBadge(status),
                                              ),
                                            ),

                                            // ACTION
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              child: DropdownButtonHideUnderline(
                                                child: DropdownButton<String>(
                                                  value: status,
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                  items: const [
                                                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                                                    DropdownMenuItem(value: 'approved', child: Text('Approve')),
                                                    DropdownMenuItem(value: 'paid', child: Text('Mark Paid')),
                                                    DropdownMenuItem(value: 'rejected', child: Text('Reject')),
                                                  ],
                                                  onChanged: (newStatus) async {
                                                    if (newStatus != null && newStatus != status) {
                                                      final success = await withdrawalsNotifier.updateStatus(id, newStatus);
                                                      if (context.mounted && success) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(
                                                            content: Text('Withdrawal status updated to $newStatus'),
                                                            backgroundColor: AdminColors.primary,
                                                          ),
                                                        );
                                                      }
                                                    }
                                                  },
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          // Pagination Controls
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Page ${withdrawalsState.page} of ${withdrawalsState.totalPages}',
                                  style: const TextStyle(fontSize: 13, color: AdminColors.textSecondary),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.chevron_left_rounded),
                                      onPressed: withdrawalsState.page > 1
                                          ? () => withdrawalsNotifier.setPage(withdrawalsState.page - 1)
                                          : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.chevron_right_rounded),
                                      onPressed: withdrawalsState.page < withdrawalsState.totalPages
                                          ? () => withdrawalsNotifier.setPage(withdrawalsState.page + 1)
                                          : null,
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

  Widget _buildHeaderCell(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AdminColors.textSecondary),
      ),
    );
  }

  Widget _buildFilterTab(BuildContext context, WidgetRef ref, {required String title, required String status, required String current}) {
    final isSelected = current == status;
    return InkWell(
      onTap: () => ref.read(withdrawalsProvider.notifier).setStatus(status),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AdminColors.activePillBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AdminColors.primary : AdminColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;

    switch (status) {
      case 'approved':
        bg = AdminColors.infoBg;
        fg = AdminColors.info;
        break;
      case 'paid':
        bg = AdminColors.successBg;
        fg = AdminColors.success;
        break;
      case 'rejected':
        bg = AdminColors.dangerBg;
        fg = AdminColors.danger;
        break;
      case 'pending':
      default:
        bg = AdminColors.warningBg;
        fg = AdminColors.warning;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}
