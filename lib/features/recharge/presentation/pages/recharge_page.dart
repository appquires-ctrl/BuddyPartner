import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_balance_card.dart';
import 'package:buddypartner/features/recharge/presentation/providers/recharge_providers.dart';
import 'package:buddypartner/features/recharge/presentation/widgets/recharge_plan_card.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';

/// Professional, state-of-the-art Recharge Store screen
/// Based on 1 Rupee = 1 Coin base pricing model.
class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});

  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  final TextEditingController _customController = TextEditingController();
  String? _selectedPlanId = 'plan_100'; // Default selected ₹100 pack
  bool _isProcessing = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  int get _calculatedCoins {
    final plans = ref.read(rechargePlansProvider);
    if (_selectedPlanId != null) {
      final selectedPlan = plans.firstWhere(
        (p) => p.id == _selectedPlanId,
        orElse: () => plans.first,
      );
      return selectedPlan.totalCoins;
    }
    final customVal = int.tryParse(_customController.text.trim()) ?? 0;
    return customVal;
  }

  int get _calculatedPrice {
    final plans = ref.read(rechargePlansProvider);
    if (_selectedPlanId != null) {
      final selectedPlan = plans.firstWhere(
        (p) => p.id == _selectedPlanId,
        orElse: () => plans.first,
      );
      return selectedPlan.price.toInt();
    }
    final customVal = int.tryParse(_customController.text.trim()) ?? 0;
    return customVal;
  }

  Future<void> _handleRecharge() async {
    final coinsToCredit = _calculatedCoins;
    final priceToPay = _calculatedPrice;

    if (coinsToCredit < 10 || priceToPay < 10) {
      AppSnackBar.showError(context, 'Minimum recharge amount is ₹10 (10 Coins).');
      return;
    }

    HapticFeedback.mediumImpact();
    AppLogger.button('Recharge $coinsToCredit Coins (₹$priceToPay)', screen: 'RechargePage');
    setState(() => _isProcessing = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.post(
        '/api/wallet/recharge',
        data: {
          'amount': coinsToCredit,
          'paymentReference': 'recharge_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      if (response.data != null && response.data['success'] == true) {
        ref.invalidate(walletBalanceProvider);
        if (mounted) {
          _showSuccessDialog(coinsToCredit, priceToPay);
        }
      } else {
        if (mounted) {
          AppSnackBar.showError(
            context,
            response.data?['error'] ?? 'Recharge failed. Please try again.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Recharge error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showSuccessDialog(int coins, int price) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Recharge Successful!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Successfully added $coins Coins to your wallet for ₹$price.',
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C6AEF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addQuickAmount(int amount) {
    HapticFeedback.selectionClick();
    final current = int.tryParse(_customController.text.trim()) ?? 0;
    final next = current + amount;
    _customController.text = next.toString();
    setState(() => _selectedPlanId = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final balanceAsync = ref.watch(walletBalanceProvider);
    final balance = balanceAsync.value ?? 0;
    final plans = ref.watch(rechargePlansProvider);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF13101E) : const Color(0xFFF9F8FD),
      appBar: AppBar(
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
            tooltip: 'Transaction History',
            onPressed: () => context.push(RouteNames.transactionHistory),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space20,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 1. Unified Live Wallet Balance Hero Card ────────────────
                    AppCoinBalanceCard(
                      balance: balance,
                      title: 'Available Balance',
                      subtitle: '1 Coin = ₹1 INR • Instant Delivery • 100% Secure',
                      onHistoryPressed: () => context.push(RouteNames.transactionHistory),
                    ),

                    const SizedBox(height: 24),

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
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // ── 4. Custom Amount Section ─────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1A2E) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _selectedPlanId == null && _customController.text.isNotEmpty
                              ? const Color(0xFF7C6AEF)
                              : (isDark ? Colors.white12 : const Color(0xFFECEBF3)),
                          width: _selectedPlanId == null && _customController.text.isNotEmpty ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // const Icon(
                              //   Icons.edit_note_rounded,
                              //   color: Color(0xFF7C6AEF),
                              //   size: 20,
                              // ),
                              // const SizedBox(width: 8),
                              const Text(
                                'Or Enter Custom Amount',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Min ₹10',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Text input field
                          TextField(
                            controller: _customController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                            decoration: InputDecoration(
                              prefixIcon: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Text(
                                  '₹',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF28233C),
                                  ),
                                ),
                              ),
                              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                              hintText: 'Enter amount (e.g. 150)',
                              hintStyle: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                color: Colors.grey.shade400,
                              ),
                              filled: true,
                              fillColor: isDark ? const Color(0xFF28233C) : const Color(0xFFF7F6FC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              suffixText: 'Coins',
                              suffixStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                            onChanged: (val) {
                              if (val.isNotEmpty) {
                                setState(() => _selectedPlanId = null);
                              }
                            },
                          ),
                          const SizedBox(height: 10),

                          
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

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
                                  'Supports UPI, Cards & NetBanking • 256-Bit SSL Encrypted',
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

                    const SizedBox(height: 100), // padding for bottom bar
                  ],
                ),
              ),
            ),

            // ── 6. Bottom Sticky Checkout Action Bar ──────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1A2E) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
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
                          '₹$_calculatedPrice',
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
                      onPressed: _isProcessing ? null : _handleRecharge,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF18181B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        shadowColor: Colors.black.withValues(alpha: 0.35),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
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

  Widget _buildQuickChip(int amount) {
    return ActionChip(
      label: Text('+₹$amount'),
      labelStyle: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        color: Color(0xFFB45309),
      ),
      backgroundColor: const Color(0xFFFEF3C7),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      onPressed: () => _addQuickAmount(amount),
    );
  }
}
