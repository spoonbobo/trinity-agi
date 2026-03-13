import 'dart:convert';
import 'dart:html' as html;

import 'http_utils.dart';

class CopilotAction {
  final String type;
  final String label;
  final String? channelId;
  final String? focus;
  final String? filter;
  final String? command;
  final bool recommended;

  const CopilotAction({
    required this.type,
    required this.label,
    this.channelId,
    this.focus,
    this.filter,
    this.command,
    this.recommended = false,
  });

  factory CopilotAction.fromJson(Map<String, dynamic> json) {
    return CopilotAction(
      type: json['type']?.toString() ?? '',
      label: json['label']?.toString() ?? 'open',
      channelId: json['channelId']?.toString(),
      focus: json['focus']?.toString(),
      filter: json['filter']?.toString(),
      command: json['command']?.toString(),
      recommended: json['recommended'] == true,
    );
  }
}

class CopilotMessage {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final List<CopilotAction> actions;

  const CopilotMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.actions = const [],
  });

  factory CopilotMessage.fromJson(Map<String, dynamic> json) {
    final rawActions = json['actions'] as List? ?? const [];
    return CopilotMessage(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      actions: rawActions
          .map((item) =>
              CopilotAction.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
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

class CopilotModelsResponse {
  final String? current;
  final List<String> available;

  const CopilotModelsResponse({this.current, required this.available});

  factory CopilotModelsResponse.fromJson(Map<String, dynamic> json) {
    return CopilotModelsResponse(
      current: json['current']?.toString(),
      available: List<String>.from(json['available'] as List? ?? const []),
    );
  }
}

class CopilotStatus {
  final String workspace;
  final String desiredDefaultModel;
  final bool desiredDefaultAvailable;
  final String? actualModel;
  final Map<String, dynamic> defaults;
  final List<String> connectedProviders;
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? openclaw;

  const CopilotStatus({
    required this.workspace,
    required this.desiredDefaultModel,
    required this.desiredDefaultAvailable,
    this.actualModel,
    required this.defaults,
    required this.connectedProviders,
    this.user,
    this.openclaw,
  });

  factory CopilotStatus.fromJson(Map<String, dynamic> json) {
    return CopilotStatus(
      workspace: json['workspace']?.toString() ?? '',
      desiredDefaultModel: json['desiredDefaultModel']?.toString() ?? '',
      desiredDefaultAvailable: json['desiredDefaultAvailable'] == true,
      actualModel: json['actualModel']?.toString(),
      defaults: Map<String, dynamic>.from(json['defaults'] as Map? ?? const {}),
      connectedProviders: List<String>.from(json['connectedProviders'] as List? ?? const []),
      user: json['user'] is Map<String, dynamic>
          ? json['user'] as Map<String, dynamic>
          : (json['user'] is Map ? Map<String, dynamic>.from(json['user'] as Map) : null),
      openclaw: json['openclaw'] is Map<String, dynamic>
          ? json['openclaw'] as Map<String, dynamic>
          : (json['openclaw'] is Map ? Map<String, dynamic>.from(json['openclaw'] as Map) : null),
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

    final responseText = await safeXhr(request,
        body: body == null ? null : jsonEncode(body));
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

  Future<CopilotStatus> fetchStatus(
    String token, {
    String? openclawId,
  }) async {
    final response = await _request(
      'GET',
      '/copilot/status',
      token,
      openclawId: openclawId,
    );
    return CopilotStatus.fromJson(response);
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

  Future<CopilotModelsResponse> fetchModels(
    String token, {
    String? openclawId,
  }) async {
    final response = await _request(
      'GET',
      '/copilot/models',
      token,
      openclawId: openclawId,
    );
    return CopilotModelsResponse.fromJson(response);
  }

  Future<CopilotModelsResponse> setModel(
    String token,
    String model, {
    String? openclawId,
  }) async {
    final response = await _request(
      'POST',
      '/copilot/model',
      token,
      openclawId: openclawId,
      body: {'model': model},
    );
    return CopilotModelsResponse.fromJson(response);
  }
}
