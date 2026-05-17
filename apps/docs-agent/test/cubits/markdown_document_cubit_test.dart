import 'package:flutter_test/flutter_test.dart';
import 'package:docs_agent/cubits/markdown_document_cubit.dart';
import 'package:docs_agent/services/document_storage.dart';

class _MockStorage implements DocumentStorage {
  String? _written;
  @override
  Future<String> read() async => '';
  @override
  Future<void> write(String content) async => _written = content;
  @override
  Stream<String> watch() => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

void main() {
  late _MockStorage storage;
  late MarkdownDocumentCubit cubit;

  setUp(() {
    storage = _MockStorage();
    cubit = MarkdownDocumentCubit(
      initialContent: '# init',
      storage: storage,
    );
  });

  group('initial state', () {
    test('emits initial content', () {
      expect(cubit.state, '# init');
    });
  });

  group('fromFile', () {
    test('emits new content without writing to storage', () {
      cubit.fromFile('# from file');
      expect(cubit.state, '# from file');
      expect(storage._written, isNull);
    });
  });

  group('fromEditor', () {
    test('emits and writes to storage', () {
      cubit.fromEditor('# from editor');
      expect(cubit.state, '# from editor');
      expect(storage._written, '# from editor');
    });
  });

  group('fromAgent', () {
    test('emits and writes to storage', () {
      cubit.fromAgent('# from agent');
      expect(cubit.state, '# from agent');
      expect(storage._written, '# from agent');
    });
  });

  group('stream', () {
    test('changes state on each update', () {
      cubit.fromEditor('a');
      expect(cubit.state, 'a');
      cubit.fromFile('b');
      expect(cubit.state, 'b');
      cubit.fromAgent('c');
      expect(cubit.state, 'c');
    });
  });
}
