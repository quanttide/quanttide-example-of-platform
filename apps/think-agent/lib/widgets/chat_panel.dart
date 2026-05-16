import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/intent_sync_bloc.dart';
import '../models/intent_model.dart';
import '../services/opencode_service.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _messages = <_ChatMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String? _sessionId;
  bool _sending = false;

  static const _userBubble = Color(0xFFE3F2FD);
  static const _aiBubble = Color(0xFFF5F5F5);
  static const _primary = Color(0xFF1A1A2E);

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initSession() async {
    final oc = context.read<OpenCodeService>();
    final id = await oc.createSession(title: 'think-agent');
    if (id != null && mounted) {
      setState(() => _sessionId = id);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sessionId == null || _sending) return;
    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _sending = true;
    });
    _scrollToBottom();
    context.read<IntentSyncBloc>().add(const UserSendMessage());
    final oc = context.read<OpenCodeService>();
    final state = context.read<IntentSyncBloc>().state;
    final reply = await oc.sendMessage(
      _sessionId!,
      text,
      includeIntent: true,
      intentDoc: state.documentContent,
    );
    if (mounted) {
      setState(() {
        if (reply != null) {
          final cleaned = _parseAndApplyIntentUpdate(reply);
          _messages.add(_ChatMessage(role: 'assistant', content: cleaned));
        } else {
          _messages.add(_ChatMessage(
            role: 'assistant',
            content: '(未连接到 OpenCode serve，请确认服务已启动)',
          ));
        }
        _sending = false;
      });
      _scrollToBottom();
    }
  }

  String _parseAndApplyIntentUpdate(String reply) {
    final updatePattern = RegExp(
      r'\[INTENT_UPDATE\](.*?)\[/INTENT_UPDATE\]',
      dotAll: true,
    );
    final match = updatePattern.firstMatch(reply);
    if (match == null) return reply;
    final updateContent = match.group(1)?.trim() ?? '';
    final cleaned = reply.replaceAll(match.group(0)!, '').trim();
    final intentModel = IntentModel.fromMarkdown(
      context.read<IntentSyncBloc>().state.documentContent,
    );
    final updated = _mergeIntentUpdate(intentModel, updateContent);
    context.read<IntentSyncBloc>().add(AiEditFile(updated.toMarkdown()));
    return cleaned;
  }

  IntentModel _mergeIntentUpdate(IntentModel current, String update) {
    var model = current;
    for (final line in update.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('goal:')) {
        model = model.copyWith(goal: trimmed.substring(5).trim());
      } else if (trimmed.startsWith('exploration:')) {
        model = model.copyWith(exploration: trimmed.substring(12).trim());
      } else if (trimmed.startsWith('constraints:')) {
        model = model.copyWith(constraints: trimmed.substring(12).trim());
      } else if (trimmed.startsWith('state:')) {
        model = model.copyWith(state: trimmed.substring(6).trim());
      }
    }
    return model;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_sessionId == null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFFFFF8E1),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: Color(0xFFB8860B)),
                const SizedBox(width: 8),
                const Text(
                  '正在连接 OpenCode serve...',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8D6E00)),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final isUser = msg.role == 'user';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment:
                      isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!isUser) ...[
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: _primary,
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
                          color: isUser ? _userBubble : _aiBubble,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isUser ? 16 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 16),
                          ),
                        ),
                        child: Text(
                          msg.content,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Color(0xFF1C1C1E),
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
          ),
        ),
        if (_sending)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _primary.withAlpha(100),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'AI 思考中...',
                  style: TextStyle(
                    fontSize: 12,
                    color: _primary.withAlpha(120),
                  ),
                ),
              ],
            ),
          ),
        Container(
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: '输入探索内容...',
                    hintStyle:
                        TextStyle(color: Colors.grey[400], fontSize: 14),
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
                      borderSide: BorderSide(color: _primary, width: 1.5),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 14),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: _primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _sending ? null : _sendMessage,
                  icon: const Icon(Icons.arrow_upward, color: Colors.white),
                  iconSize: 18,
                  constraints:
                      const BoxConstraints(minWidth: 38, minHeight: 38),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatMessage {
  final String role;
  final String content;
  const _ChatMessage({required this.role, required this.content});
}
