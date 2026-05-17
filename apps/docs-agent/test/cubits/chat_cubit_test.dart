import 'package:flutter_test/flutter_test.dart';
import 'package:docs_agent/cubits/chat_cubit.dart';
import 'package:docs_agent/cubits/markdown_document_cubit.dart';
import 'package:docs_agent/services/ai_chat_service.dart';
import 'package:docs_agent/services/document_storage.dart';

class _MockAiService implements AiChatService {
  String? sessionId;
  List<String> sentMessages = [];
  String? response;
  bool createFails = false;
  bool sendFails = false;

  @override
  Future<String?> createSession({String? title}) async {
    if (createFails) return null;
    sessionId = 'sess-1';
    return sessionId;
  }

  @override
  Future<String?> sendMessage(
    String sessionId,
    String message, {
    String? systemPrompt,
  }) async {
    sentMessages.add(message);
    if (sendFails) return null;
    return response;
  }

  @override
  Future<bool> clearSession(String sessionId) async => true;
}

class _MockDocStorage implements DocumentStorage {
  @override
  Future<String> read() async => '';
  @override
  Future<void> write(String content) async {}
  @override
  Stream<String> watch() => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

void main() {
  late _MockAiService aiService;
  late MarkdownDocumentCubit docCubit;

  setUp(() {
    aiService = _MockAiService();
    final storage = _MockDocStorage();
    docCubit = MarkdownDocumentCubit(
      initialContent: '# doc',
      storage: storage,
    );
  });

  group('initialization', () {
    test('starts disconnected then connects', () async {
      final cubit = ChatCubit(aiService: aiService, docCubit: docCubit);
      await Future(() {});
      expect(cubit.state.status, ChatStatus.connected);
      expect(cubit.state.sessionId, 'sess-1');
      cubit.close();
    });

    test('handles session creation failure', () async {
      aiService.createFails = true;
      final cubit = ChatCubit(aiService: aiService, docCubit: docCubit);
      await Future(() {});
      expect(cubit.state.status, ChatStatus.error);
      expect(cubit.state.errorMessage, isNotNull);
      cubit.close();
    });
  });

  group('sendMessage', () {
    test('sends message and receives reply', () async {
      aiService.response = 'Hello from AI';
      final cubit = ChatCubit(aiService: aiService, docCubit: docCubit);
      await Future(() {});
      await cubit.sendMessage('Hi');
      expect(cubit.state.messages.length, 2);
      expect(cubit.state.messages[0].role, 'user');
      expect(cubit.state.messages[0].content, 'Hi');
      expect(cubit.state.messages[1].role, 'assistant');
      expect(cubit.state.messages[1].content, 'Hello from AI');
      expect(cubit.state.status, ChatStatus.connected);
      cubit.close();
    });

    test('handles send failure', () async {
      aiService.sendFails = true;
      final cubit = ChatCubit(aiService: aiService, docCubit: docCubit);
      await Future(() {});
      await cubit.sendMessage('Hi');
      expect(cubit.state.messages.length, 2);
      expect(cubit.state.messages[1].content,
          contains('未连接到 OpenCode 服务'));
      expect(cubit.state.status, ChatStatus.error);
      cubit.close();
    });

    test('ignores empty message', () async {
      final cubit = ChatCubit(aiService: aiService, docCubit: docCubit);
      await Future(() {});
      await cubit.sendMessage('   ');
      expect(cubit.state.messages, isEmpty);
      cubit.close();
    });

    test('handles null session', () async {
      aiService.createFails = true;
      final cubit = ChatCubit(aiService: aiService, docCubit: docCubit);
      await Future(() {});
      await cubit.sendMessage('Hi');
      expect(cubit.state.messages.length, 1);
      expect(cubit.state.messages[0].role, 'user');
      expect(cubit.state.messages[0].content, 'Hi');
      cubit.close();
    });
  });

  group('INTENT_UPDATE parsing', () {
    test('updates doc with full reply', () async {
      aiService.response = '# Updated doc\n\nSome content';
      final cubit = ChatCubit(aiService: aiService, docCubit: docCubit);
      await Future(() {});
      await cubit.sendMessage('update');
      expect(cubit.state.messages.length, 2);
      expect(cubit.state.messages[1].content, '# Updated doc\n\nSome content');
      expect(docCubit.state, '# Updated doc\n\nSome content');
      cubit.close();
    });

    test('handles reply with INTENT_UPDATE', () async {
      aiService.response =
          'Some text\n[INTENT_UPDATE]\n# Full doc\n[/INTENT_UPDATE]';
      final cubit = ChatCubit(aiService: aiService, docCubit: docCubit);
      await Future(() {});
      await cubit.sendMessage('update');
      expect(cubit.state.messages[1].content,
          'Some text\n[INTENT_UPDATE]\n# Full doc\n[/INTENT_UPDATE]');
      expect(docCubit.state,
          'Some text\n[INTENT_UPDATE]\n# Full doc\n[/INTENT_UPDATE]');
      cubit.close();
    });
  });

  group('ChatState.copyWith', () {
    test('uses defaults when no args provided', () {
      const state = ChatState();
      final copy = state.copyWith();
      expect(copy.messages, []);
      expect(copy.status, ChatStatus.disconnected);
      expect(copy.sessionId, isNull);
      expect(copy.errorMessage, isNull);
    });

    test('overrides specific fields', () {
      const state = ChatState();
      final copy = state.copyWith(
        status: ChatStatus.connected,
        sessionId: 'sess-2',
      );
      expect(copy.status, ChatStatus.connected);
      expect(copy.sessionId, 'sess-2');
    });
  });

  group('close', () {
    test('can be closed', () async {
      final cubit = ChatCubit(aiService: aiService, docCubit: docCubit);
      await Future(() {});
      await cubit.close();
      expect(cubit.state.status, ChatStatus.connected);
    });
  });
}
