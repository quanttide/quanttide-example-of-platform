import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

// ============================================================
// Services (保持不变)
// ============================================================

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
    if (!await dir.exists()) await dir.create(recursive: true);
    if (!await _file!.exists()) await _file!.writeAsString('');
    _lastReadContent = await readContent();
    watch();
  }

  Future<String> readContent() async {
    if (_file == null) return '';
    try {
      if (await _file!.exists()) return await _file!.readAsString();
    } catch (_) {}
    return '';
  }

  Future<void> writeContent(String content) async {
    if (_file == null) return;
    _lastWrittenContent = content;
    try {
      final dir = _file!.parent;
      if (!await dir.exists()) await dir.create(recursive: true);
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
          if (content == _lastWrittenContent || content == _lastReadContent) return;
          _lastReadContent = content;
          onFileChanged?.call(content);
        });
      },
      onError: (_) {},
    );
  }

  void dispose() {
    _debounceTimer?.cancel();
    _watchSubscription?.cancel();
  }
}

class OpenCodeService {
  final String host;
  final int port;
  final String? password;
  final String? username;
  final http.Client _client = http.Client();

  OpenCodeService({this.host = '127.0.0.1', this.port = 4096, this.password, this.username});

  String get _baseUrl => 'http://$host:$port';

  Map<String, String> get _headers {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (password != null) {
      final cred = base64Encode(utf8.encode('${username ?? 'opencode'}:$password'));
      headers['Authorization'] = 'Basic $cred';
    }
    return headers;
  }

