import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:docs_agent/cubits/markdown_document_cubit.dart';
import 'package:docs_agent/ui/markdown_editor_panel.dart';
import 'package:docs_agent/services/document_storage.dart';

class _MockStorage implements DocumentStorage {
  @override
  Future<String> read() async => '';
  @override
  Future<void> write(String content) async {}
  @override
  Stream<String> watch() => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

Widget _buildApp(MarkdownDocumentCubit cubit, {String filePath = '/path/to/doc.md'}) {
  return MaterialApp(
    home: MarkdownEditorPanel(cubit: cubit, filePath: filePath),
  );
}

void main() {
  late MarkdownDocumentCubit cubit;

  setUp(() {
    cubit = MarkdownDocumentCubit(
      initialContent: '# Test Doc',
      storage: _MockStorage(),
    );
  });

  group('MarkdownEditorPanel', () {
    testWidgets('renders editor with initial content', (tester) async {
      await tester.pumpWidget(_buildApp(cubit, filePath: '/tmp/test.md'));
      expect(find.text('/tmp/test.md'), findsOneWidget);
      expect(find.text('# Test Doc'), findsOneWidget);
    });

    testWidgets('updates cubit on text change', (tester) async {
      await tester.pumpWidget(_buildApp(cubit));
      final textField = find.byType(TextField);
      await tester.enterText(textField, '# New Content');
      expect(cubit.state, '# New Content');
    });

    testWidgets('shows export button', (tester) async {
      await tester.pumpWidget(_buildApp(cubit));
      expect(find.byIcon(Icons.file_copy), findsOneWidget);
    });

    testWidgets('export copies to clipboard', (tester) async {
      await tester.pumpWidget(_buildApp(cubit));
      await tester.tap(find.byIcon(Icons.file_copy));
      await tester.pumpAndSettle();
      expect(find.text('文档已复制到剪贴板'), findsOneWidget);
    });

    testWidgets('shows hint text when empty', (tester) async {
      final emptyCubit = MarkdownDocumentCubit(
        initialContent: '',
        storage: _MockStorage(),
      );
      await tester.pumpWidget(_buildApp(emptyCubit));
      expect(find.text('在此输入 Markdown 内容...'), findsOneWidget);
    });
  });
}
