import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/auth.dart';

enum TerminalConnectionState { disconnected, connecting, connected, error }

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

  WebSocketChannel? _channel;
  TerminalConnectionState _state = TerminalConnectionState.disconnected;
  final List<TerminalOutput> _outputs = [];
  bool _isAuthenticated = false;
  bool _isExecuting = false;

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

  Future<void> connect() async {
    if (_state == TerminalConnectionState.connected ||
        _state == TerminalConnectionState.connecting) return;

    _state = TerminalConnectionState.connecting;
    notifyListeners();

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      // Wait a moment then authenticate
      await Future.delayed(const Duration(milliseconds: 100));
      _authenticate();
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

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String);
      final type = data['type'] as String;

      switch (type) {
        case 'auth':
          _isAuthenticated = data['status'] == 'ok';
          if (_isAuthenticated) {
            _state = TerminalConnectionState.connected;
          } else {
            _state = TerminalConnectionState.error;
          }
          notifyListeners();
          break;

        case 'stdout':
          _outputs.add(TerminalOutput(
            type: 'stdout',
            data: data['data'] as String,
          ));
          notifyListeners();
          break;

        case 'stderr':
          _outputs.add(TerminalOutput(
            type: 'stderr',
            data: data['data'] as String,
          ));
          notifyListeners();
          break;

        case 'system':
          _outputs.add(TerminalOutput(
            type: 'system',
            message: data['message'] as String,
          ));
          notifyListeners();
          break;

        case 'error':
          _isExecuting = false;
          _outputs.add(TerminalOutput(
            type: 'error',
            message: data['message'] as String,
          ));
          notifyListeners();
          break;

        case 'exit':
          _isExecuting = false;
          _outputs.add(TerminalOutput(
            type: 'exit',
            exitCode: data['code'] as int?,
            message: data['message'] as String?,
          ));
          notifyListeners();
          break;

        case 'pong':
          // Keep alive response
          break;
      }
    } catch (e) {
      debugPrint('[Terminal] Error parsing message: $e');
    }
  }

  void _onError(dynamic error) {
    _state = TerminalConnectionState.error;
    _outputs.add(TerminalOutput(
      type: 'error',
      message: 'Connection error: $error',
    ));
    notifyListeners();
  }

  void _onDone() {
    _state = TerminalConnectionState.disconnected;
    _isAuthenticated = false;
    notifyListeners();
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

  Future<String> executeCommandForOutput(
    String command, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_isAuthenticated || _channel == null) {
      throw StateError('Not connected to terminal proxy');
    }
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
    final completer = Completer<String>();
    Timer? timer;

    void finish() {
      if (completer.isCompleted) return;
      final slice = _outputs.sublist(startIndex);
      final buffer = StringBuffer();
      for (final out in slice) {
        final text = out.data ?? out.message;
        if (text == null || text.isEmpty) continue;
        buffer.writeln(text);
      }
      completer.complete(buffer.toString());
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
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Command timed out: $command', timeout),
        );
      }
    });

    executeCommand(command);
    return completer.future;
  }

  void cancelCommand() {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode({
        'type': 'cancel',
      }));
    }
  }

  void clearOutput() {
    _outputs.clear();
    notifyListeners();
  }

  void disconnect() {
    _channel?.sink.close();
    _state = TerminalConnectionState.disconnected;
    _isAuthenticated = false;
    _isExecuting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }

  void sendPing() {
    _channel?.sink.add(jsonEncode({'type': 'ping'}));
  }
}
