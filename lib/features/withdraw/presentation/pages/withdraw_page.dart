import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/features/withdraw/application/withdraw_providers.dart';
import 'package:buddypartner/features/withdraw/application/withdraw_controller.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';
import 'package:buddypartner/features/call/presentation/widgets/scratch_card_dialog.dart';

class WithdrawPage extends ConsumerStatefulWidget {
  const WithdrawPage({super.key});

  @override
  ConsumerState<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends ConsumerState<WithdrawPage> {
  final _amountController = TextEditingController();
  int _enteredCoins = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(instantConnectControllerProvider.notifier).fetchFemaleStatus();
      ref.read(instantConnectControllerProvider.notifier).fetchScratchCards();
    });
    _amountController.addListener(() {
      final text = _amountController.text.trim();
      final parsed = int.tryParse(text) ?? 0;
      if (parsed != _enteredCoins) {
        setState(() {
          _enteredCoins = parsed;
        });
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _setPresetAmount(int amount, int maxBalance) {
    HapticFeedback.selectionClick();
    final target = amount.clamp(0, maxBalance);
    _amountController.text = target > 0 ? target.toString() : '';
    _amountController.selection = TextSelection.fromPosition(
      TextPosition(offset: _amountController.text.length),
    );
  }

  void _submitWithdrawal(int maxCoins) {
    AppLogger.button('Submit Withdrawal Request', screen: 'WithdrawPage');
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      AppSnackBar.showError(context, 'Please enter a valid amount of coins to withdraw.');
      return;
    }

    if (amount > maxCoins) {
      AppSnackBar.showError(context, 'You cannot withdraw more than your available balance of $maxCoins coins.');
      return;
    }

    ref.read(withdrawControllerProvider.notifier).requestWithdrawal(amount).then((success) {
      if (success && mounted) {
        _amountController.clear();
        AppSnackBar.showSuccess(context, 'Withdrawal request submitted successfully!');
        ref.invalidate(walletBalanceProvider);
        ref.invalidate(withdrawalHistoryProvider);
      }
    });
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dt.month - 1];
    final day = dt.day.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = (dt.hour % 12 == 0 ? 12 : dt.hour % 12).toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$month $day, $year • $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final historyAsync = ref.watch(withdrawalHistoryProvider);
    final withdrawState = ref.watch(withdrawControllerProvider);
    final walletBalance = ref.watch(walletBalanceProvider).value ?? 0;
    final instantState = ref.watch(instantConnectControllerProvider);
    final unscratchedCards = instantState.scratchCards.where((c) => !c.isScratched).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E1B38), size: 20),
                onPressed: () => context.pop(),
              )
            : null,
        centerTitle: true,
        title: Text(
          'Earnings & Payouts',
          style: typography.titleCard.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: const Color(0xFF1E1B38),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Color(0xFF7C6AEF), size: 24),
            tooltip: 'Transaction History',
            onPressed: () => context.push(RouteNames.transactionHistory),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(left: 18.0, right: 18.0, top: 4.0, bottom: 100.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 1. VIP Dark Hero Earnings Card ──────────────────────────────
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF221E42),
                    Color(0xFF15132A),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF7C6AEF).withValues(alpha: 0.3),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C6AEF).withValues(alpha: 0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Decorative top-right gradient ambient glow
                  Positioned(
                    top: -40,
                    right: -40,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF8B7CF6).withValues(alpha: 0.25),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(22.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Header Row with Live Status
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7C6AEF).withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.account_balance_wallet_rounded,
                                    color: Color(0xFFB4A9FB),
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'AVAILABLE EARNINGS',
                                  style: TextStyle(
                                    color: Color(0xFFB4A9FB),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2DCE89).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF2DCE89).withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF2DCE89),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    '100% Guaranteed',
                                    style: TextStyle(
                                      color: Color(0xFF2DCE89),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Large Rupee Amount & Coin Equivalent
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '₹$walletBalance',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const Text(
                              '.00',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('🪙', style: TextStyle(fontSize: 12)),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$walletBalance Coins',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Guaranteed Conversion Rate Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.bolt_rounded, color: Color(0xFFFFD54F), size: 16),
                              SizedBox(width: 6),
                              Text(
                                '1 Coin = ₹1.00 INR (Direct UPI / Bank Payout)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),
                        Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
                        const SizedBox(height: 14),

                        // Metric Statistics Row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cards Scratched',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${instantState.femaleStatus.totalScratchedCards} Cards',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.12)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Scratch Earnings',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₹${instantState.femaleStatus.totalScratchedCoins}',
                                    style: const TextStyle(
                                      color: Color(0xFFFFD54F),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.12)),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Payout Speed',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Fast (24h)',
                                    style: TextStyle(
                                      color: Color(0xFF2DCE89),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ── 2. Unscratched Cards Action Card (Golden Glow) ──────────────
            if (unscratchedCards.isNotEmpty) ...[
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  ScratchCardDialog.show(context, unscratchedCards.first);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFD54F),
                        Color(0xFFFFA000),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFA000).withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5D4037).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.card_giftcard_rounded,
                          color: Color(0xFF5D4037),
                          size: 26,
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
                                  '${unscratchedCards.length} Scratch Card${unscratchedCards.length > 1 ? 's' : ''} Ready!',
                                  style: const TextStyle(
                                    color: Color(0xFF3E2723),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3E2723),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'TAP',
                                    style: TextStyle(
                                      color: Color(0xFFFFD54F),
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Reveal your rewards and credit coins into wallet!',
                              style: TextStyle(
                                color: Color(0xFF4E342E),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3E2723),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFFFFD54F),
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],

            // ── 3. Request Payout Section (Fintech Grade) ────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE8E6F0), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E1B38).withValues(alpha: 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7C6AEF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.payments_rounded,
                          color: Color(0xFF7C6AEF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Request Withdrawal',
                            style: TextStyle(
                              color: Color(0xFF1E1B38),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Direct transfer to UPI or Bank Account',
                            style: TextStyle(
                              color: Color(0xFF8A8A93),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Coin Input Box
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7FB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _enteredCoins > 0 ? const Color(0xFF7C6AEF) : const Color(0xFFE8E6F0),
                        width: _enteredCoins > 0 ? 1.5 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: Row(
                      children: [
                        const Text('🪙', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _amountController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                              color: Color(0xFF1E1B38),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Enter coins to withdraw',
                              hintStyle: TextStyle(
                                color: Color(0xFFA19EBB),
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (_enteredCoins > 0)
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF8A8A93)),
                            onPressed: () {
                              _amountController.clear();
                            },
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Preset Amount Selection Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildPresetChip('₹50', 50, walletBalance),
                        const SizedBox(width: 8),
                        _buildPresetChip('₹100', 100, walletBalance),
                        const SizedBox(width: 8),
                        _buildPresetChip('₹200', 200, walletBalance),
                        const SizedBox(width: 8),
                        _buildPresetChip('₹500', 500, walletBalance),
                        const SizedBox(width: 8),
                        _buildPresetChip('MAX (${walletBalance})', walletBalance, walletBalance, isMax: true),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Real-time Conversion Payout Preview Box
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F1FD),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF7C6AEF).withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.currency_rupee_rounded, color: Color(0xFF7C6AEF), size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Estimated Payout',
                              style: TextStyle(
                                color: Color(0xFF4A4468),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '₹$_enteredCoins.00',
                          style: const TextStyle(
                            color: Color(0xFF7C6AEF),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (withdrawState.errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              withdrawState.errorMessage!,
                              style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // Payout Action Button
                  GestureDetector(
                    onTap: withdrawState.isLoading || _enteredCoins <= 0
                        ? null
                        : () => _submitWithdrawal(walletBalance),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        gradient: _enteredCoins > 0 && !withdrawState.isLoading
                            ? const LinearGradient(
                                colors: [Color(0xFF7C6AEF), Color(0xFF8B7CF6)],
                              )
                            : LinearGradient(
                                colors: [
                                  const Color(0xFF7C6AEF).withValues(alpha: 0.4),
                                  const Color(0xFF8B7CF6).withValues(alpha: 0.4),
                                ],
                              ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _enteredCoins > 0 && !withdrawState.isLoading
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF7C6AEF).withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : [],
                      ),
                      child: Center(
                        child: withdrawState.isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    _enteredCoins > 0 ? 'Request Payout of ₹$_enteredCoins' : 'Enter Amount to Withdraw',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 4. Past Withdrawal Requests ──────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Withdrawal History',
                  style: TextStyle(
                    color: Color(0xFF1E1B38),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextButton(
                  onPressed: () => context.push(RouteNames.transactionHistory),
                  child: const Text(
                    'Full Statement ➜',
                    style: TextStyle(
                      color: Color(0xFF7C6AEF),
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            historyAsync.when(
              loading: () => const Center(child: AppLoadingIndicator()),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Failed to load history: $err',
                  style: typography.bodySmall.copyWith(color: Colors.red),
                ),
              ),
              data: (history) {
                if (history.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE8E6F0)),
                    ],
                    child: Column(
                      children: const [
                        Icon(Icons.receipt_long_rounded, color: Color(0xFFA19EBB), size: 36),
                        SizedBox(height: 10),
                        Text(
                          'No withdrawal requests yet',
                          style: TextStyle(
                            color: Color(0xFF1E1B38),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Complete calls & scratch cards to start earning payouts!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF8A8A93),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: history.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = history[index];
                    return _buildWithdrawalTile(context, item);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, int amount, int maxBalance, {bool isMax = false}) {
    final isSelected = _enteredCoins == amount && amount > 0;
    final isDisabled = amount > maxBalance && !isMax;

    return GestureDetector(
      onTap: isDisabled ? null : () => _setPresetAmount(amount, maxBalance),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF7C6AEF)
              : (isMax
                  ? const Color(0xFF7C6AEF).withValues(alpha: 0.1)
                  : const Color(0xFFF5F4FA)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF7C6AEF)
                : (isMax
                    ? const Color(0xFF7C6AEF).withValues(alpha: 0.4)
                    : const Color(0xFFE8E6F0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : (isMax
                    ? const Color(0xFF7C6AEF)
                    : (isDisabled ? const Color(0xFFB0AFC0) : const Color(0xFF1E1B38))),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildWithdrawalTile(BuildContext context, WithdrawalRequest item) {
    final dateStr = _formatDate(item.requestedAt);

    Color badgeColor;
    Color badgeBg;
    IconData statusIcon;
    String statusText = item.status.toUpperCase();

    switch (item.status.toLowerCase()) {
      case 'pending':
        badgeColor = const Color(0xFFF2A93B);
        badgeBg = const Color(0xFFF2A93B).withValues(alpha: 0.12);
        statusIcon = Icons.access_time_rounded;
        break;
      case 'approved':
      case 'paid':
        badgeColor = const Color(0xFF2DCE89);
        badgeBg = const Color(0xFF2DCE89).withValues(alpha: 0.12);
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'rejected':
        badgeColor = const Color(0xFFEF5350);
        badgeBg = const Color(0xFFEF5350).withValues(alpha: 0.12);
        statusIcon = Icons.cancel_rounded;
        break;
      default:
        badgeColor = const Color(0xFF8A8A93);
        badgeBg = const Color(0xFF8A8A93).withValues(alpha: 0.12);
        statusIcon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8E6F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: badgeBg,
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: badgeColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '₹${item.rupeeAmount}.00',
                      style: const TextStyle(
                        color: Color(0xFF1E1B38),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${item.coinAmount} Coins)',
                      style: const TextStyle(
                        color: Color(0xFF8A8A93),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  dateStr,
                  style: const TextStyle(
                    color: Color(0xFF8A8A93),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: badgeColor,
                fontWeight: FontWeight.w800,
                fontSize: 10.5,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
