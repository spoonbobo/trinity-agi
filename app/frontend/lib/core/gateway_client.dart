import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'auth.dart';
import 'protocol.dart';
import '../models/ws_frame.dart';

enum ConnectionState { disconnected, connecting, connected, error }

class GatewayClient extends ChangeNotifier {
  final String url;
  final GatewayAuth auth;
  String? openclawId;

  /// Update the auth token (e.g. when the JWT is refreshed).
  void updateToken(String newToken) {
    auth.updateToken(newToken);
  }

  /// Set the active OpenClaw instance ID for shared-pod routing.
  void setOpenClawId(String? id) {
    openclawId = id;
  }

  WebSocketChannel? _channel;
  ConnectionState _state = ConnectionState.disconnected;
  final _uuid = const Uuid();

  final _responseCompleters = <String, Completer<WsResponse>>{};

  final StreamController<WsEvent> _eventController =
      StreamController<WsEvent>.broadcast();

  ConnectionState get state => _state;
  Stream<WsEvent> get events => _eventController.stream;

  /// Filtered stream for chat events only.
  Stream<WsEvent> get chatEvents =>
      events.where((e) => e.event == 'chat' || e.event == 'agent');

  /// Filtered stream for approval events.
  Stream<WsEvent> get approvalEvents =>
      events.where((e) => e.event == 'exec.approval.requested');

  GatewayClient({required this.url, required this.auth});

  Future<void> connect() async {
    if (_state == ConnectionState.connected ||
        _state == ConnectionState.connecting) return;

    _shouldReconnect = true;
    _state = ConnectionState.connecting;
    notifyListeners();

    try {
      // Append JWT as query parameter for the gateway-proxy to authenticate
      // the upgrade request. Browsers cannot send custom headers during WS.
      final wsUri = Uri.parse(url);
      final authedUri = auth.token != null
          ? wsUri.replace(queryParameters: {
              ...wsUri.queryParameters,
              'token': auth.token!,
              if (openclawId != null) 'openclaw': openclawId!,
            })
          : wsUri;
      _channel = WebSocketChannel.connect(authedUri);
      await _channel!.ready;
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      _state = ConnectionState.error;
      notifyListeners();
      rethrow;
    }
  }

  bool _disposed = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _shouldReconnect = true;

  /// Only forward events the shell knows how to handle.
  static const _handledEvents = {
    'chat', 'agent', 'a2ui', 'canvas', 'browser',
    'exec.approval.requested', 'tick',
  };
  bool _isHandledEvent(String name) =>
      _handledEvents.contains(name) ||
      name.startsWith('canvas.') ||
      name.startsWith('browser.');

