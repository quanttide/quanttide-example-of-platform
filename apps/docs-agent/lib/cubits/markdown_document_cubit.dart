import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/document_storage.dart';

class MarkdownDocumentCubit extends Cubit<String> {
  final DocumentStorage _storage;

  MarkdownDocumentCubit({
    required String initialContent,
    required DocumentStorage storage,
  })  : _storage = storage,
        super(initialContent);

  void fromFile(String content) {
    emit(content);
  }

  void fromEditor(String content) {
    emit(content);
    _storage.write(content);
  }

  void fromAgent(String content) {
    emit(content);
    _storage.write(content);
  }
}
