import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/http_utils.dart';
import '../../main.dart' show authClientProvider;
import 'canvas_mode_provider.dart';

const _drawIORecoveryStorageKey = 'trinity_drawio_xml_recovery_v1';
const _maxDrawIOSnapshots = 20;

class DrawIOSnapshot {
  final String id;
  final String name;
  final String xml;
  final DateTime createdAt;
  final String xmlHash;

  const DrawIOSnapshot({
    required this.id,
    required this.name,
    required this.xml,
    required this.createdAt,
    required this.xmlHash,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'xml': xml,
        'createdAt': createdAt.toIso8601String(),
        'xmlHash': xmlHash,
      };

  static DrawIOSnapshot? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    final xml = json['xml'] as String?;
    final createdAtRaw = json['createdAt'] as String?;
    final xmlHash = json['xmlHash'] as String?;
    if (id == null || name == null || xml == null || createdAtRaw == null) {
      return null;
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) return null;
    return DrawIOSnapshot(
      id: id,
      name: name,
      xml: xml,
      createdAt: createdAt,
      xmlHash: xmlHash ?? DrawIOSnapshotStore.computeHash(xml),
    );
  }
}

class DrawIOSnapshotStore {
  static const _baseUrl = String.fromEnvironment(
    'AUTH_SERVICE_URL',
    defaultValue: 'http://localhost',
  );

