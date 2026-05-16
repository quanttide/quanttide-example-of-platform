import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/intent_sync_bloc.dart';
import 'screens/home_screen.dart';
import 'services/opencode_service.dart';

void main() {
  runApp(const ThinkAgentApp());
}

class ThinkAgentApp extends StatelessWidget {
  const ThinkAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ocService = OpenCodeService(
      host: '127.0.0.1',
      port: 4096,
    );
    return MultiBlocProvider(
      providers: [
        RepositoryProvider.value(value: ocService),
        BlocProvider(
          create: (_) => IntentSyncBloc(
            initialDocumentContent: _defaultIntentDoc,
            openCodeService: ocService,
          ),
        ),
      ],
      child: MaterialApp(
        title: '意图澄清工具',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

const _defaultIntentDoc = '''# 意图文档
生成时间：

## 目标

## 当前探索

## 约束

## 状态
''';
