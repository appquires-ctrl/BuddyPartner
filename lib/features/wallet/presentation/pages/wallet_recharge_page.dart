import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';

class CoinPack {
  final int id;
  final int coins;
  final int bonusCoins;
  final int priceRupees;
  final String? badge;

  const CoinPack({
    required this.id,
    required this.coins,
    required this.bonusCoins,
    required this.priceRupees,
    this.badge,
  });

  int get totalCoins => coins + bonusCoins;
}

class WalletRechargePage extends ConsumerStatefulWidget {
  const WalletRechargePage({super.key});

  @override
  ConsumerState<WalletRechargePage> createState() => _WalletRechargePageState();
}

class _WalletRechargePageState extends ConsumerState<WalletRechargePage> {
  final TextEditingController _customController = TextEditingController();
  int? _selectedPackId = 2; // Default ₹100 pack
  bool _isRecharging = false;

  final List<CoinPack> _packs = const [
    CoinPack(id: 0, coins: 20, bonusCoins: 0, priceRupees: 20),
    CoinPack(id: 1, coins: 50, bonusCoins: 0, priceRupees: 50),
    CoinPack(id: 2, coins: 100, bonusCoins: 10, priceRupees: 100, badge: 'POPULAR'),
    CoinPack(id: 3, coins: 200, bonusCoins: 30, priceRupees: 200, badge: 'BEST VALUE'),
    CoinPack(id: 4, coins: 500, bonusCoins: 100, priceRupees: 500, badge: 'VIP SAVER'),
  ];

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  int get _calculatedCoins {
    if (_selectedPackId != null) {
      final pack = _packs.firstWhere((p) => p.id == _selectedPackId);
      return pack.totalCoins;
    }
    final customVal = int.tryParse(_customController.text.trim()) ?? 0;
    return customVal;
  }

  int get _calculatedPrice {
    if (_selectedPackId != null) {
      final pack = _packs.firstWhere((p) => p.id == _selectedPackId);
      return pack.priceRupees;
    }
    final customVal = int.tryParse(_customController.text.trim()) ?? 0;
    return customVal;
  }

  Future<void> _handleRecharge() async {
    final amount = _calculatedCoins;
    if (amount < 10) {
      AppSnackBar.showError(context, 'Minimum recharge amount is 10 coins (₹10).');
      return;
    }

    setState(() => _isRecharging = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        '/api/wallet/recharge',
        data: {
          'amount': amount,
          'paymentReference': 'app_recharge_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      if (response.data != null && response.data['success'] == true) {
        ref.invalidate(walletBalanceProvider);
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: const [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
                  SizedBox(width: 10),
                  Text('Recharge Successful!'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🎉 Successfully added $amount Coins to your in-app wallet.',
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bolt_rounded, color: Color(0xFF7C6AEF), size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'You can now use Instant Connect for fast 1:1 priority matching!',
                            style: TextStyle(fontSize: 12, color: Color(0xFF554488), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C6AEF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Awesome'),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          AppSnackBar.showError(context, response.data?['error'] ?? 'Recharge failed. Please try again.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Recharge error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isRecharging = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final walletBalance = ref.watch(walletBalanceProvider).value ?? 0;
    final authUser = ref.watch(authStateProvider).value;
    final instantState = ref.watch(instantConnectControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Wallet & Recharge',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Transaction History',
            onPressed: () => context.push(RouteNames.transactionHistory),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Live Wallet Balance Card ─────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6B4EFF), Color(0xFF9F7AFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6B4EFF).withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
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
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Available Balance',
                            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => context.push(RouteNames.transactionHistory),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: const [
                              Text('History', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 10),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$walletBalance',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Coins',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '≈ ₹$walletBalance',
                        style: const TextStyle(
                          color: Color(0xFFFFD54F),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: const [
                      Icon(Icons.check_circle_outline_rounded, color: Color(0xFFB7F4D8), size: 16),
                      SizedBox(width: 6),
                      Text(
                        '1 Coin = ₹1 INR • Instant Delivery • 100% Secure',
                        style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Female Scratch Cards Summary (if female)
            if (authUser?.isFemale == true && instantState.femaleStatus.totalScratchedCoins > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFFD54F)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.card_giftcard_rounded, color: Color(0xFFD97706), size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Paid Calls Earnings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(
                            'Earned ${instantState.femaleStatus.totalScratchedCoins} Coins from ${instantState.femaleStatus.totalScratchedCards} Scratch Cards',
                            style: const TextStyle(color: Colors.black54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── 2. Coin Packs Section ───────────────────────────────────────
            const Text(
              'Select Coin Pack',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E1B4B)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Choose a popular pack to get bonus coins',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Grid of Coin Packs
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _packs.length,
              separatorBuilder: (ctx, i) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final pack = _packs[i];
                final isSelected = _selectedPackId == pack.id;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedPackId = pack.id;
                      _customController.clear();
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFF3E8FF) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF7C6AEF) : Colors.grey.shade200,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isSelected
                              ? const Color(0xFF7C6AEF).withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF7C6AEF) : const Color(0xFFF1F0FB),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.monetization_on_rounded,
                            color: isSelected ? Colors.white : const Color(0xFF7C6AEF),
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
                                    '${pack.coins} Coins',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  if (pack.bonusCoins > 0) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '+${pack.bonusCoins} Bonus',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Get ${pack.totalCoins} Coins in total',
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        if (pack.badge != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              pack.badge!,
                              style: const TextStyle(
                                color: Color(0xFFB45309),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Text(
                          '₹${pack.priceRupees}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: isSelected ? const Color(0xFF7C6AEF) : const Color(0xFF1E1B4B),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 18),

            // ── 3. Custom Amount Input ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _selectedPackId == null && _customController.text.isNotEmpty
                      ? const Color(0xFF7C6AEF)
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note_rounded, color: Color(0xFF7C6AEF)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _customController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        hintText: 'Or enter custom coins (Min 10)',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) {
                        if (val.isNotEmpty) {
                          setState(() => _selectedPackId = null);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 4. Recharge Button ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isRecharging ? null : _handleRecharge,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C6AEF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 4,
                  shadowColor: const Color(0xFF7C6AEF).withValues(alpha: 0.4),
                ),
                child: _isRecharging
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        'Recharge ₹$_calculatedPrice  (${_calculatedCoins} Coins)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }
}
