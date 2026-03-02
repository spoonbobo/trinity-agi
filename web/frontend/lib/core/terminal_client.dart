import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/auth.dart';

enum TerminalConnectionState { disconnected, connecting, connected, error }

/// Result of syncing env vars to the gateway config.
class EnvSyncResult {
  final List<String> synced;
  final List<String> skipped;
  final List<String> errors;
  final String message;

  const EnvSyncResult({
    required this.synced,
    required this.skipped,
    required this.errors,
    required this.message,
  });
}

class TerminalOutput {
  final String type; // 'stdout', 'stderr', 'system', 'error', 'exit'
  final String? data;
  final String? message;
  final int? exitCode;
  final DateTime timestamp;

  TerminalOutput({
    required this.type,
    this.data,
    this.message,
    this.exitCode,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class TerminalProxyClient extends ChangeNotifier {
  final String url;
  final GatewayAuth auth;
  String _role;

  static const int _maxOutputs = 10000;

  WebSocketChannel? _channel;
  TerminalConnectionState _state = TerminalConnectionState.disconnected;
  final List<TerminalOutput> _outputs = [];
  bool _isAuthenticated = false;
  bool _isExecuting = false;
  bool _disposed = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  /// Completer that resolves when auth succeeds (or fails/times out).
  Completer<void>? _authCompleter;

  /// Completers for pending env operations (resolved in _onMessage).
  Completer<Map<String, String>>? _envListCompleter;
  Completer<void>? _envSetCompleter;
  Completer<void>? _envDeleteCompleter;
  Completer<EnvSyncResult>? _envSyncCompleter;

  /// Command queue: each entry is a Future that completes when the previous
  /// command finishes. This ensures only one command runs at a time even when
  /// multiple callers invoke executeCommandForOutput concurrently.
  Future<void> _execQueue = Future.value();

  TerminalConnectionState get state => _state;
  List<TerminalOutput> get outputs => List.unmodifiable(_outputs);
  bool get isAuthenticated => _isAuthenticated;
  bool get isExecuting => _isExecuting;
  bool get isConnected => _state == TerminalConnectionState.connected;

  TerminalProxyClient({
    required this.url,
    required this.auth,
    String role = 'admin',
  }) : _role = role;

  /// Update the role used for terminal proxy authentication.
  void updateRole(String role) {
    _role = role;
  }

  /// Connect to the terminal proxy and wait for authentication to complete.
  /// Returns when authenticated, or throws on auth failure / timeout.
  Future<void> connect() async {
    // Already connected and authed -- nothing to do.
    if (_state == TerminalConnectionState.connected && _isAuthenticated) return;

    // If already connecting, wait for the in-flight auth to finish.
    if (_state == TerminalConnectionState.connecting && _authCompleter != null) {
      return _authCompleter!.future;
    }

    _state = TerminalConnectionState.connecting;
    _authCompleter = Completer<void>();
    notifyListeners();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready; // Wait for WebSocket handshake to complete

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _authenticate();

      // Wait for the auth response (resolved in _onMessage 'auth' case).
      // Timeout after 10 seconds so callers don't hang forever.
      await _authCompleter!.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (!_authCompleter!.isCompleted) {
            _authCompleter!.completeError(
              TimeoutException('Terminal proxy auth timed out'),
            );
          }
        },
      );
    } catch (e) {
      _state = TerminalConnectionState.error;
      notifyListeners();
      rethrow;
    }
  }

  void _authenticate() {
    _channel?.sink.add(jsonEncode({
      'type': 'auth',
      'token': auth.token,
      'role': _role,
    }));
  }

