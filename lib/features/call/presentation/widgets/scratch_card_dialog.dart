import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';
import 'package:buddypartner/features/call/domain/models/instant_connect_models.dart';

class ScratchCardDialog extends ConsumerStatefulWidget {
  final ScratchCardModel card;

  const ScratchCardDialog({super.key, required this.card});

  static Future<void> show(BuildContext context, ScratchCardModel card) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ScratchCardDialog(card: card),
    );
  }

  @override
  ConsumerState<ScratchCardDialog> createState() => _ScratchCardDialogState();
}

class _ScratchCardDialogState extends ConsumerState<ScratchCardDialog> {
  final List<Offset?> _scratchPoints = [];
  bool _isRevealed = false;
  bool _isClaiming = false;
  bool _isClaimed = false;
  int? _claimedCoins;

  @override
  void initState() {
    super.initState();
    if (widget.card.isScratched) {
      _isRevealed = true;
      _isClaimed = true;
      _claimedCoins = widget.card.coinReward;
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    if (_isRevealed) return;
    setState(() {
      final RenderBox box = context.findRenderObject() as RenderBox;
      final localPos = box.globalToLocal(details.globalPosition);
      _scratchPoints.add(localPos);

      // Reveal automatically when user has made enough scratches
      if (_scratchPoints.length > 28) {
        _isRevealed = true;
      }
    });
  }

  Future<void> _handleClaim() async {
    if (_isClaiming || _isClaimed) return;
    setState(() => _isClaiming = true);

    final reward = await ref
        .read(instantConnectControllerProvider.notifier)
        .claimScratchCard(widget.card.id);

    setState(() {
      _isClaiming = false;
      if (reward != null) {
        _isClaimed = true;
        _claimedCoins = reward;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final reward = _claimedCoins ?? widget.card.coinReward;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C6AEF), Color(0xFFB57CF6)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    '10-MIN CALL REWARD',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text(
              _isRevealed ? '🎉 Congratulations!' : 'Scratch & Win Coins!',
              style: typography.titleCard.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _isRevealed
                  ? 'Your reward from your recent VIP instant call'
                  : 'Rub your finger across the card to reveal your reward',
              style: typography.bodySmall.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Scratch Surface Box
            GestureDetector(
              onPanUpdate: (details) => _onPanUpdate(details, const Size(220, 160)),
              onTap: () {
                setState(() => _isRevealed = true);
              },
              child: Container(
                width: 220,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isRevealed
                        ? [const Color(0xFFFFF8E1), const Color(0xFFFFECB3)]
                        : [const Color(0xFF7C6AEF), const Color(0xFF9E8CF8)],
                  ),
                  border: Border.all(
                    color: _isRevealed ? const Color(0xFFFFB300) : const Color(0xFF7C6AEF),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_isRevealed ? const Color(0xFFFFB300) : const Color(0xFF7C6AEF))
                          .withValues(alpha: 0.25),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Revealed Content
                    if (_isRevealed)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.monetization_on, color: Color(0xFFFF8F00), size: 42),
                          const SizedBox(height: 6),
                          Text(
                            '+$reward Coins',
                            style: const TextStyle(
                              color: Color(0xFFE65100),
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '≈ ₹$reward Real Value',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else
                      // Foil surface
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.touch_app_rounded, color: Colors.white70, size: 36),
                          const SizedBox(height: 8),
                          Text(
                            'SCRATCH HERE',
                            style: typography.bodyMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: !_isRevealed
                    ? () => setState(() => _isRevealed = true)
                    : (_isClaimed ? () => Navigator.pop(context) : _handleClaim),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isClaimed ? colors.success : const Color(0xFF7C6AEF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isClaiming
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text(
                        !_isRevealed
                            ? 'Tap to Reveal'
                            : (_isClaimed ? 'Done (Claimed to Wallet)' : 'Claim $reward Coins to Wallet'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
