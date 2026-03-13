import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/http_utils.dart';
import '../../core/providers.dart';

// ---------------------------------------------------------------------------
// Browser tab model
// ---------------------------------------------------------------------------

class BrowserTab {
  final String targetId;
  final String title;
  final String url;
  final String type;
  final bool active;

  const BrowserTab({
    required this.targetId,
    required this.title,
    required this.url,
    this.type = 'page',
    this.active = false,
  });

  factory BrowserTab.fromJson(Map<String, dynamic> json) => BrowserTab(
        targetId: json['targetId'] as String? ?? json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Untitled',
        url: json['url'] as String? ?? '',
        type: json['type'] as String? ?? 'page',
        active: json['active'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// Snapshot ref model (interactive element from ARIA snapshot)
// ---------------------------------------------------------------------------

class SnapshotRef {
  final String ref;
  final String role;
  final String name;
  final double? x;
  final double? y;
  final double? width;
  final double? height;

  const SnapshotRef({
    required this.ref,
    required this.role,
    required this.name,
    this.x,
    this.y,
    this.width,
    this.height,
  });
}

// ---------------------------------------------------------------------------
// Browser state
// ---------------------------------------------------------------------------

enum BrowserRunState { unknown, stopped, starting, running, error }

class BrowserState {
  final BrowserRunState runState;
  final List<BrowserTab> tabs;
  final String? activeTabId;
  final String? currentUrl;
  final String? pageTitle;
  final Uint8List? screenshotBytes;
  final String? snapshotText;
  final List<SnapshotRef> snapshotRefs;
  final int viewportWidth;
  final int viewportHeight;
  final bool autoRefresh;
  final String? error;
  final String? screenshotError;
  final bool isLoading; // any operation in progress
  final String profile;

  const BrowserState({
    this.runState = BrowserRunState.unknown,
    this.tabs = const [],
    this.activeTabId,
    this.currentUrl,
    this.pageTitle,
    this.screenshotBytes,
    this.snapshotText,
    this.snapshotRefs = const [],
    this.viewportWidth = 1280,
    this.viewportHeight = 720,
    this.autoRefresh = true,
    this.error,
    this.screenshotError,
    this.isLoading = false,
    this.profile = 'openclaw',
  });

  BrowserState copyWith({
    BrowserRunState? runState,
    List<BrowserTab>? tabs,
    String? activeTabId,
    String? currentUrl,
    String? pageTitle,
    Uint8List? screenshotBytes,
    String? snapshotText,
    List<SnapshotRef>? snapshotRefs,
    int? viewportWidth,
    int? viewportHeight,
    bool? autoRefresh,
    String? error,
    String? screenshotError,
    bool? isLoading,
    String? profile,
  }) =>
      BrowserState(
        runState: runState ?? this.runState,
        tabs: tabs ?? this.tabs,
        activeTabId: activeTabId ?? this.activeTabId,
        currentUrl: currentUrl ?? this.currentUrl,
        pageTitle: pageTitle ?? this.pageTitle,
        screenshotBytes: screenshotBytes ?? this.screenshotBytes,
        snapshotText: snapshotText ?? this.snapshotText,
        snapshotRefs: snapshotRefs ?? this.snapshotRefs,
        viewportWidth: viewportWidth ?? this.viewportWidth,
        viewportHeight: viewportHeight ?? this.viewportHeight,
        autoRefresh: autoRefresh ?? this.autoRefresh,
        error: error,
        screenshotError: screenshotError,
        isLoading: isLoading ?? this.isLoading,
        profile: profile ?? this.profile,
      );
}

// ---------------------------------------------------------------------------
// Browser state notifier
// ---------------------------------------------------------------------------

class BrowserNotifier extends StateNotifier<BrowserState> {
  final Ref _ref;
  Timer? _pollTimer;
  bool _disposed = false;

  BrowserNotifier(this._ref) : super(const BrowserState()) {
    _init();
  }

  String _humanizeError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    // In release mode, dart:html ProgressEvent (thrown on non-2xx HTTP) is
    // minified. Treat it as a gateway/network error, not a frontend bug.
    if (lower.contains('minified:') || lower.contains('progressevent')) {
      return 'Browser gateway not reachable. Retrying...';
    }
    if (lower.contains('timeout')) {
      return 'Browser request timed out. Please retry.';
    }
    if (lower.contains('401') || lower.contains('403') || lower.contains('unauthorized')) {
      return 'Browser auth failed. Please re-open the session and try again.';
    }
    if (lower.contains('top-level targets')) {
      return 'Browser target was not a top-level page. Re-sync tabs and try again.';
    }
    if (lower.contains('network') || lower.contains('failed to fetch') || lower.contains('xmlhttprequest')) {
      return 'Browser network request failed. Please retry.';
    }
    return raw;
  }

  void _init() {
    // Fetch initial status with retry -- the gateway/OpenClaw pod may not be
    // ready yet immediately after page load.
    _refreshStatusWithRetry();
  }

  Future<void> _refreshStatusWithRetry({int maxRetries = 3}) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (_disposed) return;
      try {
        final client = _ref.read(gatewayClientProvider);
        final result = await client.browserStatus(profile: state.profile);
        if (_disposed) return;

        final running = result['running'] as bool? ??
            result['status'] == 'running' || result['status'] == 'connected';

        state = state.copyWith(
          runState: running ? BrowserRunState.running : BrowserRunState.stopped,
          error: null,
        );

        if (running) {
          await Future.wait([refreshTabs(), _refreshScreenshot()]);
          if (state.autoRefresh && _pollTimer == null) {
            startPolling();
          }
        }
        return; // success
      } catch (e) {
        if (_disposed) return;
        if (attempt < maxRetries) {
          if (kDebugMode) {
            debugPrint('[Browser] status attempt ${attempt + 1} failed, retrying: $e');
          }
          await Future<void>.delayed(Duration(seconds: 1 + attempt));
        } else {
          if (kDebugMode) debugPrint('[Browser] status error after ${maxRetries + 1} attempts: $e');
          state = state.copyWith(
            runState: BrowserRunState.error,
            error: _humanizeError(e),
          );
        }
      }
    }
  }

