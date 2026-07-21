import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/features/call/presentation/widgets/report_block_dialog.dart';
import 'package:dating_app/features/call/application/matchmaking_controller.dart';
import 'package:dating_app/features/call/application/matchmaking_state.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';
import 'package:dating_app/features/chat/application/chat_controller.dart';

class ChatPage extends ConsumerStatefulWidget {
  final String conversationId;
  final String userId;
  final String userName;
  final String? userAvatar;

  const ChatPage({
    super.key,
    required this.conversationId,
    required this.userId,
    required this.userName,
    this.userAvatar,
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

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: colors.surface,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFE5DFFF),
              child: Text(
                initials,
                style: const TextStyle(
                  color: Color(0xFF6B4EFF),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.userName,
                  style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
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
                    'Online', // Ideally driven by real presence state, mocked for now
                    style: typography.bodySmall.copyWith(
                      color: colors.success,
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

              context.push(RouteNames.calling);
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
            child: chatState.messages.isEmpty && chatState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true, // newest messages at the bottom
                    padding: const EdgeInsets.all(AppSpacing.space16),
                    itemCount: chatState.messages.length + (chatState.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == chatState.messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final msg = chatState.messages[index];
                      final isMe = msg.senderId == currentUser?.id;
                      final bubbleBg = isMe ? colors.primary : colors.surface;
                      final txtColor = isMe ? Colors.white : colors.textPrimary;
                      final alignment = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Column(
                          crossAxisAlignment: alignment,
                          children: [
                            Container(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75,
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
                                  msg.status == 'read' ? Icons.done_all : Icons.check,
                                  size: 14,
                                  color: msg.status == 'read' ? Colors.blue : colors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            color: colors.surface,
            padding: const EdgeInsets.all(12.0),
            child: Row(
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
                      style: typography.bodyMedium,
                      onChanged: _onTyping,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: typography.bodySmall,
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
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