  void _addOutput(TerminalOutput output) {
    _outputs.add(output);
    // Evict oldest entries if over capacity
    if (_outputs.length > _maxOutputs) {
      _outputs.removeRange(0, _outputs.length - _maxOutputs);
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String);
      final type = data['type'] as String;

      switch (type) {
        case 'auth':
          _isAuthenticated = data['status'] == 'ok';
          if (_isAuthenticated) {
            _state = TerminalConnectionState.connected;
            _reconnectAttempts = 0;
            _reconnectTimer?.cancel();
            if (_authCompleter != null && !_authCompleter!.isCompleted) {
              _authCompleter!.complete();
            }
          } else {
            _state = TerminalConnectionState.error;
            if (_authCompleter != null && !_authCompleter!.isCompleted) {
              _authCompleter!.completeError(
                StateError('Terminal proxy auth failed'),
              );
            }
          }
          notifyListeners();
          break;

        case 'stdout':
          _addOutput(TerminalOutput(
            type: 'stdout',
            data: data['data'] as String,
          ));
          notifyListeners();
          break;

        case 'stderr':
          _addOutput(TerminalOutput(
            type: 'stderr',
            data: data['data'] as String,
          ));
          notifyListeners();
          break;

        case 'system':
          _addOutput(TerminalOutput(
            type: 'system',
            message: data['message'] as String,
          ));
          notifyListeners();
          break;

        case 'error':
          _isExecuting = false;
          final errMsg = data['message'] as String;
          _addOutput(TerminalOutput(
            type: 'error',
            message: errMsg,
          ));
          // Fail any pending env completers -- the server sends generic
          // {type:'error'} for auth/permission failures on env operations
          // instead of a typed env_* response.
          _failPendingEnvCompleters(errMsg);
          notifyListeners();
          break;

        case 'exit':
          _isExecuting = false;
          _addOutput(TerminalOutput(
            type: 'exit',
            exitCode: data['code'] as int?,
            message: data['message'] as String?,
          ));
          notifyListeners();
          break;

        case 'pong':
          // Keep alive response
          break;

        // ── Dynamic env var responses ──────────────────────────────────
        case 'env_list':
          if (_envListCompleter != null && !_envListCompleter!.isCompleted) {
            final rawVars = data['vars'] as Map<String, dynamic>? ?? {};
            final vars = rawVars.map((k, v) => MapEntry(k, v.toString()));
            _envListCompleter!.complete(vars);
          }
          break;

        case 'env_set':
          if (data['status'] == 'ok') {
            if (_envSetCompleter != null && !_envSetCompleter!.isCompleted) {
              _envSetCompleter!.complete();
            }
          } else {
            final msg = data['message'] as String? ?? 'Failed to set env var';
            if (_envSetCompleter != null && !_envSetCompleter!.isCompleted) {
              _envSetCompleter!.completeError(StateError(msg));
            }
          }
          break;

        case 'env_delete':
          if (data['status'] == 'ok') {
            if (_envDeleteCompleter != null && !_envDeleteCompleter!.isCompleted) {
              _envDeleteCompleter!.complete();
            }
          } else {
            final msg = data['message'] as String? ?? 'Failed to delete env var';
            if (_envDeleteCompleter != null && !_envDeleteCompleter!.isCompleted) {
              _envDeleteCompleter!.completeError(StateError(msg));
            }
          }
          break;

        case 'env_sync_gateway':
          if (_envSyncCompleter != null && !_envSyncCompleter!.isCompleted) {
            final syncedRaw = data['synced'] as List<dynamic>? ?? [];
            final skippedRaw = data['skipped'] as List<dynamic>? ?? [];
            final errorsRaw = data['errors'] as List<dynamic>? ?? [];
            final result = EnvSyncResult(
              synced: syncedRaw.map((e) => e.toString()).toList(),
              skipped: skippedRaw.map((e) => e.toString()).toList(),
              errors: errorsRaw.map((e) => e.toString()).toList(),
              message: data['message'] as String? ?? '',
            );
            if (data['status'] == 'ok') {
              _envSyncCompleter!.complete(result);
            } else {
              // Still provide the result via completeError wrapping
              _envSyncCompleter!.completeError(result);
            }
          }
          break;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Terminal] Error parsing message: $e');
    }
  }

  void _onError(dynamic error) {
    _state = TerminalConnectionState.error;
    _outputs.add(TerminalOutput(
      type: 'error',
      message: 'Connection error: $error',
    ));
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _authCompleter!.completeError(error);
    }
    _failPendingEnvCompleters('Connection error');
    notifyListeners();
  }

  void _onDone() {
    _state = TerminalConnectionState.disconnected;
    _isAuthenticated = false;
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _authCompleter!.completeError(
        StateError('Terminal proxy connection closed before auth'),
      );
    }
    _failPendingEnvCompleters('Connection closed');
    notifyListeners();
    _scheduleReconnect();
  }

  /// Auto-reconnect with exponential backoff (mirrors GatewayClient pattern)
  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectAttempts++;
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s max
    final delay = Duration(
        seconds: (_reconnectAttempts <= 5)
            ? (1 << (_reconnectAttempts - 1))
            : 30);
    if (kDebugMode) debugPrint('[Terminal] reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_disposed &&
          _state != TerminalConnectionState.connected &&
          _state != TerminalConnectionState.connecting) {
        connect().catchError((_) {});
      }
    });
  }

  void executeCommand(String command) {
    if (!_isAuthenticated || _channel == null) {
      _outputs.add(TerminalOutput(
        type: 'error',
        message: 'Not connected to terminal proxy',
      ));
      notifyListeners();
      return;
    }

    _isExecuting = true;
    _channel!.sink.add(jsonEncode({
      'type': 'exec',
      'command': command,
    }));
    notifyListeners();
  }

  /// Execute a command and return its collected stdout as a string.
  ///
  /// Commands are queued: if multiple callers invoke this concurrently, each
  /// command waits for the previous one to finish before starting. This
  /// prevents output interleaving on the single WebSocket connection.
  Future<String> executeCommandForOutput(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    // Chain onto the queue so only one command runs at a time.
    final previous = _execQueue;
    final completer = Completer<String>();
    _execQueue = completer.future.catchError((_) {});
    // ignore errors in the queue chain so a failed command doesn't block the next

    previous.then((_) {
      _executeCommandSingle(command, timeout: timeout).then(
        (result) { if (!completer.isCompleted) completer.complete(result); },
        onError: (e) { if (!completer.isCompleted) completer.completeError(e); },
      );
    });

    return completer.future;
  }

  /// Internal: run a single command after the queue has released.
  Future<String> _executeCommandSingle(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_isAuthenticated || _channel == null) {
      throw StateError('Not connected to terminal proxy');
    }

    // If somehow still executing (e.g. stale state), wait for it to clear.
    if (_isExecuting) {
      final waitCompleter = Completer<void>();
      Timer? waitTimer;

      void waitListener() {
        if (!_isExecuting && !waitCompleter.isCompleted) {
          removeListener(waitListener);
          waitTimer?.cancel();
          waitCompleter.complete();
        }
      }

      addListener(waitListener);
      waitTimer = Timer(timeout, () {
        removeListener(waitListener);
        if (!waitCompleter.isCompleted) {
          waitCompleter.completeError(
            TimeoutException('Timed out waiting for previous command to finish', timeout),
          );
        }
      });

      await waitCompleter.future;
    }

    final startIndex = _outputs.length;
    final resultCompleter = Completer<String>();
    Timer? timer;

    void finish() {
      if (resultCompleter.isCompleted) return;
      final slice = _outputs.sublist(startIndex);
      final buffer = StringBuffer();
      for (final out in slice) {
        final text = out.data ?? out.message;
        if (text == null || text.isEmpty) continue;
        buffer.writeln(text);
      }
      resultCompleter.complete(buffer.toString());
    }

    void listener() {
      if (!_isExecuting) {
        removeListener(listener);
        timer?.cancel();
        finish();
      }
    }

    addListener(listener);
    timer = Timer(timeout, () {
      removeListener(listener);
      if (!resultCompleter.isCompleted) {
        resultCompleter.completeError(
          TimeoutException('Command timed out: $command', timeout),
        );
      }
    });

    executeCommand(command);
    return resultCompleter.future;
  }

  void cancelCommand() {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': 'cancel',
      }));
    }
  }

  // ── Dynamic environment variable management (superadmin only) ─────────

  /// Fail all pending env completers with the given error message.
  /// Called when the connection drops or the server sends a generic error.
  void _failPendingEnvCompleters(String reason) {
    final err = StateError(reason);
    if (_envListCompleter != null && !_envListCompleter!.isCompleted) {
      _envListCompleter!.completeError(err);
    }
    if (_envSetCompleter != null && !_envSetCompleter!.isCompleted) {
      _envSetCompleter!.completeError(err);
    }
    if (_envDeleteCompleter != null && !_envDeleteCompleter!.isCompleted) {
      _envDeleteCompleter!.completeError(err);
    }
    if (_envSyncCompleter != null && !_envSyncCompleter!.isCompleted) {
      _envSyncCompleter!.completeError(err);
    }
  }

  /// List all dynamic env var overrides.
  Future<Map<String, String>> listEnvVars({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!_isAuthenticated || _channel == null) {
      throw StateError('Not connected to terminal proxy');
    }
    // Cancel any previous in-flight request to prevent orphaned completers
    if (_envListCompleter != null && !_envListCompleter!.isCompleted) {
      _envListCompleter!.completeError(StateError('Superseded by new request'));
    }
    _envListCompleter = Completer<Map<String, String>>();
    _channel!.sink.add(jsonEncode({'type': 'env_list'}));
    return _envListCompleter!.future.timeout(timeout);
  }

  /// Set or update a dynamic env var override.
  Future<void> setEnvVar(
    String key,
    String value, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!_isAuthenticated || _channel == null) {
      throw StateError('Not connected to terminal proxy');
    }
    if (_envSetCompleter != null && !_envSetCompleter!.isCompleted) {
      _envSetCompleter!.completeError(StateError('Superseded by new request'));
    }
    _envSetCompleter = Completer<void>();
    _channel!.sink.add(jsonEncode({
      'type': 'env_set',
      'key': key,
      'value': value,
    }));
    return _envSetCompleter!.future.timeout(timeout);
  }

  /// Delete a dynamic env var override.
  Future<void> deleteEnvVar(
    String key, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (!_isAuthenticated || _channel == null) {
      throw StateError('Not connected to terminal proxy');
    }
    if (_envDeleteCompleter != null && !_envDeleteCompleter!.isCompleted) {
      _envDeleteCompleter!.completeError(StateError('Superseded by new request'));
    }
    _envDeleteCompleter = Completer<void>();
    _channel!.sink.add(jsonEncode({
      'type': 'env_delete',
      'key': key,
    }));
    return _envDeleteCompleter!.future.timeout(timeout);
  }

  /// Sync all env overrides with known config mappings into the gateway
  /// config file, then trigger a gateway restart.
  Future<EnvSyncResult> syncEnvToGateway({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_isAuthenticated || _channel == null) {
      throw StateError('Not connected to terminal proxy');
    }
    if (_envSyncCompleter != null && !_envSyncCompleter!.isCompleted) {
      _envSyncCompleter!.completeError(StateError('Superseded by new request'));
    }
    _envSyncCompleter = Completer<EnvSyncResult>();
    _channel!.sink.add(jsonEncode({'type': 'env_sync_gateway'}));
    return _envSyncCompleter!.future.timeout(timeout);
  }

  void clearOutput() {
    _outputs.clear();
    notifyListeners();
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _channel?.sink.close();
    _state = TerminalConnectionState.disconnected;
    _isAuthenticated = false;
    _isExecuting = false;
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _authCompleter!.completeError(
        StateError('Terminal proxy disconnected'),
      );
    }
    _authCompleter = null;
    _failPendingEnvCompleters('Disconnected');
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    super.dispose();
  }

  void sendPing() {
    _channel?.sink.add(jsonEncode({'type': 'ping'}));
  }
}