  /// Start auto-refresh polling.
  void startPolling({Duration interval = const Duration(seconds: 2)}) {
    _pollTimer?.cancel();
    if (_disposed) return;
    state = state.copyWith(autoRefresh: true);
    _pollTimer = Timer.periodic(interval, (_) {
      if (!_disposed &&
          state.autoRefresh &&
          state.runState == BrowserRunState.running) {
        _refreshScreenshot();
      }
    });
  }

  /// Stop auto-refresh polling.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_disposed) state = state.copyWith(autoRefresh: false);
  }

  void toggleAutoRefresh() {
    if (state.autoRefresh) {
      stopPolling();
    } else {
      startPolling();
    }
  }

  /// Fetch browser status and update state.
  Future<void> refreshStatus() async {
    if (_disposed) return;
    try {
      final client = _ref.read(gatewayClientProvider);
      final result = await client.browserStatus(profile: state.profile);
      if (_disposed) return;

      final running = result['running'] as bool? ??
          result['status'] == 'running' || result['status'] == 'connected';

      state = state.copyWith(
        runState: running ? BrowserRunState.running : BrowserRunState.stopped,
        error: null,
      );

      if (running) {
        // Fetch tabs and screenshot in parallel
        await Future.wait([refreshTabs(), _refreshScreenshot()]);
        if (state.autoRefresh && _pollTimer == null) {
          startPolling();
        }
      }
    } catch (e) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Browser] status error: $e');
      state = state.copyWith(
        runState: BrowserRunState.error,
        error: _humanizeError(e),
      );
    }
  }

  /// Start the managed browser.
  Future<void> startBrowser() async {
    if (_disposed) return;
    state = state.copyWith(
      runState: BrowserRunState.starting,
      isLoading: true,
      error: null,
    );
    try {
      final client = _ref.read(gatewayClientProvider);
      await client.browserStart(profile: state.profile);
      if (_disposed) return;

      // Wait a moment for browser to initialize
      await Future.delayed(const Duration(milliseconds: 1500));
      if (_disposed) return;

      state = state.copyWith(
        runState: BrowserRunState.running,
        isLoading: false,
      );
      await Future.wait([refreshTabs(), _refreshScreenshot()]);
      startPolling();
    } catch (e) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Browser] start error: $e');
      state = state.copyWith(
        runState: BrowserRunState.error,
        isLoading: false,
        error: _humanizeError(e),
      );
    }
  }

  /// Stop the managed browser.
  Future<void> stopBrowser() async {
    if (_disposed) return;
    stopPolling();
    state = state.copyWith(isLoading: true);
    try {
      final client = _ref.read(gatewayClientProvider);
      await client.browserStop(profile: state.profile);
      if (_disposed) return;
      state = state.copyWith(
        runState: BrowserRunState.stopped,
        isLoading: false,
        tabs: [],
        screenshotBytes: null,
        snapshotText: null,
        snapshotRefs: [],
        currentUrl: null,
        pageTitle: null,
        activeTabId: null,
      );
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isLoading: false, error: _humanizeError(e));
    }
  }

  /// Refresh the tab list.
  Future<void> refreshTabs() async {
    if (_disposed) return;
    try {
      final client = _ref.read(gatewayClientProvider);
      final result = await client.browserTabs(profile: state.profile);
      if (_disposed) return;

      final rawTabs = result['tabs'] as List<dynamic>? ?? [];
      final parsedTabs = rawTabs
          .whereType<Map<String, dynamic>>()
          .map((t) => BrowserTab.fromJson(t))
          .toList();
      final tabs = parsedTabs.where((t) => t.type == 'page').toList();

      // Find active tab
      final activeTab = tabs.firstWhere(
        (t) => t.active,
        orElse: () => tabs.isNotEmpty
            ? tabs.first
            : const BrowserTab(targetId: '', title: '', url: ''),
      );

      state = state.copyWith(
        tabs: tabs,
        activeTabId: activeTab.targetId.isNotEmpty ? activeTab.targetId : null,
        currentUrl: activeTab.url.isNotEmpty ? activeTab.url : state.currentUrl,
        pageTitle:
            activeTab.title.isNotEmpty ? activeTab.title : state.pageTitle,
        error: tabs.isEmpty && parsedTabs.isNotEmpty
            ? 'No top-level page tabs available (browser is focused on iframe/worker targets).'
            : state.error,
      );
    } catch (e) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Browser] tabs error: $e');
    }
  }

  /// Refresh screenshot from the active tab.
  ///
  /// The browser control API saves screenshots to a file and returns the path.
  /// Nginx serves these files directly from the shared volume at
  /// /__openclaw__/browser-media/<filename>.
  Future<void> _refreshScreenshot() async {
    if (_disposed) return;
    try {
      final client = _ref.read(gatewayClientProvider);

      // Step 1: Take the screenshot via browser control API
      Map<String, dynamic> result;
      try {
        result = await client.browserScreenshot(profile: state.profile);
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('top-level targets')) {
          await refreshTabs();
          if (_disposed) return;
          if (state.tabs.isNotEmpty) {
            await client.browserTabFocus(state.tabs.first.targetId,
                profile: state.profile);
            if (_disposed) return;
          }
          result = await client.browserScreenshot(profile: state.profile);
        } else {
          rethrow;
        }
      }
      if (_disposed) return;

      final screenshotPath = result['path'] as String?;
      if (screenshotPath == null || screenshotPath.isEmpty) return;

      // Step 2: Fetch the screenshot image.
      // In Docker Compose, nginx serves this directly from a shared volume.
      // In K8s, the request goes through gateway-proxy which requires auth.
      // We always send auth headers to work in both environments.
      final filename = screenshotPath.split('/').last;
      final imageUrl =
          '${client.browserBaseUrl}/__openclaw__/browser-media/$filename';

      final imgResp = await safeHttpRequest(
        imageUrl,
        method: 'GET',
        responseType: 'arraybuffer',
        requestHeaders: {
          'Authorization': 'Bearer ${client.auth.token}',
          if (client.openclawId != null) 'X-OpenClaw-Id': client.openclawId!,
        },
        timeout: const Duration(seconds: 15),
      );
      if (_disposed) return;
      if (imgResp.status == 200) {
        final buffer = imgResp.response;
        if (buffer is ByteBuffer) {
          state = state.copyWith(
            screenshotBytes: Uint8List.view(buffer),
            error: null,
            screenshotError: null,
          );
        } else {
          state = state.copyWith(
            screenshotError: 'Invalid screenshot payload from browser endpoint',
          );
        }
      } else {
        state = state.copyWith(
          screenshotError: 'Screenshot fetch failed (${imgResp.status})',
        );
      }
    } catch (e) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Browser] screenshot error: $e');
      state = state.copyWith(
        screenshotError: _humanizeError(e),
        error: _humanizeError(e),
      );
    }
  }

  /// Force a manual screenshot refresh.
  Future<void> manualRefresh() async {
    if (_disposed) return;
    state = state.copyWith(isLoading: true);
    await Future.wait([refreshTabs(), _refreshScreenshot()]);
    if (!_disposed) state = state.copyWith(isLoading: false);
  }

  /// Fetch interactive snapshot with element refs.
  /// Returns number of refs parsed; returns -1 on error.
  Future<int> refreshSnapshot() async {
    if (_disposed) return 0;
    try {
      final client = _ref.read(gatewayClientProvider);
      final result = await client.browserSnapshot(
        profile: state.profile,
        interactive: true,
        compact: true,
      );
      if (_disposed) return 0;

      final text = result['snapshot'] as String? ??
          result['content'] as String? ??
          result['text'] as String? ??
          '';
      final refsObj = result['refs'];
      final refs = <SnapshotRef>[];
      if (refsObj is Map<String, dynamic>) {
        refsObj.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            refs.add(
              SnapshotRef(
                ref: key,
                role: value['role'] as String? ?? '',
                name: value['name'] as String? ?? '',
              ),
            );
          }
        });
      }
      refs.sort((a, b) => a.ref.compareTo(b.ref));
      state = state.copyWith(
        snapshotText: text,
        snapshotRefs: refs,
        error: null,
      );
      return refs.length;
    } catch (e) {
      if (_disposed) return -1;
      if (kDebugMode) debugPrint('[Browser] snapshot error: $e');
      state = state.copyWith(error: _humanizeError(e));
      return -1;
    }
  }

  Future<void> setViewportSize(int width, int height) async {
    if (_disposed) return;
    final safeWidth = width.clamp(320, 3840).toInt();
    final safeHeight = height.clamp(240, 2160).toInt();
    if (safeWidth == state.viewportWidth &&
        safeHeight == state.viewportHeight) {
      return;
    }

    state = state.copyWith(
      viewportWidth: safeWidth,
      viewportHeight: safeHeight,
    );
    if (state.runState != BrowserRunState.running) return;

    try {
      final client = _ref.read(gatewayClientProvider);
      await client.browserResize(safeWidth, safeHeight, profile: state.profile);
    } catch (e) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Browser] resize error: $e');
    }
  }

  /// Navigate the active tab to a URL.
  Future<void> navigate(String url) async {
    if (_disposed) return;
    state = state.copyWith(isLoading: true);
    try {
      final client = _ref.read(gatewayClientProvider);
      // Add https:// if no protocol specified
      final normalizedUrl = url.contains('://') ? url : 'https://$url';
      await client.browserNavigate(normalizedUrl, profile: state.profile);
      if (_disposed) return;
      state = state.copyWith(currentUrl: normalizedUrl, isLoading: false);
      // Refresh after navigation settles
      await Future.delayed(const Duration(milliseconds: 800));
      if (!_disposed) await Future.wait([refreshTabs(), _refreshScreenshot()]);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isLoading: false, error: _humanizeError(e));
    }
  }

  /// Click an element by snapshot ref.
  Future<void> clickRef(String ref) async {
    if (_disposed) return;
    try {
      final client = _ref.read(gatewayClientProvider);
      await client.browserAct(kind: 'click', ref: ref, profile: state.profile);
      if (_disposed) return;
      // Refresh after click settles
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_disposed) await Future.wait([refreshTabs(), _refreshScreenshot()]);
    } catch (e) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Browser] click error: $e');
      state = state.copyWith(error: _humanizeError(e));
    }
  }

  /// Type text into a focused element.
  Future<void> typeText(String ref, String text, {bool submit = false}) async {
    if (_disposed) return;
    try {
      final client = _ref.read(gatewayClientProvider);
      await client.browserAct(
        kind: 'type',
        ref: ref,
        text: text,
        submit: submit,
        profile: state.profile,
      );
      if (_disposed) return;
      await Future.delayed(const Duration(milliseconds: 300));
      if (!_disposed) await _refreshScreenshot();
    } catch (e) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Browser] type error: $e');
    }
  }

  /// Press a key (e.g. Enter, Escape, Tab).
  Future<void> pressKey(String key) async {
    if (_disposed) return;
    try {
      final client = _ref.read(gatewayClientProvider);
      await client.browserAct(kind: 'press', text: key, profile: state.profile);
      if (_disposed) return;
      await Future.delayed(const Duration(milliseconds: 300));
      if (!_disposed) await _refreshScreenshot();
    } catch (e) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Browser] press error: $e');
    }
  }

  /// Open a new tab.
  Future<void> openTab([String url = 'about:blank']) async {
    if (_disposed) return;
    try {
      final client = _ref.read(gatewayClientProvider);
      await client.browserTabOpen(url, profile: state.profile);
      if (_disposed) return;
      await refreshTabs();
      await _refreshScreenshot();
    } catch (e) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Browser] openTab error: $e');
    }
  }

  /// Focus a tab by targetId.
  Future<void> focusTab(String targetId) async {
    if (_disposed) return;
    try {
      final client = _ref.read(gatewayClientProvider);
      await client.browserTabFocus(targetId, profile: state.profile);
      if (_disposed) return;
      state = state.copyWith(activeTabId: targetId);
      await refreshTabs();
      await _refreshScreenshot();
    } catch (e) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Browser] focusTab error: $e');
    }
  }

  /// Close a tab by targetId.
  Future<void> closeTab(String targetId) async {
    if (_disposed) return;
    try {
      final client = _ref.read(gatewayClientProvider);
      await client.browserTabClose(targetId, profile: state.profile);
      if (_disposed) return;
      await refreshTabs();
      await _refreshScreenshot();
    } catch (e) {
      if (_disposed) return;
      if (kDebugMode) debugPrint('[Browser] closeTab error: $e');
    }
  }

  /// Go back in history.
  Future<void> goBack() async {
    if (_disposed) return;
    try {
      await pressKey('Alt+ArrowLeft');
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_disposed) await Future.wait([refreshTabs(), _refreshScreenshot()]);
    } catch (e) {
      if (_disposed) return;
    }
  }

  /// Go forward in history.
  Future<void> goForward() async {
    if (_disposed) return;
    try {
      await pressKey('Alt+ArrowRight');
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_disposed) await Future.wait([refreshTabs(), _refreshScreenshot()]);
    } catch (e) {
      if (_disposed) return;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

final browserProvider = StateNotifierProvider<BrowserNotifier, BrowserState>((
  ref,
) {
  return BrowserNotifier(ref);
});
