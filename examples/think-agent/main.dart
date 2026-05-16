import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

// ============================================================
// IntentModel
// ============================================================

class IntentModel {
  final String goal;
  final String exploration;
  final String constraints;
  final String state;
  final DateTime updatedAt;

  IntentModel({
    this.goal = '',
    this.exploration = '',
    this.constraints = '',
    this.state = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  IntentModel copyWith({
    String? goal,
    String? exploration,
    String? constraints,
    String? state,
    DateTime? updatedAt,
  }) {
    return IntentModel(
      goal: goal ?? this.goal,
      exploration: exploration ?? this.exploration,
      constraints: constraints ?? this.constraints,
      state: state ?? this.state,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  String toMarkdown() {
    return '''# 意图文档
生成时间：${updatedAt.toIso8601String()}

## 目标
$goal

## 当前探索
$exploration

## 约束
$constraints

## 状态
$state''';
  }

  String toContextString() {
    return '''当前意图模型：
## 目标
$goal
## 当前探索
$exploration
## 约束
$constraints
## 状态
$state''';
  }

  static IntentModel fromMarkdown(String markdown) {
    final goal = _extractSection(markdown, '## 目标');
    final exploration = _extractSection(markdown, '## 当前探索');
    final constraints = _extractSection(markdown, '## 约束');
    final state = _extractSection(markdown, '## 状态');
    return IntentModel(goal: goal, exploration: exploration, constraints: constraints, state: state);
  }

  static String _extractSection(String markdown, String heading) {
    final start = markdown.indexOf(heading);
    if (start == -1) return '';
    final contentStart = markdown.indexOf('\n', start);
    if (contentStart == -1) return '';
    final headings = ['## 目标', '## 当前探索', '## 约束', '## 状态'];
    int end = markdown.length;
    for (final h in headings) {
      if (h == heading) continue;
      final idx = markdown.indexOf(h, contentStart);
      if (idx != -1 && idx < end) end = idx;
    }
    return markdown.substring(contentStart, end).trim();
  }
}

// ============================================================
// BLoC
// ============================================================

sealed class IntentSyncState {
  final String documentContent;
  final String? lastApprovedContent;
  const IntentSyncState({required this.documentContent, this.lastApprovedContent});
}

class Aligned extends IntentSyncState {
  const Aligned({required super.documentContent}) : super(lastApprovedContent: documentContent);
}

class AiDrift extends IntentSyncState {
  const AiDrift({required super.documentContent, required super.lastApprovedContent});
}

class HumanOverride extends IntentSyncState {
  const HumanOverride({required super.documentContent, required super.lastApprovedContent});
}

sealed class IntentSyncEvent {
  const IntentSyncEvent();
}

class AiEditFile extends IntentSyncEvent {
  final String newContent;
  const AiEditFile(this.newContent);
}

class HumanEditSave extends IntentSyncEvent {
  final String newContent;
  const HumanEditSave(this.newContent);
}

class HumanReviewConfirm extends IntentSyncEvent {
  const HumanReviewConfirm();
}

class SyncComplete extends IntentSyncEvent {
  const SyncComplete();
}

class UserSendMessage extends IntentSyncEvent {
  final String? editedContent;
  const UserSendMessage({this.editedContent});
}

// ============================================================
// Services
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

  Future<bool> appendPrompt(String text) async {
    try {
      final res = await _client.post(Uri.parse('$_baseUrl/tui/append-prompt'),
          headers: _headers, body: jsonEncode({'text': text}));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> submitPrompt() async {
    try {
      final res = await _client.post(Uri.parse('$_baseUrl/tui/submit-prompt'), headers: _headers);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> showToast({required String message, String? title, String variant = 'info'}) async {
    try {
      final body = <String, dynamic>{'message': message, 'variant': variant};
      if (title != null) body['title'] = title;
      final res =
          await _client.post(Uri.parse('$_baseUrl/tui/show-toast'), headers: _headers, body: jsonEncode(body));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> executeCommand(String command) async {
    try {
      final res = await _client.post(Uri.parse('$_baseUrl/tui/execute-command'),
          headers: _headers, body: jsonEncode({'command': command}));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> clearPrompt() async {
    try {
      final res = await _client.post(Uri.parse('$_baseUrl/tui/clear-prompt'), headers: _headers);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
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
goal: 更新后的目标
exploration: 更新后的探索方向
constraints: 更新后的约束
state: 更新后的状态
[/INTENT_UPDATE]

只包含实际发生变化的字段，未变化字段省略。变化很细微时不要触发更新。''';
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
// BLoC Implementation
// ============================================================

class IntentSyncBloc extends Bloc<IntentSyncEvent, IntentSyncState> {
  final OpenCodeService _oc;
  final IntentFileService _file;
  Completer<void>? _syncCompleter;
  bool _isSyncing = false;

  IntentSyncBloc({
    required String initialDocumentContent,
    required IntentFileService fileService,
    OpenCodeService? openCodeService,
  })  : _oc = openCodeService ?? OpenCodeService(),
        _file = fileService,
        super(Aligned(documentContent: initialDocumentContent)) {
    on<AiEditFile>(_onAiEditFile);
    on<HumanEditSave>(_onHumanEditSave);
    on<HumanReviewConfirm>(_onHumanReviewConfirm);
    on<SyncComplete>(_onSyncComplete);
    on<UserSendMessage>(_onUserSendMessage);
  }

  void _onAiEditFile(AiEditFile event, Emitter<IntentSyncState> emit) {
    final newContent = event.newContent;
    _file.writeContent(newContent);
    switch (state) {
      case Aligned():
        emit(AiDrift(documentContent: newContent, lastApprovedContent: state.documentContent));
      case AiDrift():
        emit(AiDrift(documentContent: newContent, lastApprovedContent: state.lastApprovedContent));
      case HumanOverride():
        emit(HumanOverride(documentContent: newContent, lastApprovedContent: state.lastApprovedContent));
    }
  }

  void _onHumanEditSave(HumanEditSave event, Emitter<IntentSyncState> emit) {
    final previousApproved = switch (state) {
      Aligned() => state.documentContent,
      AiDrift(:final lastApprovedContent) => lastApprovedContent,
      HumanOverride(:final lastApprovedContent) => lastApprovedContent,
    };
    emit(HumanOverride(documentContent: event.newContent, lastApprovedContent: previousApproved));
    _file.writeContent(event.newContent);
    _startImplicitSync(event.newContent);
  }

  void _onHumanReviewConfirm(HumanReviewConfirm event, Emitter<IntentSyncState> emit) {
    if (state is AiDrift) emit(Aligned(documentContent: state.documentContent));
  }

  void _onSyncComplete(SyncComplete event, Emitter<IntentSyncState> emit) {
    if (state is HumanOverride) {
      emit(Aligned(documentContent: state.documentContent));
      _isSyncing = false;
      _syncCompleter?.complete();
      _syncCompleter = null;
    }
  }

  Future<void> _onUserSendMessage(UserSendMessage event, Emitter<IntentSyncState> emit) async {
    if (event.editedContent != null) {
      add(HumanEditSave(event.editedContent!));
      await _waitForSync();
      return;
    }
    if (state is AiDrift) {
      add(const HumanReviewConfirm());
      return;
    }
    if (state is HumanOverride) {
      await _waitForSync();
      return;
    }
  }

  void _startImplicitSync(String content) {
    if (_isSyncing) return;
    _isSyncing = true;
    _sendToAi(content).then((_) => add(const SyncComplete())).catchError((error) {
      _isSyncing = false;
      _syncCompleter?.completeError(error);
      _syncCompleter = null;
    });
  }

  String _buildSyncMessage(String content) {
    return '[SYSTEM] 意图文档已被用户手动更新，当前内容如下：\n---\n$content\n---\n请基于此意图文档继续对话。';
  }

  Future<void> _sendToAi(String content) async {
    final message = _buildSyncMessage(content);
    final appended = await _oc.appendPrompt(message);
    if (!appended) {
      _oc.showToast(message: '隐式同步失败，将在下一轮消息中附加意图文档', variant: 'warning');
      throw Exception('appendPrompt failed');
    }
    final submitted = await _oc.submitPrompt();
    if (!submitted) throw Exception('submitPrompt failed');
  }

  Future<void> _waitForSync() async {
    if (_syncCompleter != null) return;
    _syncCompleter = Completer<void>();
    try {
      await _syncCompleter!.future.timeout(const Duration(seconds: 5), onTimeout: () {
        _isSyncing = false;
        _syncCompleter = null;
      });
    } catch (_) {}
  }
}

// ============================================================
// Widgets
// ============================================================

class _ChatMessage {
  final String role;
  final String content;
  const _ChatMessage({required this.role, required this.content});
}

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key});
  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _messages = <_ChatMessage>[];
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String? _sessionId;
  bool _sending = false;

  static const _userBubble = Color(0xFFE3F2FD);
  static const _aiBubble = Color(0xFFF5F5F5);
  static const _primary = Color(0xFF1A1A2E);

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initSession() async {
    final oc = context.read<OpenCodeService>();
    final id = await oc.createSession(title: 'think-agent');
    if (id != null && mounted) setState(() => _sessionId = id);
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sessionId == null || _sending) return;
    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _sending = true;
    });
    _scrollToBottom();
    context.read<IntentSyncBloc>().add(const UserSendMessage());
    final oc = context.read<OpenCodeService>();
    final state = context.read<IntentSyncBloc>().state;
    final reply = await oc.sendMessage(_sessionId!, text, includeIntent: true, intentDoc: state.documentContent);
    if (mounted) {
      setState(() {
        if (reply != null) {
          final cleaned = _parseAndApplyIntentUpdate(reply);
          _messages.add(_ChatMessage(role: 'assistant', content: cleaned));
        } else {
          _messages.add(const _ChatMessage(role: 'assistant', content: '(未连接到 OpenCode serve，请确认服务已启动)'));
        }
        _sending = false;
      });
      _scrollToBottom();
    }
  }

  String _parseAndApplyIntentUpdate(String reply) {
    final updatePattern = RegExp(r'\[INTENT_UPDATE\](.*?)\[/INTENT_UPDATE\]', dotAll: true);
    final match = updatePattern.firstMatch(reply);
    if (match == null) return reply;
    final updateContent = match.group(1)?.trim() ?? '';
    final cleaned = reply.replaceAll(match.group(0)!, '').trim();
    final intentModel = IntentModel.fromMarkdown(context.read<IntentSyncBloc>().state.documentContent);
    var model = intentModel;
    for (final line in updateContent.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('goal:')) {
        model = model.copyWith(goal: trimmed.substring(5).trim());
      } else if (trimmed.startsWith('exploration:')) {
        model = model.copyWith(exploration: trimmed.substring(12).trim());
      } else if (trimmed.startsWith('constraints:')) {
        model = model.copyWith(constraints: trimmed.substring(12).trim());
      } else if (trimmed.startsWith('state:')) {
        model = model.copyWith(state: trimmed.substring(6).trim());
      }
    }
    context.read<IntentSyncBloc>().add(AiEditFile(model.toMarkdown()));
    return cleaned;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_sessionId == null)
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
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
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
        if (_sending)
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
                  onPressed: _sending ? null : _sendMessage,
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
  }
}

class IntentPanel extends StatefulWidget {
  final IntentModel intentModel;
  final ValueChanged<IntentModel> onChanged;
  const IntentPanel({super.key, required this.intentModel, required this.onChanged});

  @override
  State<IntentPanel> createState() => _IntentPanelState();
}

class _IntentPanelState extends State<IntentPanel> {
  late IntentModel _model;
  late Map<String, TextEditingController> _controllers;

  static const _darkCard = Color(0xFF16213E);
  static const _darkText = Color(0xFFE8E8E8);
  static const _darkLabel = Color(0xFF8E8E9A);
  static const _accent = Color(0xFF4FC3F7);

  @override
  void initState() {
    super.initState();
    _model = widget.intentModel;
    _initControllers();
  }

  @override
  void didUpdateWidget(IntentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intentModel != widget.intentModel) {
      _model = widget.intentModel;
      _disposeControllers();
      _initControllers();
    }
  }

  void _initControllers() {
    _controllers = {
      'goal': TextEditingController(text: _model.goal),
      'exploration': TextEditingController(text: _model.exploration),
      'constraints': TextEditingController(text: _model.constraints),
      'state': TextEditingController(text: _model.state),
    };
  }

  void _disposeControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _onFieldChanged(String field) {
    final updated = _model.copyWith(
      goal: _controllers['goal']!.text,
      exploration: _controllers['exploration']!.text,
      constraints: _controllers['constraints']!.text,
      state: _controllers['state']!.text,
    );
    setState(() => _model = updated);
    widget.onChanged(updated);
  }

  void _exportBrd() {
    final brd = _model.toMarkdown();
    Clipboard.setData(ClipboardData(text: brd));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('BRD 已复制到剪贴板'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: _darkCard,
    ));
  }

  Widget _buildField(String label, IconData icon, String key, {int maxLines = 4}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(children: [
              Icon(icon, size: 13, color: _accent),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _darkLabel, letterSpacing: 0.5)),
            ]),
          ),
          Container(
            decoration: BoxDecoration(color: _darkCard, borderRadius: BorderRadius.circular(8)),
            child: TextField(
              controller: _controllers[key]!,
              maxLines: maxLines,
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
                hintText: label,
                hintStyle: TextStyle(color: _darkLabel.withAlpha(100)),
              ),
              style: const TextStyle(fontSize: 13, color: _darkText, height: 1.5),
              onChanged: (_) => _onFieldChanged(key),
            ),
          ),
        ],
      ),
    );
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
            const Text('意图模型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _darkText, letterSpacing: 0.3)),
            const Spacer(),
            Text(_formatTime(_model.updatedAt), style: TextStyle(fontSize: 11, color: _darkLabel)),
          ]),
        ),
        const SizedBox(height: 4),
        Divider(color: _darkLabel.withAlpha(40), height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              _buildField('目标', Icons.flag_outlined, 'goal'),
              _buildField('当前探索', Icons.explore_outlined, 'exploration', maxLines: 6),
              _buildField('约束', Icons.border_style, 'constraints', maxLines: 4),
              _buildField('状态', Icons.circle_outlined, 'state'),
            ],
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

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    return '${diff.inHours}小时前';
  }
}

// ============================================================
// Screen
// ============================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  IntentModel _intentModel = IntentModel();

  @override
  void initState() {
    super.initState();
    final fileService = context.read<IntentFileService>();
    fileService.onFileChanged = (content) => context.read<IntentSyncBloc>().add(AiEditFile(content));
    fileService.init();
  }

  void _onIntentChanged(IntentModel model) {
    context.read<IntentSyncBloc>().add(HumanEditSave(model.toMarkdown()));
  }

  @override
  void dispose() {
    context.read<IntentFileService>().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;
    return BlocBuilder<IntentSyncBloc, IntentSyncState>(
      builder: (context, state) {
        _intentModel = IntentModel.fromMarkdown(state.documentContent);
        if (isWide) {
          return Row(children: [
            const Expanded(flex: 3, child: ChatPanel()),
            Container(width: 1, color: Colors.black.withAlpha(26)),
            Expanded(
              flex: 2,
              child: Container(
                color: const Color(0xFF1A1A2E),
                child: IntentPanel(intentModel: _intentModel, onChanged: _onIntentChanged),
              ),
            ),
          ]);
        }
        return Column(children: [
          ExpansionTile(
            title: const Text('当前意图'),
            initiallyExpanded: false,
            children: [
              SizedBox(height: 250, child: IntentPanel(intentModel: _intentModel, onChanged: _onIntentChanged))
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
// App
// ============================================================

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
        BlocProvider(create: (_) => IntentSyncBloc(
          initialDocumentContent: _defaultIntentDoc,
          fileService: fileService,
          openCodeService: ocService,
        )),
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

const _defaultIntentDoc = '''# 意图文档
生成时间：

## 目标

## 当前探索

## 约束

## 状态
''';
