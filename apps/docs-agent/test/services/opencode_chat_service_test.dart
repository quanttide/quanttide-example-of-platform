import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:docs_agent/services/opencode_chat_service.dart';

http.Client _mockClient(int statusCode, dynamic body) {
  return MockClient((request) async {
    return http.Response(
      body is String ? body : jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  });
}

void main() {
  group('createSession', () {
    test('returns session id on success', () async {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: _mockClient(200, {'id': 'sess-123'}),
      );
      final id = await service.createSession(title: 'test');
      expect(id, 'sess-123');
    });

    test('sends title when provided', () async {
      String? sentBody;
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: MockClient((request) async {
          sentBody = request.body;
          return http.Response(jsonEncode({'id': 'sess-1'}), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      await service.createSession(title: 'my-title');
      expect(sentBody, isNotNull);
      final body = jsonDecode(sentBody!) as Map<String, dynamic>;
      expect(body['title'], 'my-title');
    });

    test('returns null on non-200', () async {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: _mockClient(500, {}),
      );
      final id = await service.createSession();
      expect(id, isNull);
    });

    test('returns null on exception', () async {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: MockClient((_) => throw Exception('fail')),
      );
      final id = await service.createSession();
      expect(id, isNull);
    });
  });

  group('sendMessage', () {
    test('returns text parts on success', () async {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: _mockClient(200, {
          'parts': [
            {'type': 'text', 'text': 'Hello AI'},
          ],
        }),
      );
      final reply = await service.sendMessage('sess-1', 'Hi',
          systemPrompt: '# doc');
      expect(reply, 'Hello AI');
    });

    test('handles multiple text parts', () async {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: _mockClient(200, {
          'parts': [
            {'type': 'text', 'text': 'Part 1'},
            {'type': 'text', 'text': 'Part 2'},
          ],
        }),
      );
      final reply = await service.sendMessage('sess-1', 'Hi');
      expect(reply, 'Part 1\nPart 2');
    });

    test('handles empty parts', () async {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: _mockClient(200, {'parts': []}),
      );
      final reply = await service.sendMessage('sess-1', 'Hi');
      expect(reply, isNull);
    });

    test('handles null parts list', () async {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: _mockClient(200, {}),
      );
      final reply = await service.sendMessage('sess-1', 'Hi');
      expect(reply, isNull);
    });

    test('returns null on non-200', () async {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: _mockClient(500, {}),
      );
      final reply = await service.sendMessage('sess-1', 'Hi');
      expect(reply, isNull);
    });

    test('returns null on exception', () async {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: MockClient((_) => throw Exception('fail')),
      );
      final reply = await service.sendMessage('sess-1', 'Hi');
      expect(reply, isNull);
    });

    test('includes system prompt in body', () async {
      String? sentBody;
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: MockClient((request) async {
          sentBody = request.body;
          return http.Response(jsonEncode({'parts': []}), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      await service.sendMessage('sess-1', 'Hi', systemPrompt: '# doc');
      final body = jsonDecode(sentBody!) as Map<String, dynamic>;
      expect(body['system'], contains('# doc'));
    });

    test('omits system prompt when empty', () async {
      String? sentBody;
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: MockClient((request) async {
          sentBody = request.body;
          return http.Response(jsonEncode({'parts': []}), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      await service.sendMessage('sess-1', 'Hi', systemPrompt: '');
      final body = jsonDecode(sentBody!) as Map<String, dynamic>;
      expect(body.containsKey('system'), false);
    });
  });

  group('clearSession', () {
    test('returns true on success', () async {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: _mockClient(200, {}),
      );
      final ok = await service.clearSession('sess-1');
      expect(ok, true);
    });

    test('returns false on failure', () async {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: _mockClient(500, {}),
      );
      final ok = await service.clearSession('sess-1');
      expect(ok, false);
    });

    test('returns false on exception', () async {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: MockClient((_) => throw Exception('fail')),
      );
      final ok = await service.clearSession('sess-1');
      expect(ok, false);
    });
  });

  group('authentication', () {
    test('includes auth header when password is set', () async {
      final captured = <String, String>{};
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        password: 'secret',
        username: 'admin',
        client: MockClient((request) async {
          captured.addAll(request.headers);
          return http.Response(jsonEncode({'id': 'sess-1'}), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      await service.createSession();
      expect(captured.containsKey('Authorization'), true);
      expect(captured['Authorization'], startsWith('Basic '));
    });

    test('defaults username to opencode', () async {
      final captured = <String, String>{};
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        password: 'secret',
        client: MockClient((request) async {
          captured.addAll(request.headers);
          return http.Response(jsonEncode({'id': 'sess-1'}), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      await service.createSession();
      final auth = captured['Authorization'];
      expect(auth, isNotNull);
      final cred = base64Decode(auth!.substring(6));
      expect(utf8.decode(cred), startsWith('opencode:'));
    });

    test('omits auth header without password', () async {
      final captured = <String, String>{};
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: MockClient((request) async {
          captured.addAll(request.headers);
          return http.Response(jsonEncode({'id': 'sess-1'}), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      await service.createSession();
      expect(captured.containsKey('Authorization'), false);
    });
  });

  group('dispose', () {
    test('closes client', () {
      final service = OpenCodeChatService(
        host: 'localhost',
        port: 4096,
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      service.dispose();
    });
  });
}
