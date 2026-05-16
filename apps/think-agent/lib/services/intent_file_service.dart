import 'dart:async';
import 'dart:io';
import '../models/intent_model.dart';

class IntentFileService {
  final String filePath;
  File? _file;
  Timer? _debounceTimer;
  StreamSubscription? _watchSubscription;
  String _lastWrittenContent = '';
  String _lastReadContent = '';
  void Function(String content)? onFileChanged;

  IntentFileService({required this.filePath}) {
    _file = File(filePath);
  }

  Future<void> init() async {
    if (_file == null) return;
    final dir = _file!.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    if (!await _file!.exists()) {
      await _file!.writeAsString('');
    }
    _lastReadContent = await readContent();
    watch();
  }

  Future<String> readContent() async {
    if (_file == null) return '';
    try {
      if (await _file!.exists()) {
        return await _file!.readAsString();
      }
    } catch (_) {}
    return '';
  }

  Future<void> writeContent(String content) async {
    if (_file == null) return;
    _lastWrittenContent = content;
    try {
      final dir = _file!.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await _file!.writeAsString(content);
    } catch (_) {}
  }

  void watch() {
    if (_file == null) return;
    final dir = _file!.parent;
    _watchSubscription = dir.watch(events: FileSystemEvent.modify).listen(
      (event) {
        if (event.path != _file!.path) return;
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
          final content = await readContent();
          if (content == _lastWrittenContent || content == _lastReadContent) {
            return;
          }
          _lastReadContent = content;
          onFileChanged?.call(content);
        });
      },
      onError: (_) {},
    );
  }

  Future<IntentModel> readIntentModel() async {
    final content = await readContent();
    return IntentModel.fromMarkdown(content);
  }

  Future<void> writeIntentModel(IntentModel model) async {
    await writeContent(model.toMarkdown());
  }

  void dispose() {
    _debounceTimer?.cancel();
    _watchSubscription?.cancel();
  }
}
