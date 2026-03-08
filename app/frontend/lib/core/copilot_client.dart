import 'dart:convert';
import 'dart:html' as html;

class CopilotMessage {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;

  const CopilotMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory CopilotMessage.fromJson(Map<String, dynamic> json) {
    return CopilotMessage(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class CopilotMessagesResponse {
  final String sessionId;
  final List<CopilotMessage> messages;

  const CopilotMessagesResponse({
    required this.sessionId,
    required this.messages,
  });

  factory CopilotMessagesResponse.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List? ?? const [];
    return CopilotMessagesResponse(
      sessionId: json['sessionId']?.toString() ?? '',
      messages: rawMessages
          .map((item) =>
              CopilotMessage.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}

class CopilotClient {
  String get _baseUrl => html.window.location.origin;

  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    String token, {
    String? openclawId,
    Map<String, dynamic>? body,
  }) async {
    final request = html.HttpRequest();
    request.open(method, '$_baseUrl$path');
    request.setRequestHeader('Authorization', 'Bearer $token');
    request.setRequestHeader('Content-Type', 'application/json');
    if (openclawId != null && openclawId.isNotEmpty) {
      request.setRequestHeader('X-OpenClaw-Id', openclawId);
    }

    final completer = Future<String>.delayed(Duration.zero, () async {
      await request.onLoadEnd.first;
      if (request.status != null &&
          request.status! >= 200 &&
          request.status! < 300) {
        return request.responseText ?? '{}';
      }
      throw Exception('HTTP ${request.status}: ${request.responseText}');
    });

    request.send(body == null ? null : jsonEncode(body));
    final responseText = await completer;
    if (responseText.trim().isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(responseText) as Map);
  }

  Future<CopilotMessagesResponse> fetchMessages(
    String token, {
    String? openclawId,
  }) async {
    final response = await _request(
      'GET',
      '/copilot/messages',
      token,
      openclawId: openclawId,
    );
    return CopilotMessagesResponse.fromJson(response);
  }

  Future<CopilotMessagesResponse> sendPrompt(
    String token,
    String message, {
    String? openclawId,
  }) async {
    final response = await _request(
      'POST',
      '/copilot/prompt',
      token,
      openclawId: openclawId,
      body: {'message': message},
    );
    return CopilotMessagesResponse.fromJson(response);
  }

  Future<CopilotMessagesResponse> resetSession(
    String token, {
    String? openclawId,
  }) async {
    final response = await _request(
      'POST',
      '/copilot/session/reset',
      token,
      openclawId: openclawId,
    );
    return CopilotMessagesResponse.fromJson(response);
  }
}
