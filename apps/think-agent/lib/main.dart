import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/intent_sync_bloc.dart';
import 'screens/home_screen.dart';
import 'services/intent_file_service.dart';
import 'services/opencode_service.dart';

void main() {
  runApp(const ThinkAgentApp());
}

class ThinkAgentApp extends StatelessWidget {
  const ThinkAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    final workspace = Platform.environment['OPENCODE_WORKSPACE'] ??
        Directory.current.path;
    final intentFilePath = '$workspace/.quanttide/intent.md';
    final ocService = OpenCodeService(
      host: '127.0.0.1',
      port: 4096,
    );
    final fileService = IntentFileService(filePath: intentFilePath);
    return MultiBlocProvider(
      providers: [
        RepositoryProvider.value(value: ocService),
        RepositoryProvider.value(value: fileService),
        BlocProvider(
          create: (_) => IntentSyncBloc(
            initialDocumentContent: _defaultIntentDoc,
            fileService: fileService,
            openCodeService: ocService,
          ),
        ),
      ],
      child: MaterialApp(
        title: '意图澄清工具',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const HomeScreen(),
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
      backgroundColor: Color(0xFF1A1A2E),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}

const _defaultIntentDoc = '''# 意图文档
生成时间：

## 目标

## 当前探索

## 约束

## 状态
''';
