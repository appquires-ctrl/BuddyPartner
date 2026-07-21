import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/features/chat/application/conversations_provider.dart';
import 'package:dating_app/features/chat/domain/conversation.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';

class ConversationsListPage extends ConsumerWidget {
  const ConversationsListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final conversationsAsync = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        centerTitle: false,
        backgroundColor: colors.surface,
        elevation: 0.5,
      ),
      body: conversationsAsync.when(
        data: (conversations) {
          if (conversations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: colors.textSecondary.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text(
                    'No messages yet',
                    style: typography.bodyMedium.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(conversationsProvider.notifier).refresh(),
            child: ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: colors.border),
              itemBuilder: (context, index) {
                final conv = conversations[index];
                return _ConversationTile(conversation: conv);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error loading conversations', style: typography.bodyMedium),
              TextButton(
                onPressed: () => ref.read(conversationsProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;

  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final initials = getInitials(conversation.otherUserName);

    // Format time (simple relative format)
    final now = DateTime.now();
    final isToday = now.year == conversation.lastMessageAt.year && 
                    now.month == conversation.lastMessageAt.month && 
                    now.day == conversation.lastMessageAt.day;
    final timeStr = isToday 
        ? '${conversation.lastMessageAt.hour.toString().padLeft(2, '0')}:${conversation.lastMessageAt.minute.toString().padLeft(2, '0')}' 
        : '${conversation.lastMessageAt.month}/${conversation.lastMessageAt.day}';

    return InkWell(
      onTap: () {
        context.push(RouteNames.chat, extra: {
          'conversationId': conversation.id,
          'userId': conversation.otherUserId,
          'userName': conversation.otherUserName,
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFFE5DFFF),
              child: Text(
                initials,
                style: const TextStyle(
                  color: Color(0xFF6B4EFF),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          conversation.otherUserName,
                          style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: typography.bodySmall.copyWith(color: colors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessage ?? 'Say hi!',
                          style: typography.bodySmall.copyWith(
                            color: conversation.unreadCount > 0 ? colors.textPrimary : colors.textSecondary,
                            fontWeight: conversation.unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            conversation.unreadCount > 9 ? '9+' : conversation.unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