  static String computeHash(String xml) {
    var hash = 2166136261;
    for (final codeUnit in xml.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Future<List<DrawIOSnapshot>> list({
    required String token,
    required String openclawId,
  }) async {
    final response = await _request(
      method: 'GET',
      path: '/auth/openclaws/$openclawId/drawio/snapshots',
      token: token,
    );
    final list = response['snapshots'] as List? ?? const [];
    return list
        .map((item) => DrawIOSnapshot.fromJson(Map<String, dynamic>.from(item as Map)))
        .whereType<DrawIOSnapshot>()
        .toList();
  }

  static Future<List<DrawIOSnapshot>> save({
    required String token,
    required String openclawId,
    required String name,
    required String xml,
  }) async {
    final safeName = name.trim().isEmpty ? _defaultName(DateTime.now()) : name.trim();
    final response = await _request(
      method: 'POST',
      path: '/auth/openclaws/$openclawId/drawio/snapshots',
      token: token,
      body: {'name': safeName, 'xml': xml},
    );
    final list = response['snapshots'] as List? ?? const [];
    return list
        .map((item) => DrawIOSnapshot.fromJson(Map<String, dynamic>.from(item as Map)))
        .whereType<DrawIOSnapshot>()
        .toList();
  }

  static Future<List<DrawIOSnapshot>> deleteById({
    required String token,
    required String openclawId,
    required String id,
  }) async {
    final response = await _request(
      method: 'DELETE',
      path: '/auth/openclaws/$openclawId/drawio/snapshots/$id',
      token: token,
    );
    final list = response['snapshots'] as List? ?? const [];
    return list
        .map((item) => DrawIOSnapshot.fromJson(Map<String, dynamic>.from(item as Map)))
        .whereType<DrawIOSnapshot>()
        .toList();
  }

  static void saveRecovery(String xml) {
    html.window.localStorage[_drawIORecoveryStorageKey] = xml;
  }

  static String? recoveryXml() {
    final raw = html.window.localStorage[_drawIORecoveryStorageKey];
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  static String _defaultName(DateTime dt) {
    final yyyy = dt.year.toString().padLeft(4, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final sec = dt.second.toString().padLeft(2, '0');
    return 'diagram-$yyyy$mm$dd-$hh$min$sec';
  }

  static Future<Map<String, dynamic>> _request({
    required String method,
    required String path,
    required String token,
    Map<String, dynamic>? body,
  }) async {
    final request = html.HttpRequest();
    request.open(method, '$_baseUrl$path');
    request.setRequestHeader('Authorization', 'Bearer $token');
    request.setRequestHeader('Content-Type', 'application/json');

    final text = await safeXhr(request,
        body: body == null ? null : jsonEncode(body));
    if (text.trim().isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(text) as Map);
  }
}

/// Embeds the diagrams.net (draw.io) editor via iframe + postMessage API.
/// Supports PNG export and copy-to-clipboard.
/// Uses minimal interface in both light/dark modes.
class DrawIORenderer extends ConsumerStatefulWidget {
  final bool dialogIsOpen;

  const DrawIORenderer({
    super.key,
    this.dialogIsOpen = false,
  });

  @override
  ConsumerState<DrawIORenderer> createState() => DrawIORendererState();
}

class DrawIORendererState extends ConsumerState<DrawIORenderer> {
  html.IFrameElement? _iframe;
  late String _viewType;
  StreamSubscription? _messageSub;

  // Export callback — set temporarily while waiting for an export response.
  void Function(String format, String data)? _pendingExport;
  Completer<String?>? _pendingXmlSave;
  String? _pendingLoadXml;
  String? _lastKnownXml;
  bool _initialized = false;
  String _lastEvent = 'none';
  String? _lastSaveError;
  Timer? _autoSnapshotTimer;
  String? _lastRecoveryHash;

  bool get canSaveXml => _initialized && (_lastKnownXml?.trim().isNotEmpty ?? false);

  String get debugStatus =>
      'event=$_lastEvent init=$_initialized xmlLen=${_lastKnownXml?.length ?? 0}';

  String? get lastSaveError => _lastSaveError;

  @override
  void initState() {
    super.initState();
    _viewType = 'drawio-${identityHashCode(this)}';
    _pendingLoadXml = DrawIOSnapshotStore.recoveryXml();
    _setupIframe();
    _listenMessages();
    _startAutoSnapshot();
  }

  @override
  void didUpdateWidget(DrawIORenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dialogIsOpen != widget.dialogIsOpen) {
      if (widget.dialogIsOpen) {
        disablePointerEvents();
      } else {
        enablePointerEvents();
      }
    }
  }

  /// Get DrawIO dark mode value; layout stays minimal in both themes.
  String _getDrawIODarkMode() {
    final drawIOTheme = ref.read(drawIOThemeProvider);
    return drawIOTheme == DrawIOTheme.dark ? '1' : '0';
  }

  String _defaultDiagramXml() {
    final drawIOTheme = ref.read(drawIOThemeProvider);
    final dark = drawIOTheme == DrawIOTheme.dark;
    final bg = dark ? '#0A0A0A' : '#F5F5F5';
    final grid = dark ? '#1F2937' : '#D1D5DB';
    final page = dark ? '#0F172A' : '#FFFFFF';
    return '<mxfile><diagram id="trinity-default" name="Page-1"><mxGraphModel dx="1426" dy="794" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1169" pageHeight="827" math="0" shadow="0" background="$bg" gridColor="$grid" pageBackgroundColor="$page"><root><mxCell id="0"/><mxCell id="1" parent="0"/></root></mxGraphModel></diagram></mxfile>';
  }

  /// Reload iframe with current DrawIO theme (called when theme toggled)
  Future<void> reloadWithTheme() async {
    await _reloadWithTheme();
  }

  void _setupIframe() {
    final darkMode = _getDrawIODarkMode();
    final params = {
      'embed': '1',
      'ui': 'min',
      'dark': darkMode,
      'lang': 'en',
      'proto': 'json',
      'spin': '1',
      'saveAndExit': '0',
      'noSaveBtn': '1',
      'noExitBtn': '1',
    };
    final qs = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    _iframe = html.IFrameElement()
      ..src = 'https://embed.diagrams.net/?$qs'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..allow = 'clipboard-read; clipboard-write';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _iframe!,
    );
  }

  Future<void> _reloadWithTheme() async {
    final cached = _lastKnownXml;
    if (cached != null && cached.trim().isNotEmpty) {
      _pendingLoadXml = cached;
    } else {
      final xml = await getXml();
      if (xml != null && xml.trim().isNotEmpty) {
        _pendingLoadXml = xml;
      }
    }

    // Create new iframe with updated theme
    final newViewType = 'drawio-${identityHashCode(this)}-${DateTime.now().millisecondsSinceEpoch}';
    final darkMode = _getDrawIODarkMode();

    final params = {
      'embed': '1',
      'ui': 'min',
      'dark': darkMode,
      'lang': 'en',
      'proto': 'json',
      'spin': '1',
      'saveAndExit': '0',
      'noSaveBtn': '1',
      'noExitBtn': '1',
    };
    final qs = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    final newIframe = html.IFrameElement()
      ..src = 'https://embed.diagrams.net/?$qs'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..allow = 'clipboard-read; clipboard-write';

    ui_web.platformViewRegistry.registerViewFactory(
      newViewType,
      (int viewId) => newIframe,
    );

    setState(() {
      _viewType = newViewType;
      _iframe = newIframe;
    });
  }

  void _listenMessages() {
    _messageSub = html.window.onMessage.listen((event) {
      final msg = _parseIncomingMessage(event.data);
      if (msg == null) return;
      _handleMessage(msg);
    });
  }

  Map<String, dynamic>? _parseIncomingMessage(dynamic raw) {
    try {
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry('$k', v));
        }
        return null;
      }

      if (raw is Map) {
        return raw.map((k, v) => MapEntry('$k', v));
      }

      final dartified = js_util.dartify(raw);
      if (dartified is Map) {
        return dartified.map((k, v) => MapEntry('$k', v));
      }
    } catch (_) {
      // ignore parse failures from unrelated postMessage events
    }
    return null;
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final evt = msg['event'] as String?;
    if (evt != null && evt.isNotEmpty) {
      _lastEvent = evt;
    }
    switch (evt) {
      case 'init':
        // Required: send load action after init to unblock the editor
        final xml = _pendingLoadXml ?? _defaultDiagramXml();
        _pendingLoadXml = null;
        _lastKnownXml = xml;
        _initialized = true;
        _post({
          'action': 'load',
          'xml': xml,
          'autosave': 1,
        });
        break;
      case 'autosave':
        final autosaveXml = msg['xml'] as String?;
        if (autosaveXml != null && autosaveXml.trim().isNotEmpty) {
          _lastKnownXml = autosaveXml;
          _persistRecoveryIfChanged();
        }
        break;
      case 'export':
        final format = msg['format'] as String?;
        final data = msg['data'] as String?;
        if (format != null && format.isNotEmpty) {
          _lastEvent = 'export:$format';
        }
        if (format != null && data != null) {
          _pendingExport?.call(format, data);
        }
        break;
      case 'save':
        final xml = msg['xml'] as String?;
        if (xml != null && xml.trim().isNotEmpty) {
          _lastKnownXml = xml;
          _persistRecoveryIfChanged();
        }
        if (_pendingXmlSave != null && !_pendingXmlSave!.isCompleted) {
          _pendingXmlSave!.complete(xml);
        }
        _pendingXmlSave = null;
        break;
    }
  }

  void _post(Map<String, dynamic> message) {
    _iframe?.contentWindow?.postMessage(jsonEncode(message), '*');
  }

  /// Blur the iframe to return focus to parent window
  void blur() {
    _iframe?.blur();
  }

  /// Focus the iframe
  void focus() {
    _iframe?.focus();
  }

  /// Disable pointer events on iframe - allows clicks to pass through to Flutter widgets
  void disablePointerEvents() {
    _iframe?.style.pointerEvents = 'none';
  }

  /// Enable pointer events on iframe - restore normal interaction
  void enablePointerEvents() {
    _iframe?.style.pointerEvents = 'auto';
  }

  /// Request PNG export from draw.io and download it.
  void exportPng() {
    _pendingExport = (format, data) {
      if (format != 'png') return;
      html.AnchorElement(href: data)
        ..setAttribute('download',
            'diagram-${DateTime.now().millisecondsSinceEpoch}.png')
        ..click();
      _pendingExport = null;
    };
    _post({
      'action': 'export',
      'format': 'png',
      'spin': '1',
      'border': '10',
      'crop': '1',
    });
  }

  /// Request PNG export and copy to clipboard.
  void copyPng() {
    _pendingExport = (format, data) async {
      if (format != 'png') return;
      try {
        final b64 = data.contains(',') ? data.split(',').last : data;
        final bytes = base64Decode(b64);
        final blob = html.Blob([bytes], 'image/png');

        final clipboardItem = js_util.callConstructor(
          js_util.getProperty(html.window, 'ClipboardItem'),
          [js_util.jsify({'image/png': blob})],
        );
        final clipboard =
            js_util.getProperty(html.window.navigator, 'clipboard');
        await js_util.promiseToFuture(
          js_util.callMethod(clipboard, 'write', [
            js_util.jsify([clipboardItem]),
          ]),
        );
      } catch (e) {
        debugPrint('[DrawIO] clipboard copy failed: $e');
      }
      _pendingExport = null;
    };
    _post({
      'action': 'export',
      'format': 'png',
      'spin': '1',
      'border': '10',
      'crop': '1',
    });
  }

  Future<String?> getXml() async {
    if (_pendingXmlSave != null && !_pendingXmlSave!.isCompleted) {
      return null;
    }

    final completer = Completer<String?>();
    _pendingXmlSave = completer;
    _pendingExport = (format, data) {
      final xml = _extractXmlFromExport(format, data);
      if (xml == null || xml.trim().isEmpty) return;
      _lastKnownXml = xml;
      if (!completer.isCompleted) {
        completer.complete(xml);
      }
      _pendingExport = null;
    };

    _post({
      'action': 'save',
      'exit': false,
    });
    _post({
      'action': 'export',
      'format': 'xml',
      'spin': '1',
    });
    _post({
      'action': 'export',
      'format': 'xmlsvg',
      'spin': '1',
    });

    return completer.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        if (_pendingXmlSave == completer) {
          _pendingXmlSave = null;
        }
        _pendingExport = null;
        return _lastKnownXml;
      },
    );
  }

  Future<bool> saveXmlSnapshot() async {
    return saveXmlSnapshotNamed('');
  }

  Future<bool> saveXmlSnapshotNamed(String name) async {
    _lastSaveError = null;

    if (!_initialized) {
      _lastSaveError = 'drawio not initialized';
      return false;
    }

    var xml = _lastKnownXml;
    if (xml == null || xml.trim().isEmpty) {
      xml = await getXml();
    }

    if (xml == null || xml.trim().isEmpty) {
      _lastSaveError = 'xml unavailable ($debugStatus)';
      return false;
    }
    try {
      final authState = ref.read(authClientProvider).state;
      final token = authState.token;
      final openclawId = authState.activeOpenClawId;
      if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) {
        _lastSaveError = 'missing auth/openclaw context';
        return false;
      }
      await DrawIOSnapshotStore.save(
        token: token,
        openclawId: openclawId,
        name: name,
        xml: xml,
      );
      return true;
    } catch (e) {
      _lastSaveError = 'snapshot save failed: $e';
      return false;
    }
  }

  void loadXmlSnapshot(String xml) {
    if (xml.trim().isEmpty) return;
    _lastKnownXml = xml;
    _persistRecoveryIfChanged();
    _post({
      'action': 'load',
      'xml': xml,
      'autosave': 1,
    });
  }

  String? _extractXmlFromExport(String format, String data) {
    if (format == 'xml' && data.trim().startsWith('<')) {
      return data;
    }

    if (format != 'xmlsvg' && !data.startsWith('data:image/svg+xml')) {
      return null;
    }

    try {
      final comma = data.indexOf(',');
      if (comma < 0) return null;
      final meta = data.substring(0, comma);
      final payload = data.substring(comma + 1);
      final svgText = meta.contains(';base64')
          ? utf8.decode(base64Decode(payload))
          : Uri.decodeComponent(payload);

      final escaped = _extractSvgContentAttribute(svgText);
      if (escaped == null || escaped.isEmpty) return null;
      return escaped
          .replaceAll('&quot;', '"')
          .replaceAll('&apos;', "'")
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&');
    } catch (_) {
      return null;
    }
  }

  String? _extractSvgContentAttribute(String svgText) {
    const key = 'content=';
    final start = svgText.indexOf(key);
    if (start < 0) return null;
    final quoteIndex = start + key.length;
    if (quoteIndex >= svgText.length) return null;
    final quote = svgText[quoteIndex];
    if (quote != '"' && quote != "'") return null;
    final end = svgText.indexOf(quote, quoteIndex + 1);
    if (end < 0) return null;
    return svgText.substring(quoteIndex + 1, end);
  }

  void _startAutoSnapshot() {
    _autoSnapshotTimer?.cancel();
    _autoSnapshotTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _persistRecoveryIfChanged(),
    );
  }

  void _persistRecoveryIfChanged() {
    final xml = _lastKnownXml;
    if (xml == null || xml.trim().isEmpty) return;
    final hash = DrawIOSnapshotStore.computeHash(xml);
    if (hash == _lastRecoveryHash) return;
    _lastRecoveryHash = hash;
    DrawIOSnapshotStore.saveRecovery(xml);
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _autoSnapshotTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
