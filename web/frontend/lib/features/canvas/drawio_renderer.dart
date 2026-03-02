import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Embeds the diagrams.net (draw.io) editor via iframe + postMessage API.
/// Supports PNG export and copy-to-clipboard.
class DrawIORenderer extends StatefulWidget {
  const DrawIORenderer({super.key});

  @override
  State<DrawIORenderer> createState() => DrawIORendererState();
}

class DrawIORendererState extends State<DrawIORenderer> {
  html.IFrameElement? _iframe;
  late final String _viewType;
  StreamSubscription? _messageSub;
  bool _ready = false;

  // Export callback — set temporarily while waiting for an export response.
  void Function(String format, String data)? _pendingExport;

  @override
  void initState() {
    super.initState();
    _viewType = 'drawio-${identityHashCode(this)}';
    _setupIframe();
    _listenMessages();
  }

  void _setupIframe() {
    final params = {
      'embed': '1',
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

  void _listenMessages() {
    _messageSub = html.window.onMessage.listen((event) {
      final raw = event.data;
      if (raw is! String) return;
      try {
        final msg = jsonDecode(raw) as Map<String, dynamic>;
        _handleMessage(msg);
      } catch (_) {
        // draw.io may also send non-JSON strings — ignore them
      }
    });
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final evt = msg['event'] as String?;
    switch (evt) {
      case 'init':
        // Required: send load action after init to unblock the editor
        _post({
          'action': 'load',
          'xml': '<mxfile><diagram></diagram></mxfile>',
          'autosave': 0,
        });
        if (mounted) setState(() => _ready = true);
        break;
      case 'export':
        final format = msg['format'] as String?;
        final data = msg['data'] as String?;
        if (format != null && data != null) {
          _pendingExport?.call(format, data);
          _pendingExport = null;
        }
        break;
    }
  }

  void _post(Map<String, dynamic> message) {
    _iframe?.contentWindow?.postMessage(jsonEncode(message), '*');
  }

  /// Request PNG export from draw.io and download it.
  void exportPng() {
    _pendingExport = (format, data) {
      html.AnchorElement(href: data)
        ..setAttribute('download',
            'diagram-${DateTime.now().millisecondsSinceEpoch}.png')
        ..click();
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
    };
    _post({
      'action': 'export',
      'format': 'png',
      'spin': '1',
      'border': '10',
      'crop': '1',
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The iframe is an HTML platform view — it renders above Flutter widgets
    // in the browser DOM.  draw.io shows its own loading spinner (spin=1),
    // so we do NOT overlay a Flutter loading indicator (it would be invisible
    // underneath the iframe anyway).
    return HtmlElementView(viewType: _viewType);
  }
}
