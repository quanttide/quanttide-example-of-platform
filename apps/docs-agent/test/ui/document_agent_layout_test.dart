import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:docs_agent/ui/document_agent_layout.dart';

Widget _buildLayout(double width) {
  return MediaQuery(
    data: MediaQueryData(size: Size(width, 800)),
    child: MaterialApp(
      home: Scaffold(
        body: DocumentAgentLayout(
          editor: const Text('editor_panel', textDirection: TextDirection.ltr),
          chat: const Text('chat_panel', textDirection: TextDirection.ltr),
        ),
      ),
    ),
  );
}

void main() {
  group('DocumentAgentLayout', () {
    testWidgets('renders editor and chat', (tester) async {
      await tester.pumpWidget(_buildLayout(800));
      expect(find.text('editor_panel'), findsOneWidget);
      expect(find.text('chat_panel'), findsOneWidget);
    });

    testWidgets('uses row layout on wide screen', (tester) async {
      await tester.pumpWidget(_buildLayout(800));
      expect(find.byType(Row), findsOneWidget);
    });

    testWidgets('uses column layout on narrow screen', (tester) async {
      await tester.pumpWidget(_buildLayout(400));
      expect(find.byType(Column), findsOneWidget);
    });

    testWidgets('shows divider on narrow screen', (tester) async {
      await tester.pumpWidget(_buildLayout(400));
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('shows vertical divider on wide screen', (tester) async {
      await tester.pumpWidget(_buildLayout(800));
      expect(find.byType(VerticalDivider), findsOneWidget);
    });
  });
}
