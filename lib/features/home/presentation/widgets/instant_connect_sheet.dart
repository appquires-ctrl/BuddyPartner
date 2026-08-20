import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/app_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
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
  int _selectedPreset = 20;
  bool _isLoading = false;

  final List<int> _presets = [10, 20, 50, 100, 200];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletBalanceProvider.notifier).fetchBalance();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _onPresetTapped(int val) {
    setState(() {
      _selectedPreset = val;
      _amountController.text = val.toString();
    });
  }

  Future<void> _handleStartConnect() async {
    final subAsync = ref.read(subscriptionStatusProvider);
    final isSubscribed = subAsync.value?.isSubscribed ?? false;

    if (!isSubscribed) {
      Navigator.pop(context);
      context.push(RouteNames.subscribe);
      return;
    }

    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    if (amount < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum bid amount is 10 coins.')),
      );
      return;
    }

    int currentBalance = ref.read(walletBalanceProvider).value ?? 0;
    if (currentBalance == 0) {
      currentBalance = await ref.read(walletBalanceProvider.notifier).fetchBalance();
    }

    if (currentBalance < amount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Insufficient balance ($currentBalance coins). Please recharge.'),
          action: SnackBarAction(
            label: 'Recharge',
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
    final success = await ref.read(instantConnectControllerProvider.notifier).joinQueue(amount);
    setState(() => _isLoading = false);

    if (mounted && success) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final walletBalance = ref.watch(walletBalanceProvider).value ?? 0;
    final isSubscribed = ref.watch(subscriptionStatusProvider).value?.isSubscribed ?? false;

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'VIP Instant Connect',
                          style: typography.titleCard.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFFFB300)),
                          ),
                          child: const Text(
                            'VIP',
                            style: TextStyle(
                              color: Color(0xFFE65100),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Skip the line & get matched instantly',
                      style: typography.bodySmall.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
              // Wallet balance chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3EFFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.monetization_on, color: Color(0xFF7C6AEF), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '$walletBalance',
                      style: const TextStyle(
                        color: Color(0xFF7C6AEF),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Subscription check warning if not subscribed
          if (!isSubscribed)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFB74D)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: Color(0xFFF57C00)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Active subscription required to use VIP Instant Connect.',
                      style: typography.bodySmall.copyWith(
                        color: const Color(0xFFE65100),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Bid Amount Header
          Text(
            'SELECT COIN BID',
            style: typography.bodySmall.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),

          // Preset Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _presets.map((val) {
                final isSelected = _selectedPreset == val;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    label: Text('🪙 $val'),
                    selected: isSelected,
                    selectedColor: colors.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : colors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    backgroundColor: colors.surfaceMuted,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (_) => _onPresetTapped(val),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Custom Input Field
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Custom Coins Amount (Min 10)',
              prefixIcon: const Icon(Icons.toll_rounded, color: Color(0xFF7C6AEF)),
              suffixText: 'Coins',
              filled: true,
              fillColor: colors.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.primary, width: 1.5),
              ),
            ),
            onChanged: (val) {
              final parsed = int.tryParse(val) ?? 0;
              setState(() {
                _selectedPreset = parsed;
              });
            },
          ),
          const SizedBox(height: 14),

          // Explanation Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F8FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E0FA)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFF7C6AEF), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '⚡ Higher bid prioritizes your call at the top of the queue with an online buddy for a guaranteed conversation.',
                    style: typography.bodySmall.copyWith(
                      fontSize: 11.5,
                      color: const Color(0xFF554488),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Connect Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleStartConnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: isSubscribed ? const Color(0xFF7C6AEF) : const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 3,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(
                      isSubscribed ? 'Start Instant Connect ⚡' : 'Subscribe to Unlock VIP',
                      style: typography.bodyMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
}
