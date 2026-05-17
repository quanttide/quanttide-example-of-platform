import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubits/chat_cubit.dart';

class CollaborativeChatPanel extends StatelessWidget {
  final ChatCubit cubit;
  const CollaborativeChatPanel({super.key, required this.cubit});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('对话'),
        actions: [
          _buildStatusIcon(context),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: BlocBuilder<ChatCubit, ChatState>(
              bloc: cubit,
              builder: (context, state) {
                if (state.messages.isEmpty) {
                  return const Center(
                    child: Text(
                      '开始与 AI 对话',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final msg = state.messages[index];
                    final isUser = msg.role == 'user';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: isUser
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isUser) ...[
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: const Color(0xFF1A1A2E),
                              child: const Text('AI',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? const Color(0xFFE3F2FD)
                                    : const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft:
                                      Radius.circular(isUser ? 16 : 4),
                                  bottomRight:
                                      Radius.circular(isUser ? 4 : 16),
                                ),
                              ),
                              child: Text(
                                msg.content,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                          if (isUser) ...[
                            const SizedBox(width: 8),
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: const Color(0xFF4FC3F7),
                              child: const Icon(Icons.person,
                                  size: 16, color: Colors.white),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildStatusBar(),
          _buildInputBar(context),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    return BlocBuilder<ChatCubit, ChatState>(
      bloc: cubit,
      builder: (context, state) {
        IconData icon;
        Color color;
        switch (state.status) {
          case ChatStatus.connected:
            icon = Icons.wifi;
            color = Colors.green;
          case ChatStatus.sending:
            icon = Icons.hourglass_top;
            color = Colors.orange;
          case ChatStatus.disconnected:
            icon = Icons.wifi_off;
            color = Colors.grey;
          case ChatStatus.error:
            icon = Icons.error_outline;
            color = Colors.red;
        }
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Icon(icon, size: 18, color: color),
        );
      },
    );
  }

  Widget _buildStatusBar() {
    return BlocBuilder<ChatCubit, ChatState>(
      bloc: cubit,
      builder: (context, state) {
        if (state.status == ChatStatus.connected ||
            state.status == ChatStatus.disconnected) {
          return const SizedBox.shrink();
        }
        final isSending = state.status == ChatStatus.sending;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isSending ? const Color(0xFFFFF8E1) : const Color(0xFFFFEBEE),
          child: Row(
            children: [
              Icon(
                isSending ? Icons.info_outline : Icons.error_outline,
                size: 14,
                color: isSending ? const Color(0xFFB8860B) : Colors.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSending
                      ? 'AI 思考中...'
                      : state.errorMessage ?? '连接异常',
                  style: TextStyle(
                    fontSize: 12,
                    color: isSending ? const Color(0xFF8D6E00) : Colors.red,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isSending) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => cubit.retryConnect(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('重试',
                        style: TextStyle(fontSize: 11, color: Colors.red)),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputBar(BuildContext context) {
    return BlocBuilder<ChatCubit, ChatState>(
      bloc: cubit,
      builder: (context, state) {
        final sending = state.status == ChatStatus.sending;
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 4,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: _ChatInputField(
            enabled: !sending && state.sessionId != null,
            onSend: (text) => cubit.sendMessage(text),
          ),
        );
      },
    );
  }
}

class _ChatInputField extends StatefulWidget {
  final bool enabled;
  final ValueChanged<String> onSend;
  const _ChatInputField({required this.enabled, required this.onSend});

  @override
  State<_ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<_ChatInputField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    _controller.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            enabled: widget.enabled,
            maxLines: 1,
            decoration: InputDecoration(
              hintText: widget.enabled ? '输入消息...' : '连接中...',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide:
                    const BorderSide(color: Color(0xFF1A1A2E), width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
            onSubmitted: (_) => _send(),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A2E),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: widget.enabled ? _send : null,
            icon: const Icon(Icons.arrow_upward, color: Colors.white),
            iconSize: 18,
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
