import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:think_agent/services/intent_file_service.dart';

void main() {
  late Directory tmpDir;
  late String filePath;
  late IntentFileService service;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('intent_test_');
    filePath = '${tmpDir.path}/.quanttide/intent.md';
    service = IntentFileService(filePath: filePath);
  });

  tearDown(() {
    service.dispose();
    tmpDir.deleteSync(recursive: true);
  });

  test('init creates directory and file', () async {
    await service.init();
    expect(File(filePath).existsSync(), true);
  });

  test('writeContent then readContent returns same content', () async {
    await service.init();
    const content = '# 意图文档\n\n## 目标\n测试目标';
    await service.writeContent(content);
    final read = await service.readContent();
    expect(read, content);
  });

  test('readContent returns empty string for missing file', () async {
    final content = await service.readContent();
    expect(content, '');
  });

  test('write then read IntentModel', () async {
    await service.init();
    const content = '# 意图文档\n生成时间：\n\n## 目标\n测试目标\n\n## 当前探索\n测试探索\n\n## 约束\n测试约束\n\n## 状态\n测试状态';
    await service.writeContent(content);
    final model = await service.readIntentModel();
    expect(model.goal, '测试目标');
    expect(model.exploration, '测试探索');
    expect(model.constraints, '测试约束');
    expect(model.state, '测试状态');
  });

  test('onFileChanged fires after external file write', () async {
    await service.init();
    final completer = Completer<String>();
    service.onFileChanged = (content) {
      if (!completer.isCompleted) completer.complete(content);
    };
    const content = '## 目标\n外部写入';
    File(filePath).writeAsStringSync(content);
    await completer.future.timeout(const Duration(seconds: 2));
    expect(await completer.future, content);
  });
}
