import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';

import 'http_utils.dart';

class AppUpdateGate extends StatefulWidget {
  final Widget child;

  const AppUpdateGate({super.key, required this.child});

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  static const Duration _pollInterval = Duration(seconds: 90);

  Timer? _pollTimer;
  String? _initialVersionToken;
  bool _updateAvailable = false;
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeUpdateChecks());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeUpdateChecks() async {
    _initialVersionToken = await _fetchVersionToken();
    await _checkForUpdates();
    _pollTimer = Timer.periodic(_pollInterval, (_) => unawaited(_checkForUpdates()));
  }

  Future<void> _checkForUpdates() async {
    if (!mounted || _updateAvailable) return;

    final latestVersionToken = await _fetchVersionToken();
    if (!mounted) return;

    if (_initialVersionToken != null &&
        latestVersionToken != null &&
        latestVersionToken != _initialVersionToken) {
      setState(() => _updateAvailable = true);
      return;
    }

    final swUpdate = await _hasWaitingServiceWorker();
    if (!mounted) return;
    if (swUpdate) {
      setState(() => _updateAvailable = true);
    }
  }

  Future<String?> _fetchVersionToken() async {
    for (final path in ['/trinity-version.json', '/version.json']) {
      final token = await _fetchVersionTokenFrom(path);
      if (token != null && token.isNotEmpty) return token;
    }
    return null;
  }

  Future<String?> _fetchVersionTokenFrom(String path) async {
    try {
      final response = await safeHttpRequest(
        '$path?v=${DateTime.now().millisecondsSinceEpoch}',
        method: 'GET',
        requestHeaders: const {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
        },
        timeout: const Duration(seconds: 5),
      );

      if (response.status != 200) return null;

      final raw = response.responseText ?? '';
      if (raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final version = decoded['version'];
        final build = decoded['build'] ?? decoded['buildNumber'];
        if (version is String && build is String) return '$version+$build';
        if (build is String) return build;
        if (version is String) return version;
      }

      return raw;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _hasWaitingServiceWorker() async {
    try {
      final sw = html.window.navigator.serviceWorker;
      if (sw == null) return false;
      final reg = await sw.getRegistration();

      await reg.update();
      return reg.waiting != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyUpdate() async {
    if (_reloading) return;
    setState(() => _reloading = true);

    try {
      final sw = html.window.navigator.serviceWorker;
      if (sw == null) {
        html.window.location.reload();
        return;
      }
      final reg = await sw.getRegistration();
      if (reg.waiting != null) {
        reg.waiting!.postMessage('skipWaiting');
        reg.waiting!.postMessage({'type': 'SKIP_WAITING'});
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    } catch (_) {
      // fallback to direct reload below
    }

    html.window.location.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (!_updateAvailable) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                border: Border.all(color: const Color(0xFF2A2A2A), width: 0.5),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'A newer Trinity version is available.',
                      style: TextStyle(fontSize: 11, color: Color(0xFFE5E5E5)),
                    ),
                  ),
                  TextButton(
                    onPressed: _reloading ? null : _applyUpdate,
                    child: Text(
                      _reloading ? 'reloading...' : 'reload now',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF6EE7B7)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
