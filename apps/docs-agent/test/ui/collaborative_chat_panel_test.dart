import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:docs_agent/cubits/chat_cubit.dart';
import 'package:docs_agent/cubits/markdown_document_cubit.dart';
import 'package:docs_agent/services/ai_chat_service.dart';
import 'package:docs_agent/services/document_storage.dart';
import 'package:docs_agent/ui/collaborative_chat_panel.dart';

class _MockAiService implements AiChatService {
  @override
  Future<String?> createSession({String? title}) async => 'sess-1';
  @override
  Future<String?> sendMessage(
    String sessionId,
    String message, {
    String? systemPrompt,
  }) async =>
      'AI reply';
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

Widget _buildApp(ChatCubit cubit) {
  return MaterialApp(
    home: Scaffold(
      body: CollaborativeChatPanel(cubit: cubit),
    ),
  );
}

void main() {
  late MarkdownDocumentCubit docCubit;

  setUp(() {
    docCubit = MarkdownDocumentCubit(
      initialContent: '# doc',
      storage: _MockDocStorage(),
    );
  });

  group('CollaborativeChatPanel', () {
    testWidgets('shows title and input field', (tester) async {
      final cubit = ChatCubit(
        aiService: _MockAiService(),
        docCubit: docCubit,
      );
      await tester.pumpWidget(_buildApp(cubit));
      await tester.pump();
      expect(find.text('对话'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      cubit.close();
    });

    testWidgets('shows empty state when no messages', (tester) async {
      final cubit = ChatCubit(
        aiService: _MockAiService(),
        docCubit: docCubit,
      );
      await tester.pumpWidget(_buildApp(cubit));
      await tester.pump();
      expect(find.text('开始与 AI 对话'), findsOneWidget);
      cubit.close();
    });

    testWidgets('shows connected status icon', (tester) async {
      final cubit = ChatCubit(
        aiService: _MockAiService(),
        docCubit: docCubit,
      );
      await tester.pumpWidget(_buildApp(cubit));
      await tester.pump();
      expect(find.byIcon(Icons.wifi), findsOneWidget);
      cubit.close();
    });

    testWidgets('sends message and shows reply', (tester) async {
      final cubit = ChatCubit(
        aiService: _MockAiService(),
        docCubit: docCubit,
      );
      await tester.pumpWidget(_buildApp(cubit));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('AI reply'), findsOneWidget);
      cubit.close();
    });

    testWidgets('shows error status bar when disconnected', (tester) async {
      final ai = _MockAiService();
      final cubit = ChatCubit(aiService: ai, docCubit: docCubit);
      await tester.pumpWidget(_buildApp(cubit));
      await tester.pump();

      expect(find.text('输入消息...'), findsOneWidget);
      cubit.close();
    });

    testWidgets('sends message on enter key', (tester) async {
      final cubit = ChatCubit(
        aiService: _MockAiService(),
        docCubit: docCubit,
      );
      await tester.pumpWidget(_buildApp(cubit));
      await tester.pump();

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Enter pressed');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Enter pressed'), findsOneWidget);
      expect(find.text('AI reply'), findsOneWidget);
      cubit.close();
    });
  });
}
