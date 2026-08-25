import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/core/widgets/shimmer/skeletons/chat_message_skeleton.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/features/call/presentation/widgets/report_block_dialog.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/chat/application/chat_controller.dart';
import 'package:buddypartner/features/chat/application/conversations_provider.dart';
import 'package:buddypartner/features/chat/data/chat_repository.dart';
import 'package:buddypartner/features/chat/application/presence_provider.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/core/widgets/feedback/in_app_notification_banner.dart';

class ChatPage extends ConsumerStatefulWidget {
  final String conversationId;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String? avatarSeed;
  final String? avatarStyle;
  final String? gender;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.avatarSeed,
    this.avatarStyle,
    this.gender,
  });

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  String get _effectiveConversationId =>
      widget.conversationId.isNotEmpty ? widget.conversationId : 'user:${widget.userId}';

  @override
  void initState() {
    super.initState();
    InAppNotificationManager.activeConversationId = _effectiveConversationId;
    _scrollController.addListener(_onScroll);
    Future.microtask(() {
      ref.read(conversationsProvider.notifier).markConversationAsRead(_effectiveConversationId);
      ref.read(chatRepositoryProvider).markConversationAsRead(_effectiveConversationId);
      ref.read(presenceProvider.notifier).fetchPresence([widget.userId]);
    });
  }

  @override
  void dispose() {
    if (InAppNotificationManager.activeConversationId == _effectiveConversationId ||
        InAppNotificationManager.activeConversationId == widget.userId) {
      InAppNotificationManager.activeConversationId = null;
    }
    ref.read(conversationsProvider.notifier).markConversationAsRead(_effectiveConversationId);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(chatControllerProvider(_effectiveConversationId).notifier).loadMore();
    }
  }

  void _sendMessage([String? customText]) {
    AppLogger.button('Send Chat Message', screen: 'ChatPage');
    final text = (customText ?? _messageController.text).trim();
    if (text.isNotEmpty) {
      final isSubscribed = ref.read(subscriptionStatusProvider).value?.isSubscribed ?? false;
      if (!isSubscribed) {
        if (mounted) {
          AppSnackBar.showError(context, 'An active subscription is required to send messages.');
          context.push(RouteNames.subscribe);
        }
        return;
      }

      ref.read(chatControllerProvider(_effectiveConversationId).notifier).sendMessage(text);
      _messageController.clear();
      // Scroll to bottom (since we are reversed, bottom is 0)
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  void _onTyping(String value) {
    if (value.isNotEmpty) {
      ref.read(chatControllerProvider(_effectiveConversationId).notifier).sendTyping();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final initials = getInitials(widget.userName);

    final chatState = ref.watch(chatControllerProvider(_effectiveConversationId));
    final currentUser = ref.watch(authStateProvider).value;
    final isOnline = ref.watch(presenceProvider)[widget.userId] ?? false;
    final isSubscribed = ref.watch(subscriptionStatusProvider).value?.isSubscribed ?? false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/app_bg.jpg',
          fit: BoxFit.cover,
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            titleSpacing: 0,
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: colors.textPrimary),
              onPressed: () => context.pop(),
            ),
            title: Row(
              children: [
                GradientAvatar(
                  initials: initials,
                  avatarSeed: widget.avatarSeed,
                  avatarStyle: widget.avatarStyle,
                  gender: widget.gender,
                  userAvatar: widget.userAvatar,
                  radius: 19,
                  showStatus: true,
                  isOnline: isOnline,
                  statusIndicatorSize: 11,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.userName,
                      style: typography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    if (chatState.typingUserId == widget.userId)
                      Text(
                        'typing...',
                        style: typography.bodySmall.copyWith(
                          color: colors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Row(
                        children: [
                          if (isOnline) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            isOnline ? 'Online' : 'Offline',
                            style: typography.bodySmall.copyWith(
                              color: isOnline ? const Color(0xFF10B981) : colors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.phone_rounded, color: colors.primary, size: 18),
                ),
                onPressed: () {
                  final matchState = ref.read(matchmakingControllerProvider);
                  if (matchState.phase != MatchmakingPhase.idle) return;

                  ref.read(matchmakingControllerProvider.notifier).callUser(
                        targetUserId: widget.userId,
                        targetUserName: widget.userName,
                      );
                },
              ),
              IconButton(
                icon: Icon(Icons.more_vert_rounded, color: colors.textSecondary),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => ReportBlockDialog(
                      reportedUserId: widget.userId,
                      conversationId: _effectiveConversationId,
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: chatState.isLoading && chatState.messages.isEmpty
                    ? const ChatMessageSkeleton()
                    : (chatState.errorMessage != null && chatState.messages.isEmpty)
                        ? _buildErrorEmptyState(context, isDark, chatState.errorMessage!)
                        : (chatState.messages.isEmpty)
                            ? _buildIcebreakerEmptyState(context, isDark)
                            : ListView.builder(
                                controller: _scrollController,
                                reverse: true, // newest messages at the bottom
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                itemCount: chatState.messages.length + (chatState.hasMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == chatState.messages.length) {
                                    return Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: AppLoadingIndicator(
                                        size: 20,
                                        color: colors.primary,
                                      ),
                                    );
                                  }

                                  final msg = chatState.messages[index];
                                  final isMe = msg.senderId == currentUser?.id;
                                  final bubbleBg = isMe
                                      ? colors.primary
                                      : (isDark ? const Color(0xFF1E1A2E) : Colors.white);
                                  final txtColor = isMe ? Colors.white : colors.textPrimary;
                                  final alignment = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: Row(
                                      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        if (!isMe) ...[
                                          GradientAvatar(
                                            initials: initials,
                                            avatarSeed: widget.avatarSeed,
                                            avatarStyle: widget.avatarStyle,
                                            gender: widget.gender,
                                            userAvatar: widget.userAvatar,
                                            radius: 14,
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Column(
                                          crossAxisAlignment: alignment,
                                          children: [
                                            Container(
                                              constraints: BoxConstraints(
                                                maxWidth: MediaQuery.of(context).size.width * 0.72,
                                              ),
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                              decoration: BoxDecoration(
                                                color: bubbleBg,
                                                borderRadius: BorderRadius.only(
                                                  topLeft: const Radius.circular(18),
                                                  topRight: const Radius.circular(18),
                                                  bottomLeft: Radius.circular(isMe ? 18 : 3),
                                                  bottomRight: Radius.circular(isMe ? 3 : 18),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                                border: isMe
                                                    ? null
                                                    : Border.all(
                                                        color: isDark
                                                            ? colors.border.withValues(alpha: 0.2)
                                                            : colors.border.withValues(alpha: 0.6),
                                                      ),
                                              ),
                                              child: Text(
                                                msg.content,
                                                style: typography.bodyMedium.copyWith(
                                                  color: txtColor,
                                                  fontSize: 14.5,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ),
                                            if (isMe)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2, right: 4),
                                                child: Icon(
                                                  msg.status == 'sent'
                                                      ? Icons.check_rounded
                                                      : Icons.done_all_rounded,
                                                  size: 14,
                                                  color: msg.status == 'read'
                                                      ? colors.primary
                                                      : colors.textSecondary.withValues(alpha: 0.7),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),

              // Bottom Input Bar
              if (chatState.isBlocked || (chatState.errorMessage?.toLowerCase().contains('block') ?? false))
                Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceMuted,
                    border: Border(top: BorderSide(color: colors.border.withValues(alpha: 0.5))),
                  ),
                  child: SafeArea(
                    top: false,
                    bottom: true,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space16),
                      child: Center(
                        child: Text(
                          'You cannot message this user.',
                          style: typography.bodyMedium.copyWith(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else if (!isSubscribed)
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                  ),
                  child: SafeArea(
                    top: false,
                    bottom: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space16,
                        vertical: 10.0,
                      ),
                      child: GestureDetector(
                        onTap: () {
                          AppLogger.click('Subscribe to Chat Prompt Bar', screen: 'ChatPage');
                          context.push(RouteNames.subscribe);
                        },
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFFE879F9)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: AppRadius.pill,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_open_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Subscribe to Send Messages',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.0,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                  ),
                  child: SafeArea(
                    top: false,
                    bottom: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 10.0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E1A2E) : Colors.white,
                                borderRadius: AppRadius.pill,
                                border: Border.all(
                                  color: isDark
                                      ? colors.border.withValues(alpha: 0.25)
                                      : colors.border.withValues(alpha: 0.8),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.035),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _messageController,
                                style: typography.bodyMedium.copyWith(
                                  color: colors.textPrimary,
                                  fontSize: 14.0,
                                ),
                                onChanged: _onTyping,
                                textInputAction: TextInputAction.send,
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle: typography.bodySmall.copyWith(
                                    color: colors.textSecondary.withValues(alpha: 0.7),
                                    fontSize: 14.0,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 13,
                                  ),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => _sendMessage(),
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [colors.primary, const Color(0xFFE879F9)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.primary.withValues(alpha: 0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
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
      ],
    );
  }

  /// Icebreaker Match Empty State
  Widget _buildIcebreakerEmptyState(BuildContext context, bool isDark) {
    final colors = context.colors;
    final initials = getInitials(widget.userName);
    final firstName = widget.userName.split(' ').first;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Dual-ring Match Avatar
            Container(
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFFFF5277)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: GradientAvatar(
                initials: initials,
                avatarSeed: widget.avatarSeed,
                avatarStyle: widget.avatarStyle,
                gender: widget.gender,
                userAvatar: widget.userAvatar,
                radius: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You matched with $firstName!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
                letterSpacing: -0.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Say hello or pick a conversation starter below ✨',
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Quick Icebreaker Chips
            Wrap(
              spacing: 8,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _buildIcebreakerChip(
                  context,
                  isDark,
                  'Hey $firstName! 👋',
                ),
                _buildIcebreakerChip(
                  context,
                  isDark,
                  'How is your day going? 😊',
                ),
                _buildIcebreakerChip(
                  context,
                  isDark,
                  'Nice to meet you! ✨',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcebreakerChip(BuildContext context, bool isDark, String text) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _messageController.text = text;
        _sendMessage(text);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? colors.border.withValues(alpha: 0.25)
                : colors.border.withValues(alpha: 0.8),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
      ),
    );
  }

  /// Elegant Connection Error State
  Widget _buildErrorEmptyState(BuildContext context, bool isDark, String errorMessage) {
    final colors = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1A2E) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? colors.border.withValues(alpha: 0.25)
                  : colors.border.withValues(alpha: 0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: colors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Connecting to Chat...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Could not load messages right now. Tap below to refresh.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () {
                  ref.read(chatControllerProvider(_effectiveConversationId).notifier).loadInitial();
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh Chat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
