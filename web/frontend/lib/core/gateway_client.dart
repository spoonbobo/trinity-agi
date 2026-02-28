import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'auth.dart';
import '../models/ws_frame.dart';

enum ConnectionState { disconnected, connecting, connected, error }

class GatewayClient extends ChangeNotifier {
  final String url;
  final GatewayAuth auth;

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

    _state = ConnectionState.connecting;
    notifyListeners();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
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

  /// Only forward events the shell knows how to handle.
  static const _handledEvents = {
    'chat', 'agent', 'a2ui', 'canvas',
    'exec.approval.requested', 'tick',
  };
  bool _isHandledEvent(String name) =>
      _handledEvents.contains(name) || name.startsWith('canvas.');

  void _onMessage(dynamic raw) {
    try {
      final rawStr = raw as String;
      debugPrint('[GW] raw: ${rawStr.length > 300 ? rawStr.substring(0, 300) : rawStr}');
      final frame = WsFrame.parse(rawStr);

      switch (frame.type) {
        case FrameType.event:
          final event = frame.event!;
          debugPrint('[GW] event: ${event.event}');
          if (event.event == 'connect.challenge') {
            _handleChallenge(event);
          } else if (_isHandledEvent(event.event)) {
            if (!_disposed) _eventController.add(event);
          }
          break;
        case FrameType.res:
          final response = frame.response!;
          debugPrint('[GW] res: id=${response.id} ok=${response.ok}');
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
      debugPrint('[GW] error processing message: $e\n$st');
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
      'caps': [],
      'commands': [],
      'permissions': {},
      'locale': 'en-US',
      'userAgent': 'trinity-shell/0.1.0',
      ...auth.toConnectParams(nonce),
    };

    sendRequest('connect', params);
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
    if (!_disposed) {
      _eventController.add(WsEvent(
        event: 'chat',
        payload: {'type': 'message', 'role': 'user', 'content': message},
      ));
    }
    return sendRequest('chat.send', {
      'message': message,
      'sessionKey': sessionKey,
      'idempotencyKey': _uuid.v4(),
    });
  }

  /// Fetch chat history.
  Future<WsResponse> getChatHistory({
    String sessionKey = 'main',
    int limit = 50,
  }) {
    return sendRequest('chat.history', {
      'sessionKey': sessionKey,
      'limit': limit,
    });
  }

  /// Abort an in-progress agent run.
  Future<WsResponse> abortChat({String sessionKey = 'main'}) {
    return sendRequest('chat.abort', {
      'sessionKey': sessionKey,
    });
  }

  /// Resolve an exec approval request.
  Future<WsResponse> resolveApproval(String requestId, bool approve) {
    return sendRequest('exec.approval.resolve', {
      'requestId': requestId,
      'approved': approve,
    });
  }

  void emitCanvasEvent(WsEvent event) {
    if (!_disposed) _eventController.add(event);
  }

  void _onError(dynamic error) {
    _state = ConnectionState.error;
    notifyListeners();
  }

  void _onDone() {
    _state = ConnectionState.disconnected;
    _failPendingCompleters('Connection closed');
    notifyListeners();
    // #3: Auto-reconnect with exponential backoff
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectAttempts++;
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s max
    final delay = Duration(
        seconds: (_reconnectAttempts <= 5)
            ? (1 << (_reconnectAttempts - 1))
            : 30);
    debugPrint('[GW] reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_disposed &&
          _state != ConnectionState.connected &&
          _state != ConnectionState.connecting) {
        connect().catchError((e) {
          debugPrint('[GW] reconnect failed: $e');
        });
      }
    });
  }

  void disconnect() {
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

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    _eventController.close();
    super.dispose();
  }
}
