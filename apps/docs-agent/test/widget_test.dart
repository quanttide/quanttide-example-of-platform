import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:docs_agent/main.dart';

void main() {
  testWidgets('app renders without crash', (tester) async {
    await tester.pumpWidget(DocAgentApp());
    await tester.pump();
    expect(find.byType(DocAgentApp), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
