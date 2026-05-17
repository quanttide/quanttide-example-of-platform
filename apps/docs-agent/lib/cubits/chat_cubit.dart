import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/ai_chat_service.dart';
import 'markdown_document_cubit.dart';

enum ChatStatus { disconnected, connected, sending, error }

class ChatState {
  final List<ChatMessage> messages;
  final ChatStatus status;
  final String? sessionId;
  final String? errorMessage;

  const ChatState({
    this.messages = const [],
    this.status = ChatStatus.disconnected,
    this.sessionId,
    this.errorMessage,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    ChatStatus? status,
    String? sessionId,
    String? errorMessage,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      status: status ?? this.status,
      sessionId: sessionId ?? this.sessionId,
      errorMessage: errorMessage,
    );
  }
}

class ChatMessage {
  final String role;
  final String content;
  const ChatMessage({required this.role, required this.content});
}

class ChatCubit extends Cubit<ChatState> {
  final AiChatService _aiService;
  final MarkdownDocumentCubit _docCubit;
  StreamSubscription? _docSubscription;
  Timer? _retryTimer;

  ChatCubit({
    required AiChatService aiService,
    required MarkdownDocumentCubit docCubit,
  })  : _aiService = aiService,
        _docCubit = docCubit,
        super(const ChatState()) {
    _initSession();
  }

  Future<void> _initSession() async {
    final id = await _aiService.createSession(title: 'docs-agent');
    if (id != null) {
      _retryTimer?.cancel();
      _retryTimer = null;
      emit(state.copyWith(status: ChatStatus.connected, sessionId: id));
    } else {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: '无法创建会话，请确认 OpenCode 服务已启动',
      ));
      _scheduleRetry();
    }
  }

  Future<void> retryConnect() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _initSession();
  }

  void _scheduleRetry() {
    if (_retryTimer != null) return;
    _retryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _initSession();
    });
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    emit(state.copyWith(
      messages: [...state.messages, ChatMessage(role: 'user', content: text)],
      status: state.sessionId != null ? ChatStatus.sending : state.status,
    ));

    if (state.sessionId == null) {
      await retryConnect();
    }
    if (state.sessionId == null) return;

    final reply = await _aiService.sendMessage(
      state.sessionId!,
      text,
      systemPrompt: _docCubit.state,
    );

    if (reply != null) {
      final cleaned = _parseAndApplyDocUpdate(reply);
      emit(state.copyWith(
        messages: [...state.messages, ChatMessage(role: 'assistant', content: cleaned)],
        status: ChatStatus.connected,
      ));
    } else {
      emit(state.copyWith(
        messages: [
          ...state.messages,
          const ChatMessage(
            role: 'assistant',
            content: '(未连接到 OpenCode 服务，请确认服务已启动)',
          ),
        ],
        status: ChatStatus.error,
        errorMessage: '消息发送失败',
      ));
    }
  }

  String _parseAndApplyDocUpdate(String reply) {
    _docCubit.fromAgent(reply);
    return reply;
  }

  @override
  Future<void> close() {
    _retryTimer?.cancel();
    _docSubscription?.cancel();
    return super.close();
  }
}
