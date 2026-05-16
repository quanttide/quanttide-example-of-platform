import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenCodeService {
  final String host;
  final int port;
  final String? password;
  final String? username;
  final http.Client _client = http.Client();

  OpenCodeService({
    this.host = '127.0.0.1',
    this.port = 4096,
    this.password,
    this.username,
  });

  String get _baseUrl => 'http://$host:$port';

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (password != null) {
      final cred = base64Encode(
        utf8.encode('${username ?? 'opencode'}:$password'),
      );
      headers['Authorization'] = 'Basic $cred';
    }
    return headers;
  }

  Future<bool> appendPrompt(String text) async {
    try {
      final res = await _client.post(
        Uri.parse('$_baseUrl/tui/append-prompt'),
        headers: _headers,
        body: jsonEncode({'text': text}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> submitPrompt() async {
    try {
      final res = await _client.post(
        Uri.parse('$_baseUrl/tui/submit-prompt'),
        headers: _headers,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> showToast({
    required String message,
    String? title,
    String variant = 'info',
  }) async {
    try {
      final body = <String, dynamic>{'message': message, 'variant': variant};
      if (title != null) body['title'] = title;
      final res = await _client.post(
        Uri.parse('$_baseUrl/tui/show-toast'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> executeCommand(String command) async {
    try {
      final res = await _client.post(
        Uri.parse('$_baseUrl/tui/execute-command'),
        headers: _headers,
        body: jsonEncode({'command': command}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> clearPrompt() async {
    try {
      final res = await _client.post(
        Uri.parse('$_baseUrl/tui/clear-prompt'),
        headers: _headers,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> health() async {
    try {
      final res = await _client.get(
        Uri.parse('$_baseUrl/global/health'),
        headers: _headers,
      );
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
      final res = await _client.post(
        Uri.parse('$_baseUrl/session'),
        headers: _headers,
        body: body.isEmpty ? null : jsonEncode(body),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['id'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> sendMessage(
    String sessionId,
    String text, {
    bool includeIntent = false,
    String? intentDoc,
  }) async {
    try {
      final parts = [
        {'type': 'text', 'text': text},
      ];
      final body = <String, dynamic>{
        'parts': parts,
      };
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
      final res = await _client.post(
        Uri.parse('$_baseUrl/session/$sessionId/message'),
        headers: _headers,
        body: jsonEncode(body),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final partsList = data['parts'] as List<dynamic>?;
        if (partsList != null && partsList.isNotEmpty) {
          final textParts = partsList
              .where((p) => p['type'] == 'text')
              .map((p) => p['text'] as String)
              .join('\n');
          return textParts;
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
