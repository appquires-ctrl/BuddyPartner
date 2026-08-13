import 'package:flutter/material.dart';
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
import 'package:buddypartner/features/chat/application/presence_provider.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';

import 'package:buddypartner/core/utils/app_logger.dart';

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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(() {
      ref.read(presenceProvider.notifier).fetchPresence([widget.userId]);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(chatControllerProvider(widget.conversationId).notifier).loadMore();
    }
  }

  void _sendMessage() {
    AppLogger.button('Send Chat Message', screen: 'ChatPage');
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      ref.read(chatControllerProvider(widget.conversationId).notifier).sendMessage(text);
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
      ref.read(chatControllerProvider(widget.conversationId).notifier).sendTyping();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final initials = getInitials(widget.userName);
    
    final chatState = ref.watch(chatControllerProvider(widget.conversationId));
    final currentUser = ref.watch(authStateProvider).value;
    final isOnline = ref.watch(presenceProvider)[widget.userId] ?? false;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/app_bg.jpeg',
          fit: BoxFit.cover,
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            titleSpacing: 0,
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colors.textPrimary),
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
                  radius: 18,
                  showStatus: true,
                  isOnline: isOnline,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.userName,
                      style: typography.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
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
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: typography.bodySmall.copyWith(
                          color: isOnline ? colors.success : colors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.call, color: colors.primary),
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
                icon: Icon(Icons.more_vert, color: colors.textSecondary),
                onPressed: () {
                  // Pass the reported user ID + conversation info down to the dialog
                  showDialog(
                    context: context,
                    builder: (context) => ReportBlockDialog(
                      reportedUserId: widget.userId,
                      conversationId: widget.conversationId,
                    ),
                  );
                },
              ),
            ],
          ),
          body: Column(
        children: [
          Expanded(
            child: chatState.errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.space24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.danger.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.error_outline_rounded,
                              color: colors.danger,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            chatState.errorMessage!,
                            style: typography.bodyMedium.copyWith(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              ref.read(chatControllerProvider(widget.conversationId).notifier).loadInitial();
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Try Again'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: const RoundedRectangleBorder(
                                borderRadius: AppRadius.pill,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : chatState.messages.isEmpty && chatState.isLoading
                    ? const ChatMessageSkeleton()
                    : ListView.builder(
                    controller: _scrollController,
                    reverse: true, // newest messages at the bottom
                    padding: const EdgeInsets.all(AppSpacing.space16),
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
                      final bubbleBg = isMe ? colors.primary : colors.surface;
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
                                    maxWidth: MediaQuery.of(context).size.width * 0.70,
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: bubbleBg,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: Radius.circular(isMe ? 16 : 0),
                                      bottomRight: Radius.circular(isMe ? 0 : 16),
                                    ),
                                    border: isMe ? null : Border.all(color: colors.border),
                                  ),
                                  child: Text(
                                    msg.content,
                                    style: typography.bodyMedium.copyWith(color: txtColor, fontSize: 14),
                                  ),
                                ),
                                if (isMe)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2, right: 4),
                                    child: Icon(
                                      msg.status == 'sent'
                                          ? Icons.check
                                          : Icons.done_all,
                                      size: 14,
                                      color: msg.status == 'read'
                                          ? colors.primary
                                          : colors.textSecondary,
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
          else
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.border.withValues(alpha: 0.5))),
                boxShadow: [
                  BoxShadow(
                    color: colors.textPrimary.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                bottom: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space16,
                    vertical: 10.0,
                  ),
                  child: Builder(
                    builder: (context) {
                      // Subscription bypass: Allow all users to send messages immediately
                      // final subState = ref.watch(subscriptionStatusProvider).value;
                      // final isSubscribed = subState?.isSubscribed ?? false;
                      // if (!isSubscribed) { ... }

                      return Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: colors.surfaceMuted,
                                borderRadius: AppRadius.pill,
                                border: Border.all(color: colors.border),
                              ),
                              child: TextField(
                                controller: _messageController,
                                style: typography.bodyMedium.copyWith(color: colors.textPrimary),
                                onChanged: _onTyping,
                                textInputAction: TextInputAction.send,
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle: typography.bodySmall.copyWith(
                                    color: colors.textSecondary,
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.space16,
                                    vertical: 12,
                                  ),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _sendMessage,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: colors.primary,
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
                      );
                    },
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
