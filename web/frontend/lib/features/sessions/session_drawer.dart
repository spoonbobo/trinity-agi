import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../main.dart' show languageProvider;

/// Strip the `agent:<agentId>:` prefix that OpenClaw stores internally.
/// The WS methods `chat.send` / `chat.history` expect the short key.
String _normalizeKey(String key) {
  return key.replaceFirst(RegExp(r'^agent:[^:]+:'), '');
}

class _SessionEntry {
  final String key;
  final int updatedAt;
  _SessionEntry(this.key, this.updatedAt);
}

class SessionDrawer extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onSessionChanged;

  const SessionDrawer({
    super.key,
    required this.onClose,
    required this.onSessionChanged,
  });

  @override
  ConsumerState<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends ConsumerState<SessionDrawer> {
  List<String> _sessionKeys = ['main'];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchSessions();
  }

  /// Fetch sessions from the gateway -- single source of truth.
  /// Sorted by updatedAt descending (newest first), main pinned at top.
  Future<void> _fetchSessions() async {
    setState(() => _loading = true);
    try {
      final client = ref.read(gatewayClientProvider);
      final response = await client.listSessions();
      if (response.ok && response.payload != null) {
        final sessions = response.payload!['sessions'];
        if (sessions is List) {
          final entries = <_SessionEntry>[];
          for (final s in sessions) {
            if (s is Map<String, dynamic>) {
              final raw = s['key'] as String? ?? s['id'] as String? ?? '';
              final updatedAt = s['updatedAt'] as num? ?? 0;
              if (raw.isNotEmpty) {
                entries.add(_SessionEntry(_normalizeKey(raw), updatedAt.toInt()));
              }
            } else if (s is String && s.isNotEmpty) {
              entries.add(_SessionEntry(_normalizeKey(s), 0));
            }
          }
          // Sort newest first
          entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

          // Build key list: main pinned at top
          final keys = <String>['main'];
          for (final e in entries) {
            if (e.key != 'main' && !keys.contains(e.key)) keys.add(e.key);
          }
          // Keep active session even if server doesn't know it yet
          final active = ref.read(activeSessionProvider);
          if (!keys.contains(active)) keys.insert(1, active);

          if (mounted) setState(() => _sessionKeys = keys);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Sessions] Failed to fetch sessions: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Create a new session locally and switch to it immediately.
  /// The gateway creates the session lazily on the first chat.send.
  void _createNewSession() {
    final key = 'session-${const Uuid().v4().substring(0, 8)}';
    setState(() {
      // Insert right after main
      final idx = _sessionKeys.indexOf('main');
      _sessionKeys.insert(idx + 1, key);
    });
    ref.read(activeSessionProvider.notifier).state = key;
    widget.onSessionChanged();
  }

  void _selectSession(String key) {
    ref.read(activeSessionProvider.notifier).state = key;
    widget.onSessionChanged();
    widget.onClose();
  }

  void _deleteSession(String key) {
    if (key == 'main') return;
    setState(() => _sessionKeys.remove(key));
    if (ref.read(activeSessionProvider) == key) {
      ref.read(activeSessionProvider.notifier).state = 'main';
      widget.onSessionChanged();
    }
    // Notify the gateway so the session is actually removed server-side.
    final client = ref.read(gatewayClientProvider);
    client.deleteSession(key).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final language = ref.watch(languageProvider);
    final activeKey = ref.watch(activeSessionProvider);

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: t.surfaceBase,
        border: Border(right: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Text(tr(language, 'sessions_label'),
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted)),
                const Spacer(),
                GestureDetector(
                  onTap: _createNewSession,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(Icons.add, size: 14, color: t.fgMuted),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onClose,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(Icons.close, size: 14, color: t.fgMuted),
                  ),
                ),
              ],
            ),
          ),
          // Session list
          Expanded(
            child: _loading
                ? Center(child: SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: t.accentPrimary)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _sessionKeys.length,
                    itemBuilder: (context, index) {
                      final key = _sessionKeys[index];
                      final isActive = key == activeKey;
                      return _SessionItem(
                        name: key,
                        isActive: isActive,
                        canDelete: key != 'main',
                        onTap: () => _selectSession(key),
                        onDelete: () => _deleteSession(key),
                        tokens: t,
                        theme: theme,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionItem extends StatefulWidget {
  final String name;
  final bool isActive;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final ShellTokens tokens;
  final ThemeData theme;

  const _SessionItem({
    required this.name,
    required this.isActive,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
    required this.tokens,
    required this.theme,
  });

  @override
  State<_SessionItem> createState() => _SessionItemState();
}

class _SessionItemState extends State<_SessionItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: widget.isActive
              ? t.accentPrimary.withOpacity(0.08)
              : _hovering
                  ? t.surfaceCard
                  : Colors.transparent,
          child: Row(
            children: [
              Icon(
                widget.isActive ? Icons.chat_bubble : Icons.chat_bubble_outline,
                size: 12,
                color: widget.isActive ? t.accentPrimary : t.fgMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.name,
                  style: widget.theme.textTheme.labelSmall?.copyWith(
                    color: widget.isActive ? t.accentPrimary : t.fgSecondary,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.canDelete && _hovering)
                GestureDetector(
                  onTap: widget.onDelete,
                  child: Icon(Icons.close, size: 12, color: t.fgMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
