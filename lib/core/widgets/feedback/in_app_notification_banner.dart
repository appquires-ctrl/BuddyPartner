import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';

/// Model representing an in-app notification message
class InAppMessageNotification {
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String? avatarSeed;
  final String? avatarStyle;
  final String? gender;
  final String message;
  final String conversationId;
  final bool isGroup;
  final String? groupId;
  final DateTime timestamp;

  InAppMessageNotification({
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    this.avatarSeed,
    this.avatarStyle,
    this.gender,
    required this.message,
    required this.conversationId,
    this.isGroup = false,
    this.groupId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Global stream controller for in-app message notifications
class InAppNotificationManager {
  static final StreamController<InAppMessageNotification> _controller =
      StreamController<InAppMessageNotification>.broadcast();

  static Stream<InAppMessageNotification> get stream => _controller.stream;

  /// Currently open conversation or group ID (to suppress notifications while inside that room)
  static String? activeConversationId;

  /// Whether the user is currently on the Messages list tab (index 1 of dashboard)
  static bool isMessagesTabActive = false;

  /// Returns true if the user is currently anywhere in the chat/messaging flow
  static bool get isInChatSection => isMessagesTabActive || activeConversationId != null;

  /// Shows an in-app notification banner
  static void show(InAppMessageNotification notification) {
    // Only show in-app banner if user is browsing other features outside the chat/messaging section
    if (isInChatSection) {
      return;
    }
    _controller.add(notification);
  }
}

/// Global overlay widget that listens for in-app notifications and renders an interactive top toast
class InAppNotificationOverlay extends StatefulWidget {
  final Widget child;
  final void Function(InAppMessageNotification notification)? onNotificationTap;

  const InAppNotificationOverlay({
    super.key,
    required this.child,
    this.onNotificationTap,
  });

  @override
  State<InAppNotificationOverlay> createState() => _InAppNotificationOverlayState();
}

class _InAppNotificationOverlayState extends State<InAppNotificationOverlay>
    with SingleTickerProviderStateMixin {
  StreamSubscription<InAppMessageNotification>? _subscription;
  InAppMessageNotification? _currentNotification;
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));

    _subscription = InAppNotificationManager.stream.listen(_handleNewNotification);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _dismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _handleNewNotification(InAppMessageNotification notification) {
    _dismissTimer?.cancel();
    setState(() {
      _currentNotification = notification;
    });

    HapticFeedback.lightImpact();
    _animController.forward(from: 0.0);

    _dismissTimer = Timer(const Duration(seconds: 4), () {
      _dismiss();
    });
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    if (_animController.isAnimating || _animController.isCompleted) {
      _animController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _currentNotification = null;
          });
        }
      });
    }
  }

  void _handleTap() {
    final notif = _currentNotification;
    if (notif == null) return;
    HapticFeedback.selectionClick();
    _dismiss();
    widget.onNotificationTap?.call(notif);
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        widget.child,

        if (_currentNotification != null)
          Positioned(
            top: topPadding + 10,
            left: 14,
            right: 14,
            child: SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: GestureDetector(
                  onVerticalDragUpdate: (details) {
                    if (details.primaryDelta != null && details.primaryDelta! < -4) {
                      _dismiss();
                    }
                  },
                  onTap: _handleTap,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E1B38), Color(0xFF131024)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF7C6AEF).withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7C6AEF).withValues(alpha: 0.25),
                            blurRadius: 16,
                            spreadRadius: 1,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // 1. Sender Avatar with live ring
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFF7C6AEF), Color(0xFFE879F9)],
                              ),
                            ),
                            child: GradientAvatar(
                              initials: _currentNotification!.senderName.isNotEmpty
                                  ? _currentNotification!.senderName[0].toUpperCase()
                                  : 'U',
                              avatarSeed: _currentNotification!.avatarSeed,
                              avatarStyle: _currentNotification!.avatarStyle,
                              gender: _currentNotification!.gender,
                              userAvatar: _currentNotification!.senderAvatar,
                              radius: 20,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // 2. Message details
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _currentNotification!.senderName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: -0.2,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF7C6AEF).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'New Message',
                                        style: TextStyle(
                                          color: Color(0xFFB5A7FF),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _currentNotification!.message,
                                  style: const TextStyle(
                                    color: Color(0xFFD1CEE8),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    height: 1.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),

                          // 3. Action button / indicator
                          const SizedBox(width: 8),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C6AEF).withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Color(0xFFB5A7FF),
                              size: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