  void _onMessage(dynamic raw) {
    try {
      if (raw is! String) return; // Ignore binary frames
      final rawStr = raw;
      final frame = WsFrame.parse(rawStr);

      switch (frame.type) {
        case FrameType.event:
          final event = frame.event!;
          if (event.event == 'connect.challenge') {
            _handleChallenge(event);
          } else if (_isHandledEvent(event.event)) {
            if (!_disposed) _eventController.add(event);
          }
          break;
        case FrameType.res:
          final response = frame.response!;
          final completer = _responseCompleters.remove(response.id);
          if (completer != null) {
            completer.complete(response);
          }
          if (response.ok &&
              response.payload?['type'] == 'hello-ok') {
            _state = ConnectionState.connected;
            _reconnectAttempts = 0; // Reset on successful connect
            _reconnectTimer?.cancel();
            notifyListeners();
          }
          break;
        case FrameType.req:
          break;
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[GW] error processing message: $e\n$st');
    }
  }

  void _handleChallenge(WsEvent event) {
    final nonce = event.payload['nonce'] as String?;
    _sendConnect(nonce);
  }

  void _sendConnect(String? nonce) {
    final params = <String, dynamic>{
      'minProtocol': 3,
      'maxProtocol': 3,
      'client': {
        'id': 'openclaw-control-ui',
        'version': 'dev',
        'platform': 'web',
        'mode': 'webchat',
      },
      'role': 'operator',
      'scopes': ['operator.read', 'operator.write', 'operator.approvals'],
      'caps': ['tool-events'],
      'commands': [],
      'permissions': {},
      'locale': 'en-US',
      'userAgent': 'trinity-shell/0.1.0',
      ...auth.toConnectParams(nonce),
    };

    sendRequest(GatewayMethods.connect, params);
  }

  /// Send a typed request and return a future that resolves with the response.
  /// Times out after 30 seconds to prevent silent hangs.
  Future<WsResponse> sendRequest(
    String method,
    Map<String, dynamic> params,
  ) {
    final id = _uuid.v4();
    final request = WsRequest(id: id, method: method, params: params);
    final completer = Completer<WsResponse>();
    _responseCompleters[id] = completer;
    _channel?.sink.add(request.encode());
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _responseCompleters.remove(id);
        return WsResponse(id: id, ok: false, payload: {
          'error': 'Request timed out after 30s',
          'method': method,
        });
      },
    );
  }

  /// Send a chat message to the agent.
  Future<WsResponse> sendChatMessage(String message,
      {String sessionKey = 'main'}) {
    final idempotencyKey = _uuid.v4();
    if (!_disposed) {
      _eventController.add(WsEvent(
        event: 'chat',
        payload: {
          'type': 'message',
          'role': 'user',
          'content': message,
          'localEcho': true,
          'idempotencyKey': idempotencyKey,
        },
      ));
    }
    return sendRequest(GatewayMethods.chatSend, {
      'message': message,
      'sessionKey': sessionKey,
      'idempotencyKey': idempotencyKey,
    });
  }

  /// Fetch chat history.
  Future<WsResponse> getChatHistory({
    String sessionKey = 'main',
    int limit = 50,
  }) {
    return sendRequest(GatewayMethods.chatHistory, {
      'sessionKey': sessionKey,
      'limit': limit,
    });
  }

  /// Abort an in-progress agent run.
  Future<WsResponse> abortChat({String sessionKey = 'main'}) {
    return sendRequest(GatewayMethods.chatAbort, {
      'sessionKey': sessionKey,
    });
  }

  /// Resolve an exec approval request.
  Future<WsResponse> resolveApproval(String requestId, bool approve) {
    return sendRequest(GatewayMethods.execApprovalResolve, {
      'requestId': requestId,
      'approved': approve,
    });
  }

  void emitCanvasEvent(WsEvent event) {
    if (!_disposed) _eventController.add(event);
  }

  /// List all sessions from the gateway.
  Future<WsResponse> listSessions() {
    return sendRequest(GatewayMethods.sessionsList, {});
  }

  /// Delete a session from the gateway.
  Future<WsResponse> deleteSession(String key) {
    return sendRequest(GatewayMethods.sessionsDelete, {'key': key});
  }

  /// Send a chat message with optional file attachments.
  ///
  /// Attachments use OpenClaw's protocol field names:
  ///   content  – base64 data
  ///   mimeType – MIME string
  ///   fileName – display name (optional)
  ///   type     – "image" for images (optional)
  Future<WsResponse> sendChatMessageWithAttachments(
    String message, {
    String sessionKey = 'main',
    List<Map<String, dynamic>>? attachments,
  }) {
    final idempotencyKey = _uuid.v4();
    if (!_disposed) {
      _eventController.add(WsEvent(
        event: 'chat',
        payload: {
          'type': 'message',
          'role': 'user',
          'content': message,
          'localEcho': true,
          'idempotencyKey': idempotencyKey,
          if (attachments != null) 'attachments': attachments,
        },
      ));
    }
    return sendRequest(GatewayMethods.chatSend, {
      'message': message,
      'sessionKey': sessionKey,
      'idempotencyKey': idempotencyKey,
      if (attachments != null) 'attachments': attachments,
    });
  }

  void _onError(dynamic error) {
    _state = ConnectionState.error;
    notifyListeners();
  }

  void _onDone() {
    _state = ConnectionState.disconnected;
    _failPendingCompleters('Connection closed');
    notifyListeners();
    if (_shouldReconnect) {
      // #3: Auto-reconnect with exponential backoff
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectAttempts++;
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s max
    final delay = Duration(
        seconds: (_reconnectAttempts <= 5)
            ? (1 << (_reconnectAttempts - 1))
            : 30);
    if (kDebugMode) debugPrint('[GW] reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_disposed &&
          _state != ConnectionState.connected &&
          _state != ConnectionState.connecting) {
        connect().catchError((_) {});
      }
    });
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _channel?.sink.close();
    _state = ConnectionState.disconnected;
    _failPendingCompleters('Client disconnected');
    notifyListeners();
  }

  /// Complete all pending request completers with an error response
  /// so callers are not left hanging indefinitely.
  void _failPendingCompleters(String reason) {
    for (final entry in _responseCompleters.entries) {
      if (!entry.value.isCompleted) {
        entry.value.complete(WsResponse(
          id: entry.key,
          ok: false,
          payload: {'error': reason},
        ));
      }
    }
    _responseCompleters.clear();
  }

  // ---------------------------------------------------------------------------
  // Browser control HTTP API
  // ---------------------------------------------------------------------------
  // The gateway exposes a loopback browser control API.
  // In the Trinity Docker stack, nginx proxies /__openclaw__/ to the gateway.
  // We use the page origin for same-origin requests (goes through nginx),
  // falling back to deriving from the WebSocket URL for direct connections.

  /// Base URL for browser control HTTP API calls.
  String get browserBaseUrl => _browserBaseUrl;
  String get _browserBaseUrl {
    // Prefer same-origin (works through nginx proxy)
    final origin = html.window.location.origin;
    if (origin.isNotEmpty && origin != 'null') return origin;
    // Fallback: derive from WS URL
    final wsUri = Uri.parse(url);
    final scheme = wsUri.scheme == 'wss' ? 'https' : 'http';
    return '$scheme://${wsUri.host}${wsUri.hasPort ? ':${wsUri.port}' : ''}';
  }

  /// Auth headers for browser control API calls.
  Map<String, String> get browserHeaders => _browserHeaders;
  Map<String, String> get _browserHeaders => {
    'Authorization': 'Bearer ${auth.token}',
    'Content-Type': 'application/json',
    if (openclawId != null) 'X-OpenClaw-Id': openclawId!,
  };

  Future<Map<String, dynamic>> browserApiGet(String path, {String profile = 'openclaw'}) async {
    final separator = path.contains('?') ? '&' : '?';
    final fullUrl = '$_browserBaseUrl/__openclaw__/browser$path${separator}profile=$profile';
    final response = await html.HttpRequest.request(
      fullUrl,
      method: 'GET',
      requestHeaders: _browserHeaders,
    );
    if (response.status == 200 || response.status == 201) {
      return jsonDecode(response.responseText ?? '{}') as Map<String, dynamic>;
    }
    throw Exception('Browser API GET $path failed: ${response.status} ${response.responseText}');
  }

  Future<Map<String, dynamic>> browserApiPost(String path, {
    Map<String, dynamic>? body,
    String profile = 'openclaw',
  }) async {
    final separator = path.contains('?') ? '&' : '?';
    final fullUrl = '$_browserBaseUrl/__openclaw__/browser$path${separator}profile=$profile';
    final response = await html.HttpRequest.request(
      fullUrl,
      method: 'POST',
      requestHeaders: _browserHeaders,
      sendData: body != null ? jsonEncode(body) : null,
    );
    if (response.status == 200 || response.status == 201) {
      final text = response.responseText ?? '{}';
      if (text.isEmpty) return {};
      try {
        return jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        return {'raw': text};
      }
    }
    throw Exception('Browser API POST $path failed: ${response.status} ${response.responseText}');
  }

  Future<Map<String, dynamic>> browserApiDelete(String path, {String profile = 'openclaw'}) async {
    final separator = path.contains('?') ? '&' : '?';
    final fullUrl = '$_browserBaseUrl/__openclaw__/browser$path${separator}profile=$profile';
    final response = await html.HttpRequest.request(
      fullUrl,
      method: 'DELETE',
      requestHeaders: _browserHeaders,
    );
    if (response.status == 200 || response.status == 201) {
      final text = response.responseText ?? '{}';
      if (text.isEmpty) return {};
      try {
        return jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        return {'raw': text};
      }
    }
    throw Exception('Browser API DELETE $path failed: ${response.status} ${response.responseText}');
  }

  /// Get browser status.
  Future<Map<String, dynamic>> browserStatus({String profile = 'openclaw'}) =>
      browserApiGet('/', profile: profile);

  /// Start the managed browser.
  Future<Map<String, dynamic>> browserStart({String profile = 'openclaw'}) =>
      browserApiPost('/start', profile: profile);

  /// Stop the managed browser.
  Future<Map<String, dynamic>> browserStop({String profile = 'openclaw'}) =>
      browserApiPost('/stop', profile: profile);

  /// List open tabs.
  Future<Map<String, dynamic>> browserTabs({String profile = 'openclaw'}) =>
      browserApiGet('/tabs', profile: profile);

  /// Open a new tab with optional URL.
  Future<Map<String, dynamic>> browserTabOpen(String url, {String profile = 'openclaw'}) =>
      browserApiPost('/tabs/open', body: {'url': url}, profile: profile);

  /// Focus a specific tab by targetId.
  Future<Map<String, dynamic>> browserTabFocus(String targetId, {String profile = 'openclaw'}) =>
      browserApiPost('/tabs/focus', body: {'targetId': targetId}, profile: profile);

  /// Close a tab by targetId.
  Future<Map<String, dynamic>> browserTabClose(String targetId, {String profile = 'openclaw'}) =>
      browserApiDelete('/tabs/$targetId', profile: profile);

  /// Take a screenshot (returns base64 PNG in response).
  Future<Map<String, dynamic>> browserScreenshot({
    String profile = 'openclaw',
    bool fullPage = false,
  }) =>
      browserApiPost('/screenshot', body: {
        if (fullPage) 'fullPage': true,
      }, profile: profile);

  /// Get an interactive ARIA snapshot with refs.
  Future<Map<String, dynamic>> browserSnapshot({
    String profile = 'openclaw',
    bool interactive = true,
    bool compact = true,
  }) =>
      browserApiGet('/snapshot?interactive=$interactive&compact=$compact', profile: profile);

  /// Navigate to a URL.
  Future<Map<String, dynamic>> browserNavigate(String url, {String profile = 'openclaw'}) =>
      browserApiPost('/navigate', body: {'url': url}, profile: profile);

  /// Perform a browser action (click, type, press, hover, scroll, etc.).
  Future<Map<String, dynamic>> browserAct({
    required String kind,
    String? ref,
    String? text,
    bool? submit,
    String profile = 'openclaw',
  }) =>
      browserApiPost('/act', body: {
        'kind': kind,
        if (ref != null) 'ref': ref,
        if (text != null) 'text': text,
        if (submit != null) 'submit': submit,
      }, profile: profile);

  /// Resize the browser viewport.
  Future<Map<String, dynamic>> browserResize(int width, int height, {String profile = 'openclaw'}) =>
      browserApiPost('/act', body: {
        'kind': 'resize',
        'width': width,
        'height': height,
      }, profile: profile);

  @override
  void dispose() {
    _disposed = true;
    _shouldReconnect = false;
    disconnect();
    _eventController.close();
    super.dispose();
  }
}
