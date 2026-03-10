import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'canvas_mode_provider.dart';

const _drawIOSnapshotsStorageKey = 'trinity_drawio_xml_snapshots_v1';
const _maxDrawIOSnapshots = 20;

class DrawIOSnapshot {
  final String id;
  final String name;
  final String xml;
  final DateTime createdAt;

  const DrawIOSnapshot({
    required this.id,
    required this.name,
    required this.xml,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'xml': xml,
        'createdAt': createdAt.toIso8601String(),
      };

  static DrawIOSnapshot? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    final xml = json['xml'] as String?;
    final createdAtRaw = json['createdAt'] as String?;
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
    );
  }
}

class DrawIOSnapshotStore {
  static List<DrawIOSnapshot> list() {
    final stored = html.window.localStorage[_drawIOSnapshotsStorageKey];
    if (stored == null || stored.isEmpty) return const [];
    try {
      final decoded = jsonDecode(stored) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(DrawIOSnapshot.fromJson)
          .whereType<DrawIOSnapshot>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static void save(String name, String xml) {
    final now = DateTime.now();
    final snapshots = list();
    final safeName = name.trim().isEmpty ? _defaultName(now) : name.trim();
    snapshots.insert(
      0,
      DrawIOSnapshot(
        id: '${now.microsecondsSinceEpoch}',
        name: safeName,
        xml: xml,
        createdAt: now,
      ),
    );
    if (snapshots.length > _maxDrawIOSnapshots) {
      snapshots.removeRange(_maxDrawIOSnapshots, snapshots.length);
    }
    _persist(snapshots);
  }

  static void deleteById(String id) {
    final snapshots = list();
    snapshots.removeWhere((s) => s.id == id);
    _persist(snapshots);
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

  static void _persist(List<DrawIOSnapshot> snapshots) {
    final json = snapshots.map((s) => s.toJson()).toList();
    html.window.localStorage[_drawIOSnapshotsStorageKey] = jsonEncode(json);
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

  bool get canSaveXml => _initialized && (_lastKnownXml?.trim().isNotEmpty ?? false);

  String get debugStatus =>
      'event=$_lastEvent init=$_initialized xmlLen=${_lastKnownXml?.length ?? 0}';

  String? get lastSaveError => _lastSaveError;

  @override
  void initState() {
    super.initState();
    _viewType = 'drawio-${identityHashCode(this)}';
    _setupIframe();
    _listenMessages();
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
        final xml = _pendingLoadXml ?? '<mxfile><diagram></diagram></mxfile>';
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
      DrawIOSnapshotStore.save('', xml);
      return true;
    } catch (e) {
      _lastSaveError = 'localStorage write failed: $e';
      return false;
    }
  }

  void loadXmlSnapshot(String xml) {
    if (xml.trim().isEmpty) return;
    _lastKnownXml = xml;
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

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
