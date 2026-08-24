import 'package:flutter/material.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';

/// AppCoinBalanceCard provides a modern, unified Hero Wallet Balance card
/// used consistently across Home, Recharge, Withdraw, and Profile pages.
class AppCoinBalanceCard extends StatelessWidget {
  final int balance;
  final String title;
  final String? subtitle;
  final VoidCallback? onTopUpPressed;
  final VoidCallback? onHistoryPressed;
  final List<Color>? gradientColors;

  const AppCoinBalanceCard({
    super.key,
    required this.balance,
    this.title = 'Available Balance',
    this.subtitle = '1 Coin = ₹1 INR • Instant Delivery • 100% Secure',
    this.onTopUpPressed,
    this.onHistoryPressed,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors ??
        const [
          Color(0xFF141417),
          Color(0xFF24242A),
        ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            bottom: -30,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFD54F).withValues(alpha: 0.05),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top Header Row: Icon + Title + Action Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  if (onHistoryPressed != null)
                    const Row(
                      children: [
                         AppCoinIcon(size: 35, withGlow: true),
                        SizedBox(width: 4),
                        
                      ],
                    )
                  else if (onTopUpPressed != null)
                    GestureDetector(
                      onTap: onTopUpPressed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.add_circle_rounded, color: Color(0xFF141417), size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Top Up',
                              style: TextStyle(
                                color: Color(0xFF141417),
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 0),

              // 2. Large Coin Balance & Rupee Equivalent
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$balance',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Coins',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // const Spacer(),
                  // Container(
                  //   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  //   decoration: BoxDecoration(
                  //     color: const Color(0xFFFFD54F).withValues(alpha: 0.2),
                  //     borderRadius: BorderRadius.circular(10),
                  //     border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.4)),
                  //   ),
                  //   child: Text(
                  //     '≈ ₹$balance',
                  //     style: const TextStyle(
                  //       color: Color(0xFFFFD54F),
                  //       fontSize: 14,
                  //       fontWeight: FontWeight.w900,
                  //     ),
                  //   ),
                  // ),
                ],
              ),

              // if (subtitle != null) ...[
              //   const SizedBox(height: 12),
              //   const Divider(color: Colors.white24, height: 1),
              //   const SizedBox(height: 8),
              //   Row(
              //     children: [
              //       const Icon(Icons.verified_user_rounded, color: Color(0xFF6EE7B7), size: 14),
              //       const SizedBox(width: 6),
              //       Expanded(
              //         child: Text(
              //           subtitle!,
              //           style: const TextStyle(
              //             color: Colors.white70,
              //             fontSize: 11,
              //             fontWeight: FontWeight.w500,
              //           ),
              //         ),
              //       ),
              //     ],
              //   ),
              // ],
            ],
          ),
        ],
      ),
    );
  }
}
