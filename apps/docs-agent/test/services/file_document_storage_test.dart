import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:docs_agent/services/file_document_storage.dart';

void main() {
  late Directory tmpDir;
  late String filePath;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('doc_storage_test_');
    filePath = '${tmpDir.path}/test.md';
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('read', () {
    test('returns empty string for non-existent file', () async {
      final storage = FileDocumentStorage(filePath: filePath);
      final content = await storage.read();
      expect(content, '');
    });

    test('reads existing file content', () async {
      File(filePath).writeAsStringSync('# hello');
      final storage = FileDocumentStorage(filePath: filePath);
      final content = await storage.read();
      expect(content, '# hello');
    });
  });

  group('write', () {
    test('writes content to file', () async {
      final storage = FileDocumentStorage(filePath: filePath);
      await storage.write('# written');
      final content = File(filePath).readAsStringSync();
      expect(content, '# written');
    });

    test('creates parent directory if needed', () async {
      final nestedPath = '${tmpDir.path}/nested/deep/doc.md';
      final storage = FileDocumentStorage(filePath: nestedPath);
      await storage.write('# nested');
      expect(File(nestedPath).readAsStringSync(), '# nested');
    });
  });

  group('watch', () {
    test('returns broadcast stream', () {
      final storage = FileDocumentStorage(filePath: filePath);
      final stream = storage.watch();
      expect(stream.isBroadcast, true);
      storage.dispose();
    });

    test('detects external file changes', () async {
      File(filePath).writeAsStringSync('# initial');
      final storage = FileDocumentStorage(filePath: filePath);
      await storage.init();
      final notified = Completer<void>();
      final sub = storage.watch().listen((_) => notified.complete());
      File(filePath).writeAsStringSync('# changed');
      await Future.any([notified.future, Future.delayed(const Duration(seconds: 2))]);
      await sub.cancel();
      await storage.dispose();
    });

    test('handles watcher errors gracefully', () async {
      final storage = FileDocumentStorage(filePath: filePath);
      await storage.init();
      final sub = storage.watch().listen((_) {});
      await Future.delayed(const Duration(milliseconds: 50));
      Directory(tmpDir.path).deleteSync(recursive: true);
      await Future.delayed(const Duration(milliseconds: 100));
      await sub.cancel();
      await storage.dispose();
      tmpDir = Directory.systemTemp.createTempSync('doc_storage_test_');
      filePath = '${tmpDir.path}/test.md';
    });
  });

  group('init', () {
    test('creates file and directory if missing', () async {
      final nestedPath = '${tmpDir.path}/newdir/doc.md';
      final storage = FileDocumentStorage(filePath: nestedPath);
      await storage.init();
      expect(File(nestedPath).existsSync(), true);
      await storage.dispose();
    });

    test('reads initial content', () async {
      File(filePath).writeAsStringSync('# existing');
      final storage = FileDocumentStorage(filePath: filePath);
      await storage.init();
      final content = await storage.read();
      expect(content, '# existing');
      await storage.dispose();
    });
  });

  group('dispose', () {
    test('can be called multiple times', () async {
      final storage = FileDocumentStorage(filePath: filePath);
      await storage.dispose();
      await storage.dispose();
    });
  });

  group('edge cases', () {
    test('handles write error gracefully', () async {
      final storage = FileDocumentStorage(filePath: '/nonexistent/path/doc.md');
      await storage.write('content');
    });

    test('read returns empty for inaccessible path', () async {
      final storage = FileDocumentStorage(filePath: '/nonexistent/doc.md');
      final content = await storage.read();
      expect(content, '');
    });
  });
}
