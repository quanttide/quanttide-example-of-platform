abstract class AiChatService {
  Future<String?> createSession({String? title});
  Future<String?> sendMessage(
    String sessionId,
    String message, {
    String? systemPrompt,
  });
  Future<bool> clearSession(String sessionId);
}
