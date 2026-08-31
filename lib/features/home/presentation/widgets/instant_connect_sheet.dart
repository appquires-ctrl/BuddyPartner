import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/app_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';

class InstantConnectSheet extends ConsumerStatefulWidget {
  const InstantConnectSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const InstantConnectSheet(),
    );
  }

  @override
  ConsumerState<InstantConnectSheet> createState() => _InstantConnectSheetState();
}

class _InstantConnectSheetState extends ConsumerState<InstantConnectSheet> {
  final TextEditingController _amountController = TextEditingController(text: '20');
  final FocusNode _focusNode = FocusNode();
  int _selectedPreset = 20;
  bool _isLoading = false;

  static const List<({int coins, String? badge})> _presets = [
    (coins: 10, badge: 'ECO'),
    (coins: 20, badge: 'POPULAR'),
    (coins: 50, badge: 'FAST'),
    (coins: 100, badge: 'TOP'),
    (coins: 200, badge: 'VIP'),
  ];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletBalanceProvider.notifier).fetchBalance();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _amountController.dispose();
    super.dispose();
  }

  int get _currentAmount => int.tryParse(_amountController.text.trim()) ?? 0;

  void _onPresetTapped(int val) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedPreset = val;
      _amountController.text = val.toString();
    });
    _focusNode.unfocus();
  }

  void _adjustAmount(int delta) {
    HapticFeedback.lightImpact();
    final current = _currentAmount == 0 ? _selectedPreset : _currentAmount;
    final newAmount = (current + delta).clamp(10, 10000);
    setState(() {
      _selectedPreset = newAmount;
      _amountController.text = newAmount.toString();
    });
  }

  ({String title, String waitTime, double progress, Color color, IconData icon}) _getPriorityInfo(int amount) {
    if (amount < 10) {
      return (
        title: 'Minimum 10 Coins Required',
        waitTime: 'Select coins ≥ 10',
        progress: 0.0,
        color: const Color(0xFFE11D48),
        icon: Icons.info_outline_rounded,
      );
    } else if (amount >= 100) {
      return (
        title: 'Instant Top Match',
        waitTime: 'Est. wait: < 3s',
        progress: 1.0,
        color: const Color(0xFFFF9100),
        icon: Icons.rocket_launch_rounded,
      );
    } else if (amount >= 50) {
      return (
        title: 'Turbo VIP Priority',
        waitTime: 'Est. wait: < 8s',
        progress: 0.8,
        color: const Color(0xFF8B5CF6),
        icon: Icons.bolt_rounded,
      );
    } else if (amount >= 20) {
      return (
        title: 'High Queue Priority',
        waitTime: 'Est. wait: < 15s',
        progress: 0.55,
        color: const Color(0xFF6366F1),
        icon: Icons.flash_on_rounded,
      );
    } else {
      return (
        title: 'Standard VIP Priority',
        waitTime: 'Est. wait: ~20-30s',
        progress: 0.3,
        color: const Color(0xFF0EA5E9),
        icon: Icons.timer_outlined,
      );
    }
  }

  Future<void> _handleStartConnect() async {
    HapticFeedback.mediumImpact();
    final subAsync = ref.read(subscriptionStatusProvider);
    final isSubscribed = subAsync.value?.isSubscribed ?? false;

    if (!isSubscribed) {
      Navigator.pop(context);
      context.push(RouteNames.subscribe);
      return;
    }

    final amount = _currentAmount;
    if (amount < 10) {
      _focusNode.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF1E1E24),
          content: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFFFFB74D), size: 20),
              SizedBox(width: 10),
              Text('Minimum coin amount is 10 coins.', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
      return;
    }

    int currentBalance = ref.read(walletBalanceProvider).value ?? 0;
    if (currentBalance == 0) {
      currentBalance = await ref.read(walletBalanceProvider.notifier).fetchBalance();
      if (!mounted) return;
    }

    if (currentBalance < amount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF1E1E24),
          content: Text(
            'Insufficient balance ($currentBalance coins). Need ${amount - currentBalance} more.',
            style: const TextStyle(color: Colors.white),
          ),
          action: SnackBarAction(
            label: 'Recharge',
            textColor: const Color(0xFFFFB74D),
            onPressed: () {
              final navContext = rootNavigatorKey.currentContext;
              if (navContext != null && navContext.mounted) {
                navContext.push(RouteNames.recharge);
              }
            },
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final success = await ref.read(instantConnectControllerProvider.notifier).joinQueue(amount);
      if (mounted) {
        if (success) {
          Navigator.pop(context);
        } else {
          final error = ref.read(instantConnectControllerProvider).errorMessage ??
              'Unable to join instant queue. Please try again.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: const Color(0xFF1E1E24),
              content: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: const Color(0xFF1E1E24),
            content: Text(
              'Error: $e',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<InstantConnectState>(instantConnectControllerProvider, (prev, next) {
      if (next.phase == InstantPhase.inCall && mounted) {
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    });

    final typography = context.typography;
    final walletAsync = ref.watch(walletBalanceProvider);
    final walletBalance = walletAsync.valueOrNull ?? 0;
    final isSubscribed = ref.watch(subscriptionStatusProvider).value?.isSubscribed ?? false;
    final amount = _currentAmount;
    final isBelowMin = _amountController.text.trim().isNotEmpty && amount < 10;

    // Only flag as insufficient when wallet balance has actually loaded and amount >= 10
    final isInsufficient = isSubscribed && walletAsync.hasValue && !isBelowMin && walletBalance < amount;
    final priority = _getPriorityInfo(amount);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 36,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            top: 12,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Drag Handle Bar ─────────────────────────────────────
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4E4E7),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // ── Header Row ───────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Glowing VIP Icon
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9F1C), Color(0xFFFF5E36)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF7A29).withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Title & Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'VIP Instant Connect',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF18181B),
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Skip the line & match instantly',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF71717A),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Wallet Balance Pill
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final navContext = rootNavigatorKey.currentContext;
                        if (navContext != null && navContext.mounted) {
                          navContext.push(RouteNames.recharge);
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F1FE),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE0DAFB)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppCoinIcon(size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '$walletBalance',
                              style: const TextStyle(
                                color: Color(0xFF5B45E0),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // ── Subscription Notice (if not subscribed) ─────────────
              if (!isSubscribed)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.lock_person_rounded,
                          color: Color(0xFFD97706),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'VIP Membership Required',
                              style: TextStyle(
                                color: Color(0xFF92400E),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Subscribe to unlock high-priority matching',
                              style: TextStyle(
                                color: Color(0xFFB45309),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          context.push(RouteNames.subscribe);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          backgroundColor: const Color(0xFFD97706),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text(
                          'Unlock',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Preset Coins Section ─────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SELECT COIN AMOUNT',
                    style: typography.bodySmall.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: const Color(0xFF71717A),
                    ),
                  ),
                  Row(
                    children: const [
                      Icon(Icons.speed_rounded, size: 13, color: Color(0xFF7C6AEF)),
                      SizedBox(width: 4),
                      Text(
                        'Higher = Faster match',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7C6AEF),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Preset Cards Row
              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: _presets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final item = _presets[index];
                    final isSelected = _selectedPreset == item.coins;

                    return GestureDetector(
                      onTap: () => _onPresetTapped(item.coins),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: 82,
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [Color(0xFF7C6AEF), Color(0xFF907CFF)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isSelected ? null : const Color(0xFFF8F8FA),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF6551E8)
                                : const Color(0xFFE4E4E7),
                            width: isSelected ? 1.8 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF7C6AEF).withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Badge Container with fixed height to prevent overflow
                            SizedBox(
                              height: 16,
                              child: item.badge != null
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Colors.white.withValues(alpha: 0.25)
                                            : const Color(0xFFEDE9FE),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        item.badge!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3,
                                          color: isSelected
                                              ? Colors.white
                                              : const Color(0xFF6D28D9),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 2),

                            // Coins Display
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AppCoinIcon(size: 15, withGlow: isSelected),
                                const SizedBox(width: 3),
                                Text(
                                  '${item.coins}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected ? Colors.white : const Color(0xFF18181B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Coins',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w800,
                                color: isSelected
                                    ? const Color.fromARGB(255, 255, 255, 255).withValues(alpha: 0.85)
                                    : const Color.fromARGB(255, 99, 99, 99),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ── Custom Amount Stepper Input ─────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8FA),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isBelowMin
                            ? const Color(0xFFE11D48)
                            : (_focusNode.hasFocus
                                ? const Color(0xFF7C6AEF)
                                : const Color(0xFFE4E4E7)),
                        width: (isBelowMin || _focusNode.hasFocus) ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Coin Icon Badge
                        const AppCoinIcon(size: 22),
                        const SizedBox(width: 12),

                        // Custom Input Field
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isBelowMin ? 'Minimum 10 Coins Required' : 'Custom Amount (Min 10)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isBelowMin ? const Color(0xFFE11D48) : const Color(0xFF71717A),
                                ),
                              ),
                              TextField(
                                controller: _amountController,
                                focusNode: _focusNode,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: isBelowMin ? const Color(0xFFE11D48) : const Color(0xFF18181B),
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 2),
                                  hintText: '20',
                                  border: InputBorder.none,
                                ),
                                onChanged: (val) {
                                  final parsed = int.tryParse(val) ?? 0;
                                  setState(() {
                                    _selectedPreset = parsed;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                        // Stepper Buttons (-10, +10)
                        Row(
                          children: [
                            _buildStepperBtn(
                              icon: Icons.remove_rounded,
                              onTap: amount > 10 ? () => _adjustAmount(-10) : null,
                            ),
                            const SizedBox(width: 6),
                            _buildStepperBtn(
                              icon: Icons.add_rounded,
                              onTap: () => _adjustAmount(10),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Inline Validation Warning Message
                  if (isBelowMin)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 6),
                      child: Row(
                        children: const [
                          Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFE11D48)),
                          SizedBox(width: 4),
                          Text(
                            'Please enter at least 10 coins to proceed.',
                            style: TextStyle(
                              color: Color(0xFFE11D48),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Priority Visualizer Card ────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      priority.color.withValues(alpha: 0.08),
                      const Color(0xFFF9FAFB),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: priority.color.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(priority.icon, color: priority.color, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          priority.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: priority.color,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: priority.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            priority.waitTime,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: priority.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Priority Meter Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        children: [
                          Container(
                            height: 6,
                            width: double.infinity,
                            color: const Color(0xFFE4E4E7),
                          ),
                          FractionallySizedBox(
                            widthFactor: priority.progress.clamp(0.05, 1.0),
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    priority.color.withValues(alpha: 0.7),
                                    priority.color,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: const [
                        Icon(Icons.shield_outlined, size: 12, color: Color(0xFF71717A)),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '100% coins refunded automatically if not matched within 60s.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF71717A),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── Insufficient Balance Banner (if applicable) ─────────
              if (isInsufficient) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You need ${amount - walletBalance} more coins to connect.',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          final navContext = rootNavigatorKey.currentContext;
                          if (navContext != null && navContext.mounted) {
                            navContext.push(RouteNames.recharge);
                          }
                        },
                        child: const Text(
                          'Recharge',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFDC2626),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Primary Action Button ───────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: isBelowMin
                          ? [const Color(0xFFE11D48), const Color(0xFFBE123C)]
                          : (isSubscribed
                              ? (isInsufficient
                                  ? [const Color(0xFFF59E0B), const Color(0xFFD97706)]
                                  : [const Color(0xFF7C6AEF), const Color(0xFF6B4EFF)])
                              : [const Color(0xFFFF9F1C), const Color(0xFFFF5E36)]),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isBelowMin
                                ? const Color(0xFFE11D48)
                                : (isSubscribed
                                    ? (isInsufficient
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFF7C6AEF))
                                    : const Color(0xFFFF9F1C)))
                            .withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : (isInsufficient
                            ? () {
                                final navContext = rootNavigatorKey.currentContext;
                                if (navContext != null && navContext.mounted) {
                                  navContext.push(RouteNames.recharge);
                                }
                              }
                            : _handleStartConnect),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isBelowMin
                                    ? Icons.info_outline_rounded
                                    : (isSubscribed
                                        ? (isInsufficient ? Icons.add_card_rounded : Icons.bolt_rounded)
                                        : Icons.workspace_premium_rounded),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isBelowMin
                                    ? 'Minimum 10 Coins Required'
                                    : (!isSubscribed
                                        ? 'Unlock VIP to Connect'
                                        : (isInsufficient
                                            ? 'Recharge & Connect ($amount Coins)'
                                            : 'Start Instant Connect • $amount Coins')),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                  letterSpacing: 0.2,
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
      ),
    );
  }

  Widget _buildStepperBtn({required IconData icon, VoidCallback? onTap}) {
    final isEnabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isEnabled ? Colors.white : const Color(0xFFE4E4E7).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isEnabled ? const Color(0xFFD4D4D8) : const Color(0xFFE4E4E7),
            ),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Icon(
            icon,
            size: 18,
            color: isEnabled ? const Color(0xFF18181B) : const Color(0xFFA1A1AA),
          ),
        ),
      ),
    );
  }
}
