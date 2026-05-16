import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:think_agent/blocs/intent_sync_bloc.dart';
import 'package:think_agent/services/intent_file_service.dart';
import 'package:think_agent/services/opencode_service.dart';

void main() {
  late IntentFileService file;
  late IntentSyncBloc bloc;

  setUp(() {
    final tmp = Directory.systemTemp.createTempSync('bloc_test_');
    file = IntentFileService(filePath: '${tmp.path}/intent.md');
  });

  tearDown(() {
    bloc.close();
    file.dispose();
  });

  group('initial state', () {
    test('is Aligned with initial content', () {
      bloc = IntentSyncBloc(
        initialDocumentContent: '# 初始文档',
        fileService: file,
      );
      expect(bloc.state, isA<Aligned>());
      expect(bloc.state.documentContent, '# 初始文档');
    });

    test('Aligned has lastApprovedContent == documentContent', () {
      bloc = IntentSyncBloc(
        initialDocumentContent: '# 初始文档',
        fileService: file,
      );
      final s = bloc.state as Aligned;
      expect(s.lastApprovedContent, s.documentContent);
    });
  });

  group('aligned → ai_drift', () {
    setUp(() {
      bloc = IntentSyncBloc(
        initialDocumentContent: '# 初始文档',
        fileService: file,
      );
    });

    test('AiEditFile transitions to AiDrift', () async {
      bloc.add(const AiEditFile('# AI 修改'));
      await Future(() {});
      expect(bloc.state, isA<AiDrift>());
      expect(bloc.state.documentContent, '# AI 修改');
    });

    test('AiDrift preserves lastApprovedContent', () async {
      bloc.add(const AiEditFile('# AI 修改'));
      await Future(() {});
      final s = bloc.state as AiDrift;
      expect(s.lastApprovedContent, '# 初始文档');
    });
  });

  group('state transitions', () {
    setUp(() {
      bloc = IntentSyncBloc(
        initialDocumentContent: '# 初始文档',
        fileService: file,
      );
    });

    test('HumanReviewConfirm transitions AiDrift to Aligned', () async {
      bloc.add(const AiEditFile('# AI 修改'));
      await Future(() {});
      bloc.add(const HumanReviewConfirm());
      await Future(() {});
      expect(bloc.state, isA<Aligned>());
      expect(bloc.state.documentContent, '# AI 修改');
    });

    test('HumanEditSave transitions to HumanOverride', () async {
      bloc.add(const HumanEditSave('# 人类编辑'));
      await Future(() {});
      expect(bloc.state, isA<HumanOverride>());
      expect(bloc.state.documentContent, '# 人类编辑');
    });

    test('HumanEditSave overrides AiDrift', () async {
      bloc.add(const AiEditFile('# AI 修改'));
      await Future(() {});
      bloc.add(const HumanEditSave('# 人类编辑'));
      await Future(() {});
      expect(bloc.state, isA<HumanOverride>());
      expect(bloc.state.documentContent, '# 人类编辑');
    });

    test('consecutive AiEditFile updates content', () async {
      bloc.add(const AiEditFile('# AI v1'));
      await Future(() {});
      bloc.add(const AiEditFile('# AI v2'));
      await Future(() {});
      expect(bloc.state, isA<AiDrift>());
      expect(bloc.state.documentContent, '# AI v2');
    });

    test('HumanEditSave writes to file', () async {
      bloc.add(const HumanEditSave('# 写入测试'));
      await Future.delayed(const Duration(milliseconds: 50));
      final content = await file.readContent();
      expect(content, '# 写入测试');
    });
  });
}
