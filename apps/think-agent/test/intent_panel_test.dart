import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:think_agent/blocs/intent_sync_bloc.dart';
import 'package:think_agent/models/intent_model.dart';
import 'package:think_agent/services/intent_file_service.dart';
import 'package:think_agent/widgets/intent_panel.dart';

Widget wrapWithMaterial(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('IntentPanel', () {
    testWidgets('renders four field labels', (tester) async {
      await tester.pumpWidget(wrapWithMaterial(
        IntentPanel(
          intentModel: IntentModel(),
          onChanged: (_) {},
        ),
      ));
      expect(find.text('目标'), findsAtLeast(1));
      expect(find.text('当前探索'), findsAtLeast(1));
      expect(find.text('约束'), findsOneWidget);
      expect(find.text('状态'), findsOneWidget);
    });

    testWidgets('displays goal text', (tester) async {
      final model = IntentModel(goal: '测试目标内容');
      await tester.pumpWidget(wrapWithMaterial(
        IntentPanel(
          intentModel: model,
          onChanged: (_) {},
        ),
      ));
      expect(find.text('测试目标内容'), findsOneWidget);
    });

    testWidgets('displays all fields', (tester) async {
      final model = IntentModel(
        goal: '目标',
        exploration: '探索内容',
        constraints: '约束内容',
        state: '状态内容',
      );
      await tester.pumpWidget(wrapWithMaterial(
        IntentPanel(
          intentModel: model,
          onChanged: (_) {},
        ),
      ));
      expect(find.text('探索内容'), findsOneWidget);
      expect(find.text('约束内容'), findsOneWidget);
      expect(find.text('状态内容'), findsOneWidget);
    });

    testWidgets('export BRD button exists', (tester) async {
      await tester.pumpWidget(wrapWithMaterial(
        IntentPanel(
          intentModel: IntentModel(),
          onChanged: (_) {},
        ),
      ));
      expect(find.text('导出 BRD'), findsOneWidget);
    });
  });

  group('IntentPanel with BLoC integration', () {
    testWidgets('updates when BLoC state changes', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('panel_test_');
      final file = IntentFileService(filePath: '${tmp.path}/intent.md');
      final bloc = IntentSyncBloc(
        initialDocumentContent: '# 意图文档\n\n## 目标\n旧目标',
        fileService: file,
      );
      addTearDown(() {
        bloc.close();
        file.dispose();
      });

      await tester.pumpWidget(wrapWithMaterial(
        BlocProvider.value(
          value: bloc,
          child: BlocBuilder<IntentSyncBloc, IntentSyncState>(
            builder: (context, state) {
              final model = IntentModel.fromMarkdown(state.documentContent);
              return IntentPanel(
                intentModel: model,
                onChanged: (_) {},
              );
            },
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('旧目标'), findsOneWidget);

      bloc.add(const AiEditFile('# 意图文档\n\n## 目标\n新目标'));
      await Future(() {});
      await tester.pump();
      expect(find.text('新目标'), findsOneWidget);
      expect(find.text('旧目标'), findsNothing);
    });
  });
}
