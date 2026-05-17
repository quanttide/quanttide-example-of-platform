import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'cubits/markdown_document_cubit.dart';
import 'cubits/chat_cubit.dart';
import 'services/file_document_storage.dart';
import 'services/opencode_chat_service.dart';
import 'ui/markdown_editor_panel.dart';
import 'ui/collaborative_chat_panel.dart';
import 'ui/document_agent_layout.dart';

void main() {
  runApp(DocAgentApp());
}

class DocAgentApp extends StatefulWidget {
  const DocAgentApp({super.key});

  @override
  State<DocAgentApp> createState() => _DocAgentAppState();
}

class _DocAgentAppState extends State<DocAgentApp> {
  late final String _docFilePath;
  late final FileDocumentStorage _storage;
  late final OpenCodeChatService _aiService;
  late final MarkdownDocumentCubit _docCubit;
  late final ChatCubit _chatCubit;

  @override
  void initState() {
    super.initState();
    _docFilePath = '/home/iguo/data/intent.md';

    _storage = FileDocumentStorage(filePath: _docFilePath);
    _aiService = OpenCodeChatService(
      host: '127.0.0.1',
      port: 4096,
    );
    _docCubit = MarkdownDocumentCubit(
      initialContent: _defaultDoc,
      storage: _storage,
    );
    _chatCubit = ChatCubit(aiService: _aiService, docCubit: _docCubit);
  }

  @override
  void dispose() {
    _chatCubit.close();
    _aiService.dispose();
    _storage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _docCubit),
        BlocProvider.value(value: _chatCubit),
      ],
      child: MaterialApp(
        title: '文档智能体',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: DocumentAgentLayout(
          editor: MarkdownEditorPanel(cubit: _docCubit, filePath: _docFilePath),
          chat: CollaborativeChatPanel(cubit: _chatCubit),
        ),
      ),
    );
  }
}

ThemeData _buildTheme() {
  const base = Color(0xFF1A1A2E);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: base,
      onPrimary: Colors.white,
      secondary: const Color(0xFF16213E),
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: const Color(0xFF1C1C1E),
      error: Colors.redAccent,
      onError: Colors.white,
    ),
    scaffoldBackgroundColor: const Color(0xFFF5F5F7),
    appBarTheme: const AppBarTheme(
      backgroundColor: base,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}

const _defaultDoc = '''# 项目文档
生成时间：

## 目标

## 当前进展

## 约束

## 待办
''';
