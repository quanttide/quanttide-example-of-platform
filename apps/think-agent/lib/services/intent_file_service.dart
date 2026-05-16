import 'dart:async';
import 'dart:io';
import '../models/intent_model.dart';

class IntentFileService {
  final String filePath;
  File? _file;
  Timer? _debounceTimer;
  void Function(String content)? onFileChanged;

  IntentFileService({required this.filePath}) {
    _file = File(filePath);
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
    await _file!.writeAsString(content);
  }

  Future<void> watch() async {
    if (_file == null) return;
    final dir = _file!.parent;
    if (!await dir.exists()) return;
    await for (final event in dir.watch(events: FileSystemEvent.modify)) {
      if (event.path == _file!.path) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
          final content = await readContent();
          onFileChanged?.call(content);
        });
      }
    }
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
  }
}
