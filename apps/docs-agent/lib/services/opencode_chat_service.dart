import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ai_chat_service.dart';

class OpenCodeChatService implements AiChatService {
  final String host;
  final int port;
  final String? password;
  final String? username;
  http.Client client;

  OpenCodeChatService({
    this.host = '127.0.0.1',
    this.port = 4096,
    this.password,
    this.username,
    http.Client? client,
  }) : client = client ?? http.Client();

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

  @override
  Future<String?> createSession({String? title}) async {
    try {
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      final res = await client.post(
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

  @override
  Future<String?> sendMessage(
    String sessionId,
    String message, {
    String? systemPrompt,
  }) async {
    try {
      final parts = [
        {'type': 'text', 'text': message},
      ];
      final body = <String, dynamic>{
        'parts': parts,
      };
      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        body['system'] = '你是一个文档协作工具。当前文档内容：\n\n$systemPrompt\n\n'
            '你的每次回复就是更新后的完整文档。回复的内容会直接写入文档文件。';
      }
      final res = await client.post(
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

  @override
  Future<bool> clearSession(String sessionId) async {
    try {
      final res = await client.delete(
        Uri.parse('$_baseUrl/session/$sessionId'),
        headers: _headers,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    client.close();
  }
}