  Future<bool> health() async {
    try {
      final res = await _client.get(Uri.parse('$_baseUrl/global/health'), headers: _headers);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> createSession({String? parentId, String? title}) async {
    try {
      final body = <String, dynamic>{};
      if (parentId != null) body['parentID'] = parentId;
      if (title != null) body['title'] = title;
      final res = await _client.post(Uri.parse('$_baseUrl/session'),
          headers: _headers, body: body.isEmpty ? null : jsonEncode(body));
      if (res.statusCode == 200) return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String?;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> sendMessage(String sessionId, String text,
      {bool includeIntent = false, String? intentDoc}) async {
    try {
      final parts = [{'type': 'text', 'text': text}];
      final body = <String, dynamic>{'parts': parts};
      if (includeIntent && intentDoc != null) {
        body['system'] = '''$intentDoc

当你发现对话中意图发生结构性变化时（目标切换、方向调整、约束新增、阶段转换），在回复末尾附加：
[INTENT_UPDATE]
...更新的意图文档 Markdown...
[/INTENT_UPDATE]

如果没有变化，不要附加。变化很细微时也不要触发更新。''';
      }
      final res = await _client.post(Uri.parse('$_baseUrl/session/$sessionId/message'),
          headers: _headers, body: jsonEncode(body));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final partsList = data['parts'] as List<dynamic>?;
        if (partsList != null && partsList.isNotEmpty) {
          return partsList.where((p) => p['type'] == 'text').map((p) => p['text'] as String).join('\n');
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}

// ============================================================
// Intent Cubit (管理文档字符串)
// ============================================================

class IntentCubit extends Cubit<String> {
  final IntentFileService _fileService;

  IntentCubit({required String initialDocument, required IntentFileService fileService})
      : _fileService = fileService,
        super(initialDocument);

  void updateFromFile(String content) {
    if (content != state) emit(content);
  }

  void updateFromEditor(String content) {
    if (content != state) {
      emit(content);
      _fileService.writeContent(content);
    }
  }

  void updateFromAi(String content) {
    if (content != state) {
      emit(content);
      _fileService.writeContent(content);
    }
  }
}

// ============================================================
// Chat Cubit (管理对话状态)
// ============================================================

class _ChatMessage {
  final String role;
  final String content;
  const _ChatMessage({required this.role, required this.content});
}

class ChatState {
  final List<_ChatMessage> messages;
  final String? sessionId;
  final bool isSending;
  final String? error;

  const ChatState({
    this.messages = const [],
    this.sessionId,
    this.isSending = false,
    this.error,
  });

  ChatState copyWith({
    List<_ChatMessage>? messages,
    String? sessionId,
    bool? isSending,
    String? error,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      sessionId: sessionId ?? this.sessionId,
      isSending: isSending ?? this.isSending,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ChatCubit extends Cubit<ChatState> {
  final OpenCodeService _ocService;
  final IntentCubit _intentCubit;

  ChatCubit({
    required OpenCodeService ocService,
    required IntentCubit intentCubit,
  })  : _ocService = ocService,
        _intentCubit = intentCubit,
        super(const ChatState());

  Future<void> initSession() async {
    final id = await _ocService.createSession(title: 'think-agent');
    emit(state.copyWith(sessionId: id));
  }

  Future<void> sendMessage(String text) async {
    final sessionId = state.sessionId;
    if (sessionId == null || state.isSending || text.trim().isEmpty) return;

    // 添加用户消息
    final userMessage = _ChatMessage(role: 'user', content: text);
    emit(state.copyWith(
      messages: [...state.messages, userMessage],
      isSending: true,
      clearError: true,
    ));

    try {
      // 获取当前意图文档
      final intentDoc = _intentCubit.state;
      final reply = await _ocService.sendMessage(
        sessionId,
        text,
        includeIntent: true,
        intentDoc: intentDoc,
      );

      if (reply != null) {
        final cleaned = _parseAndApplyIntentUpdate(reply);
        final aiMessage = _ChatMessage(role: 'assistant', content: cleaned);
        emit(state.copyWith(
          messages: [...state.messages, aiMessage],
          isSending: false,
        ));
      } else {
        emit(state.copyWith(
          messages: [
            ...state.messages,
            const _ChatMessage(
                role: 'assistant', content: '(未连接到 OpenCode serve，请确认服务已启动)'),
          ],
          isSending: false,
          error: '连接失败',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        isSending: false,
        error: e.toString(),
      ));
    }
  }

  String _parseAndApplyIntentUpdate(String reply) {
    final updatePattern = RegExp(r'\[INTENT_UPDATE\](.*?)\[/INTENT_UPDATE\]', dotAll: true);
    final match = updatePattern.firstMatch(reply);
    if (match == null) return reply;
    final newDoc = match.group(1)?.trim() ?? '';
    final cleaned = reply.replaceAll(match.group(0)!, '').trim();
    _intentCubit.updateFromAi(newDoc);
    return cleaned;
  }
}

// ============================================================
// Chat Panel UI
// ============================================================

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key});
  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  static const _userBubble = Color(0xFFE3F2FD);
  static const _aiBubble = Color(0xFFF5F5F5);
  static const _primary = Color(0xFF1A1A2E);

  @override
  void initState() {
    super.initState();
    context.read<ChatCubit>().initSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<ChatCubit>().sendMessage(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChatCubit, ChatState>(
      listener: (context, state) {
        if (state.messages.isNotEmpty) _scrollToBottom();
      },
      builder: (context, chatState) {
        return Column(
          children: [
            if (chatState.sessionId == null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: const Color(0xFFFFF8E1),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: Color(0xFFB8860B)),
                    const SizedBox(width: 8),
                    const Text('正在连接 OpenCode serve...',
                        style: TextStyle(fontSize: 12, color: Color(0xFF8D6E00))),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                itemCount: chatState.messages.length,
                itemBuilder: (context, index) {
                  final msg = chatState.messages[index];
                  final isUser = msg.role == 'user';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!isUser) ...[
                          CircleAvatar(
                              radius: 14,
                              backgroundColor: _primary,
                              child: const Text('AI',
                                  style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600))),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isUser ? _userBubble : _aiBubble,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isUser ? 16 : 4),
                                bottomRight: Radius.circular(isUser ? 4 : 16),
                              ),
                            ),
                            child: Text(msg.content,
                                style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF1C1C1E))),
                          ),
                        ),
                        if (isUser) ...[
                          const SizedBox(width: 8),
                          CircleAvatar(
                              radius: 14,
                              backgroundColor: const Color(0xFF4FC3F7),
                              child: const Icon(Icons.person, size: 16, color: Colors.white)),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            if (chatState.isSending)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _primary.withAlpha(100))),
                    const SizedBox(width: 8),
                    Text('AI 思考中...', style: TextStyle(fontSize: 12, color: _primary.withAlpha(120))),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 4, offset: const Offset(0, -1))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: '输入探索内容...',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey[300]!)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey[300]!)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: _primary, width: 1.5)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 14),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(color: _primary, shape: BoxShape.circle),
                    child: IconButton(
                      onPressed: chatState.isSending ? null : _sendMessage,
                      icon: const Icon(Icons.arrow_upward, color: Colors.white),
                      iconSize: 18,
                      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================
// Intent Editor (简单的 Markdown 编辑器)
// ============================================================

class IntentEditor extends StatefulWidget {
  final String document;
  final ValueChanged<String> onChanged;
  const IntentEditor({super.key, required this.document, required this.onChanged});

  @override
  State<IntentEditor> createState() => _IntentEditorState();
}

class _IntentEditorState extends State<IntentEditor> {
  late TextEditingController _controller;

  static const _darkCard = Color(0xFF16213E);
  static const _darkText = Color(0xFFE8E8E8);
  static const _darkLabel = Color(0xFF8E8E9A);
  static const _accent = Color(0xFF4FC3F7);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.document);
  }

  @override
  void didUpdateWidget(IntentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      _controller.text = widget.document;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _exportBrd() {
    Clipboard.setData(ClipboardData(text: _controller.text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('BRD 已复制到剪贴板'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: _darkCard,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(children: [
            Container(width: 3, height: 16, decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            const Text('意图文档', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _darkText, letterSpacing: 0.3)),
          ]),
        ),
        const SizedBox(height: 4),
        Divider(color: _darkLabel.withAlpha(40), height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Container(
              decoration: BoxDecoration(color: _darkCard, borderRadius: BorderRadius.circular(8)),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                  isDense: true,
                  hintText: '输入意图文档 Markdown...',
                  hintStyle: TextStyle(color: _darkLabel.withAlpha(100)),
                ),
                style: const TextStyle(fontSize: 13, color: _darkText, height: 1.5),
                onChanged: (value) => widget.onChanged(value),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _exportBrd,
              icon: const Icon(Icons.file_copy, size: 15),
              label: const Text('导出 BRD'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: _accent.withAlpha(80)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Home Screen
// ============================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    final fileService = context.read<IntentFileService>();
    fileService.onFileChanged = (content) => context.read<IntentCubit>().updateFromFile(content);
    fileService.init();
  }

  @override
  void dispose() {
    context.read<IntentFileService>().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;
    return BlocBuilder<IntentCubit, String>(
      builder: (context, document) {
        if (isWide) {
          return Row(children: [
            const Expanded(flex: 3, child: ChatPanel()),
            Container(width: 1, color: Colors.black.withAlpha(26)),
            Expanded(
              flex: 2,
              child: Container(
                color: const Color(0xFF1A1A2E),
                child: IntentEditor(
                  document: document,
                  onChanged: (newDoc) => context.read<IntentCubit>().updateFromEditor(newDoc),
                ),
              ),
            ),
          ]);
        }
        return Column(children: [
          ExpansionTile(
            title: const Text('当前意图'),
            initiallyExpanded: false,
            children: [
              SizedBox(
                height: 250,
                child: IntentEditor(
                  document: document,
                  onChanged: (newDoc) => context.read<IntentCubit>().updateFromEditor(newDoc),
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          const Expanded(child: ChatPanel()),
        ]);
      },
    );
  }
}

// ============================================================
// App Entry
// ============================================================

const _defaultIntentDoc = '''# 意图文档
生成时间：

## 目标

## 当前探索

## 约束

## 状态
''';

void main() {
  runApp(const ThinkAgentApp());
}

class ThinkAgentApp extends StatelessWidget {
  const ThinkAgentApp({super.key});
  @override
  Widget build(BuildContext context) {
    final workspace = Platform.environment['OPENCODE_WORKSPACE'] ?? Directory.current.path;
    final intentFilePath = '$workspace/.quanttide/intent.md';
    final ocService = OpenCodeService(host: '127.0.0.1', port: 4096);
    final fileService = IntentFileService(filePath: intentFilePath);

    return MultiBlocProvider(
      providers: [
        RepositoryProvider.value(value: ocService),
        RepositoryProvider.value(value: fileService),
        BlocProvider<IntentCubit>(
          create: (_) => IntentCubit(
            initialDocument: _defaultIntentDoc,
            fileService: fileService,
          ),
        ),
        BlocProvider<ChatCubit>(
          create: (context) => ChatCubit(
            ocService: ocService,
            intentCubit: context.read<IntentCubit>(),
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
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1A1A2E), foregroundColor: Colors.white, elevation: 0),
  );
}