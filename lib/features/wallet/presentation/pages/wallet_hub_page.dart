import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_balance_card.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/recharge/presentation/pages/recharge_page.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';
import 'package:buddypartner/features/withdraw/presentation/pages/withdraw_page.dart';

enum WalletHubTab {
  recharge,
  withdraw,
}

/// Unified Wallet Hub screen providing both Male & Female users with
/// full financial autonomy: live dual-balance ledger, coin store, and payouts.
class WalletHubPage extends ConsumerStatefulWidget {
  final WalletHubTab? initialTab;

  const WalletHubPage({
    super.key,
    this.initialTab,
  });

  @override
  ConsumerState<WalletHubPage> createState() => _WalletHubPageState();
}

class _WalletHubPageState extends ConsumerState<WalletHubPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();

    final currentUser = ref.read(authStateProvider).value;
    final initialIndex = widget.initialTab == WalletHubTab.withdraw
        ? 1
        : (widget.initialTab == WalletHubTab.recharge
            ? 0
            : ((currentUser?.isFemale ?? false) ? 1 : 0));

    _currentTabIndex = initialIndex;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController.addListener(() {
      if (mounted && _tabController.index != _currentTabIndex) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dualWalletProvider.notifier).fetchWallet();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _switchToTab(int index) {
    if (_tabController.index != index) {
      HapticFeedback.selectionClick();
      _tabController.animateTo(index);
      setState(() {
        _currentTabIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final dualWalletAsync = ref.watch(dualWalletProvider);
    final walletState = dualWalletAsync.value ?? const UserWalletState();
    final isBalanceLoading = dualWalletAsync.isLoading && dualWalletAsync.value == null;

    final balanceAsync = ref.watch(walletBalanceProvider);
    final totalBalance = walletState.balance > 0 ? walletState.balance : (balanceAsync.value ?? 0);
    final spendableBalance = walletState.spendableBalance;
    final earnedBalance = walletState.earnedBalance;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF13101E) : const Color(0xFFF9F8FD),
      appBar: AppBar(
        title: const Text(
          'Wallet & Payouts',
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
        bottom: false,
        child: Column(
          children: [
            // ── 1. Hero Dual-Balance Card ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 0,
              ),
              child: AppCoinBalanceCard(
                totalBalance: totalBalance,
                spendableBalance: spendableBalance,
                earnedBalance: earnedBalance,
                isLoading: isBalanceLoading,
                activeTabIndex: _currentTabIndex,
                showAddCoinsButton: false,
                onAddCoinsPressed: () => _switchToTab(0),
                onTopUpPressed: () => _switchToTab(0),
                onEarnedPressed: () => _switchToTab(1),
              ),
            ),

            const SizedBox(height: 6),

            // ── 2. Segmented Pill Tab Selector ────────────────────────────
            Container(
              height: 44,
              margin: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1A2E) : const Color(0xFFEBE8F4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0xFF2C2746) : const Color(0xFFE0DCEB),
                  width: 1,
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C5DF9), Color(0xFF6347EA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6E4BF5).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: isDark ? Colors.white60 : const Color(0xFF5E5776),
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_bag_rounded, size: 15),
                        SizedBox(width: 7),
                        Text('Buy Coins'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance_wallet_rounded, size: 15),
                        SizedBox(width: 7),
                        Text('Withdraw'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // ── 3. TabBarView for Embedded Pages ──────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  RechargePage(isEmbedded: true),
                  WithdrawPage(isEmbedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
