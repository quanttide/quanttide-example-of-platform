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
            padding: const EdgeInsets.all(8),
            color: Colors.orange[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.orange[700]),
                const SizedBox(width: 6),
                Text(
                  '正在连接 OpenCode serve...',
                  style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final isUser = msg.role == 'user';
              return Align(
                alignment:
                    isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isUser ? Colors.blue[100] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  child: Text(msg.content),
                ),
              );
            },
          ),
        ),
        if (_sending)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: '输入探索内容...',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _sendMessage,
                icon: const Icon(Icons.send),
                color: Colors.blue,
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
