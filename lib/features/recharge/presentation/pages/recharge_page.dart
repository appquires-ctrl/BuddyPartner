import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_balance_card.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';
import 'package:buddypartner/features/recharge/presentation/providers/recharge_providers.dart';
import 'package:buddypartner/features/recharge/presentation/widgets/recharge_plan_card.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';
import 'package:buddypartner/core/services/google_play_purchase_service.dart';

/// Professional, state-of-the-art Recharge Store screen
/// Based on Google Play In-App Billing & Option B (Base price + 18% GST) pricing model.
class RechargePage extends ConsumerStatefulWidget {
  final bool isEmbedded;

  const RechargePage({
    super.key,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _customController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _selectedPlanId = 'plan_99'; // Default selected ₹99 pack

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (!widget.isEmbedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(dualWalletProvider.notifier).fetchWallet();
      });
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  RechargePlanUiModel get _selectedPlan {
    final plans = ref.read(rechargePlansProvider);
    if (_selectedPlanId != null) {
      return plans.firstWhere(
        (p) => p.id == _selectedPlanId,
        orElse: () => plans[1], // default plan_99
      );
    }
    // If custom amount was typed, match nearest or default
    final customVal = int.tryParse(_customController.text.trim()) ?? 99;
    return plans.firstWhere(
      (p) => p.coins == customVal,
      orElse: () => plans.firstWhere((p) => p.id == 'plan_99', orElse: () => plans.first),
    );
  }

  int get _calculatedCoins {
    if (_selectedPlanId != null) {
      return _selectedPlan.totalCoins;
    }
    final customVal = int.tryParse(_customController.text.trim()) ?? 0;
    return customVal > 0 ? customVal : _selectedPlan.totalCoins;
  }

  int get _calculatedBasePrice {
    if (_selectedPlanId != null) {
      return _selectedPlan.basePriceRupees;
    }
    final customVal = int.tryParse(_customController.text.trim()) ?? 0;
    return customVal > 0 ? customVal : _selectedPlan.basePriceRupees;
  }

  Future<void> _handleRecharge(RechargePlanUiModel plan) async {
    HapticFeedback.mediumImpact();
    AppLogger.button(
      'Google Play In-App Purchase: ${plan.id} (${plan.totalCoins} Coins - ₹${plan.totalPriceRupees})',
      screen: 'RechargePage',
    );

    // Initiate native Google Play In-App Purchase flow
    await ref.read(googlePlayPurchaseProvider.notifier).buyProduct(plan.id, isConsumable: true);
  }

  void _showOrderSummaryBottomSheet(BuildContext context, RechargePlanUiModel plan) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => _CoinOrderSummarySheet(
        plan: plan,
        onPay: () => _handleRecharge(plan),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen<GooglePlayState>(googlePlayPurchaseProvider, (prev, next) {
      if (next.status == GooglePlayPurchaseStatus.success && next.successMessage != null) {
        AppSnackBar.showSuccess(context, next.successMessage!);
        ref.read(googlePlayPurchaseProvider.notifier).resetStatus();
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } else if (next.status == GooglePlayPurchaseStatus.error && next.errorMessage != null) {
        AppSnackBar.showError(context, next.errorMessage!);
        ref.read(googlePlayPurchaseProvider.notifier).resetStatus();
      }
    });

    final gpState = ref.watch(googlePlayPurchaseProvider);
    final isPurchasing = gpState.status == GooglePlayPurchaseStatus.purchasing ||
        gpState.status == GooglePlayPurchaseStatus.verifying;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dualWalletAsync = ref.watch(dualWalletProvider);
    final walletState = dualWalletAsync.value ?? const UserWalletState();
    final isBalanceLoading = dualWalletAsync.isLoading && dualWalletAsync.value == null;

    final balanceAsync = ref.watch(walletBalanceProvider);
    final totalBalance = walletState.balance > 0 ? walletState.balance : (balanceAsync.value ?? 0);
    final spendableBalance = walletState.spendableBalance;
    final earnedBalance = walletState.earnedBalance;

    final plans = ref.watch(rechargePlansProvider);
    final selectedPlan = _selectedPlan;

    return Scaffold(
      backgroundColor: widget.isEmbedded
          ? Colors.transparent
          : (isDark ? const Color(0xFF13101E) : const Color(0xFFF9F8FD)),
      appBar: widget.isEmbedded
          ? null
          : AppBar(
              title: const Text(
                'Coin Store',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
              ),
              centerTitle: true,
              elevation: 0,
              backgroundColor: Colors.transparent,
              actions: [
                IconButton(
                  icon: const Icon(Icons.history_rounded),
                  tooltip: 'Wallet History',
                  onPressed: () => context.push(RouteNames.walletHistory),
                ),
                const SizedBox(width: 4),
              ],
            ),
      body: SafeArea(
        top: !widget.isEmbedded,
        bottom: !widget.isEmbedded,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.isEmbedded) ...[
                      // ── 1. Unified Dual-Balance Hero Card ────────────────────────
                      AppCoinBalanceCard(
                        totalBalance: totalBalance,
                        spendableBalance: spendableBalance,
                        earnedBalance: earnedBalance,
                        isLoading: isBalanceLoading,
                        onAddCoinsPressed: () {
                          HapticFeedback.lightImpact();
                          if (_scrollController.hasClients) {
                            _scrollController.animateTo(
                              180,
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                        onEarnedPressed: () => context.push(RouteNames.withdraw),
                      ),
                      const SizedBox(height: 0),
                    ],

                    const SizedBox(height: 0),

                    // ── 2. Select Coin Pack Header ───────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Coin Pack',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose a value pack to get free bonus coins',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── 3. Coin Packs Grid ───────────────────────────────────────
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: plans.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 0.95,
                      ),
                      itemBuilder: (context, index) {
                        final plan = plans[index];
                        final isSelected = _selectedPlanId == plan.id;

                        return RechargePlanCard(
                          plan: plan,
                          isSelected: isSelected,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() {
                              _selectedPlanId = plan.id;
                              _customController.clear();
                            });
                            // _showOrderSummaryBottomSheet(context, plan);
                          },
                        );
                      },
                    ),

                    // const SizedBox(height: 24),

                    // ── 4. Custom Amount Section ─────────────────────────────────
                    // Container(
                      // padding: const EdgeInsets.all(16),
                      // decoration: BoxDecoration(
                      //   color: isDark ? const Color(0xFF1E1A2E) : Colors.white,
                      //   borderRadius: BorderRadius.circular(20),
                      //   border: Border.all(
                      //     color: _selectedPlanId == null && _customController.text.isNotEmpty
                      //         ? const Color(0xFF7C6AEF)
                      //         : (isDark ? Colors.white12 : const Color(0xFFECEBF3)),
                      //     width: _selectedPlanId == null && _customController.text.isNotEmpty ? 2 : 1,
                      //   ),
                      //   boxShadow: [
                      //     BoxShadow(
                      //       color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      //       blurRadius: 8,
                      //       offset: const Offset(0, 3),
                      //     ),
                      //   ],
                      // ),
                      // child: Column(
                      //   crossAxisAlignment: CrossAxisAlignment.start,
                      //   children: [
                          // Row(
                          //   children: [
                          //     const Text(
                          //       'Or Select by Amount',
                          //       style: TextStyle(
                          //         fontWeight: FontWeight.bold,
                          //         fontSize: 14,
                          //       ),
                          //     ),
                          //     const Spacer(),
                          //     Text(
                          //       'Min ₹10',
                          //       style: TextStyle(
                          //         fontSize: 11,
                          //         color: Colors.grey.shade500,
                          //         fontWeight: FontWeight.w600,
                          //       ),
                          //     ),
                          //   ],
                          // ),
                          // const SizedBox(height: 12),

                          // Text input field
                          // TextField(
                          //   controller: _customController,
                          //   keyboardType: TextInputType.number,
                          //   inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          //   style: const TextStyle(
                          //     fontSize: 16,
                          //     fontWeight: FontWeight.w800,
                          //   ),
                            // decoration: InputDecoration(
                            //   prefixIcon: const Padding(
                            //     padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            //     child: Text(
                            //       '₹',
                            //       style: TextStyle(
                            //         fontSize: 18,
                            //         fontWeight: FontWeight.w900,
                            //         color: Color(0xFF28233C),
                            //       ),
                            //     ),
                            //   ),
                            //   prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                            //   hintText: 'Enter amount (e.g. 99)',
                              // hintStyle: TextStyle(
                              //   fontSize: 14,
                              //   fontWeight: FontWeight.normal,
                            //     color: Colors.grey.shade400,
                            //   ),
                            //   filled: true,
                            //   fillColor: isDark ? const Color(0xFF28233C) : const Color(0xFFF7F6FC),
                            //   contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            //   border: OutlineInputBorder(
                            //     borderRadius: BorderRadius.circular(12),
                            //     borderSide: BorderSide.none,
                            //   ),
                            //   suffixText: 'Coins',
                            //   suffixStyle: const TextStyle(
                            //     fontWeight: FontWeight.bold,
                            //     color: Colors.grey,
                            //     fontSize: 13,
                            //   ),
                            // ),
                      //       onChanged: (val) {
                      //         final amount = int.tryParse(val.trim());
                      //         if (amount != null) {
                      //           final matchingPlan = plans.where((p) => p.coins == amount);
                      //           if (matchingPlan.isNotEmpty) {
                      //             setState(() => _selectedPlanId = matchingPlan.first.id);
                      //           } else {
                      //             setState(() => _selectedPlanId = null);
                      //           }
                      //         }
                      //       },
                      //     ),
                      //     const SizedBox(height: 10),
                      //   ],
                      // ),
                    // ),

                    const SizedBox(height: 0),

                    // ── 5. Trust & Security Banner ───────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E1A2E).withValues(alpha: 0.6)
                            : const Color(0xFFF8F8FA),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.shield_rounded,
                            color: Color(0xFF10B981),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Guaranteed Instant Coin Delivery',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  'Supports UPI, Cards & NetBanking • 100% Google Play Protected',
                                  style: TextStyle(
                                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ── 6. Bottom Checkout Action Bar (Anchored at Bottom of Screen) ──
            Container(
              margin: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 4,
                bottom: widget.isEmbedded
                    ? (6.0 + MediaQuery.of(context).padding.bottom)
                    : (16.0 + MediaQuery.of(context).padding.bottom),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1A2E) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? const Color(0xFF2C2746) : const Color(0xFFECEBF3),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '₹$_calculatedBasePrice',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'You get $_calculatedCoins Coins',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isPurchasing
                          ? null
                          : () => _showOrderSummaryBottomSheet(context, selectedPlan),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF18181B),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF27272A),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        shadowColor: Colors.black.withValues(alpha: 0.35),
                      ),
                      child: isPurchasing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              children: [
                                Icon(Icons.bolt_rounded, color: Color(0xFFFFD54F), size: 20),
                                SizedBox(width: 6),
                                Text(
                                  'Recharge Now',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoinOrderSummarySheet extends ConsumerWidget {
  final RechargePlanUiModel plan;
  final VoidCallback onPay;

  const _CoinOrderSummarySheet({
    required this.plan,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gpState = ref.watch(googlePlayPurchaseProvider);
    final isPurchasing = gpState.status == GooglePlayPurchaseStatus.purchasing ||
        gpState.status == GooglePlayPurchaseStatus.verifying;

    final totalDisplay = '₹${plan.totalPriceRupees}.00';

    final surfaceColor = isDark ? const Color(0xFF1E1A2E) : Colors.white;
    final mutedColor = isDark ? const Color(0xFF28233C) : const Color(0xFFF7F6FC);
    final textColor = isDark ? Colors.white : const Color(0xFF18181B);
    final textMuted = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sheet Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: Color(0xFFF59E0B),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Order Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Coin Pack Summary Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: mutedColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.25),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  const AppCoinIcon(size: 38, withGlow: true),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${plan.totalCoins} Coins',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: textColor,
                              ),
                            ),
                            if (plan.bonusCoins > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '+${plan.bonusCoins} Free',
                                  style: const TextStyle(
                                    color: Color(0xFF059669),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Instant 1:1 wallet crediting • Never expires',
                          style: TextStyle(
                            fontSize: 12,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // GST Breakdown Table
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: mutedColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  // Base Price
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Coin Pack Base Price',
                        style: TextStyle(
                          fontSize: 14,
                          color: textMuted,
                        ),
                      ),
                      Text(
                        '₹${plan.basePriceRupees}.00',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 18% GST
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Goods & Services Tax (18% GST)',
                        style: TextStyle(
                          fontSize: 14,
                          color: textMuted,
                        ),
                      ),
                      Text(
                        '+ ₹${plan.gstRupees}.00',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, thickness: 1),
                  ),

                  // Total Amount
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Payable',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Inclusive of all taxes',
                            style: TextStyle(
                              fontSize: 11,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        totalDisplay,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Regulatory Note
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '₹${plan.basePriceRupees} + 18% GST (₹${plan.gstRupees}) = ₹${plan.totalPriceRupees}. Billed securely through Google Play.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: textMuted,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Pay CTA Button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: isPurchasing ? null : onPay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF18181B),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF27272A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 3,
                ),
                child: isPurchasing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.lock_rounded,
                            size: 19,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Pay $totalDisplay with Google Play',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15.5,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 10),

            // Security reassurance
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 13,
                  color: textMuted,
                ),
                const SizedBox(width: 5),
                Text(
                  '100% Secure Payment • Instant Coin Delivery',
                  style: TextStyle(
                    fontSize: 11,
                    color: textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
