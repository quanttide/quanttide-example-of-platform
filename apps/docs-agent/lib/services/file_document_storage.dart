import 'dart:async';
import 'dart:io';
import 'document_storage.dart';

class FileDocumentStorage implements DocumentStorage {
  final String filePath;
  File? _file;
  StreamSubscription? _watchSubscription;
  Timer? _debounceTimer;
  String _lastWrittenContent = '';
  String _lastReadContent = '';
  final _controller = StreamController<String>.broadcast();

  FileDocumentStorage({required this.filePath}) {
    _file = File(filePath);
  }

  @override
  Future<String> read() async {
    if (_file == null) return '';
    try {
      if (await _file!.exists()) {
        return await _file!.readAsString();
      }
    } catch (_) {}
    return '';
  }

  @override
  Future<void> write(String content) async {
    if (_file == null) return;
    _lastWrittenContent = content;
    try {
      final dir = _file!.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await _file!.writeAsString(content);
      _controller.add(content);
    } catch (_) {}
  }

  @override
  Stream<String> watch() {
    _startWatching();
    return _controller.stream;
  }

  void _startWatching() {
    if (_file == null) return;
    final dir = _file!.parent;
    _watchSubscription = dir.watch(events: FileSystemEvent.modify).listen(
      (event) {
        if (event.path != _file!.path) return;
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
          final content = await read();
          if (content == _lastWrittenContent || content == _lastReadContent) {
            return;
          }
          _lastReadContent = content;
          _controller.add(content);
        });
      },
      onError: (_) {},
    );
  }

  Future<void> init() async {
    final dir = _file!.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    if (!await _file!.exists()) {
      await _file!.writeAsString('');
    }
    _lastReadContent = await read();
  }

  @override
  Future<void> dispose() async {
    _debounceTimer?.cancel();
    await _watchSubscription?.cancel();
    await _controller.close();
  }
}
