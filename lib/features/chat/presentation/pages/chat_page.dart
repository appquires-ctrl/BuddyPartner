import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/features/call/presentation/widgets/report_block_dialog.dart';

/// ChatPage renders the scrollable messaging page for textual chat.
/// Features customized message bubbles and quick access to voice calls/reporting dialogs.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _messages.add({'text': text, 'isMe': true});
        _messageController.clear();
      });
      // Mock automated reply
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _messages.add({'text': 'That sounds cool! Let\'s talk on a call?', 'isMe': false});
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    const imgUrl = 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=100';

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
            const CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage(imgUrl),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Priya',
                  style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Online',
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
          // Quick call action
          IconButton(
            icon: Icon(Icons.call, color: colors.primary),
            onPressed: () => context.push(RouteNames.calling),
          ),
          // Report option
          IconButton(
            icon: Icon(Icons.more_vert, color: colors.textSecondary),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const ReportBlockDialog(),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Scrollable messages list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.space16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['isMe'] as bool;
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
                          msg['text'] as String,
                          style: typography.bodyMedium.copyWith(color: txtColor, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Bottom message input field keyboard bar
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
