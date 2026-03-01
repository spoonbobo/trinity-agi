import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/providers.dart';
import '../../models/ws_frame.dart';
import '../../main.dart' show languageProvider;

class AppNotification {
  final String id;
  final String type; // 'cron', 'hook', 'webhook', 'approval', 'connection', 'error'
  final String title;
  final String body;
  final DateTime timestamp;
  bool read;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.read = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'type': type, 'title': title,
    'body': body, 'timestamp': timestamp.toIso8601String(),
    'read': read,
  };

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as String? ?? '',
    type: json['type'] as String? ?? 'system',
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    read: json['read'] as bool? ?? false,
  );
}

const _storageKey = 'trinity_notifications';
const _maxNotifications = 100;

class NotificationState extends ChangeNotifier {
  final List<AppNotification> _items = [];

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _items.where((n) => !n.read).length;

  NotificationState() {
    _restoreFromStorage();
  }

  void _restoreFromStorage() {
    final stored = html.window.localStorage[_storageKey];
    if (stored != null && stored.isNotEmpty) {
      try {
        final list = jsonDecode(stored) as List;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            _items.add(AppNotification.fromJson(item));
          }
        }
      } catch (_) {}
    }
  }

  void _persistToStorage() {
    final json = _items.map((n) => n.toJson()).toList();
    html.window.localStorage[_storageKey] = jsonEncode(json);
  }

  void add(AppNotification notification) {
    _items.insert(0, notification);
    if (_items.length > _maxNotifications) {
      _items.removeRange(_maxNotifications, _items.length);
    }
    _persistToStorage();
    notifyListeners();
  }

  void markRead(String id) {
    final item = _items.where((n) => n.id == id).firstOrNull;
    if (item != null && !item.read) {
      item.read = true;
      _persistToStorage();
      notifyListeners();
    }
  }

  void markAllRead() {
    for (final item in _items) {
      item.read = true;
    }
    _persistToStorage();
    notifyListeners();
  }

  void clearAll() {
    _items.clear();
    _persistToStorage();
    notifyListeners();
  }

  void dismiss(String id) {
    _items.removeWhere((n) => n.id == id);
    _persistToStorage();
    notifyListeners();
  }

  /// Process a gateway event and create notifications for relevant events.
  void processEvent(WsEvent event) {
    final payload = event.payload;

    if (event.event == 'exec.approval.requested') {
      add(AppNotification(
        id: 'approval-${DateTime.now().millisecondsSinceEpoch}',
        type: 'approval',
        title: 'Exec Approval Required',
        body: payload['command']?.toString() ?? 'A command needs your approval',
        timestamp: DateTime.now(),
      ));
    }
  }
}

final notificationProvider = ChangeNotifierProvider<NotificationState>((ref) {
  return NotificationState();
});

class NotificationCenter extends ConsumerWidget {
  const NotificationCenter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final language = ref.watch(languageProvider);
    final state = ref.watch(notificationProvider);

    return Container(
      width: 320,
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        borderRadius: kShellBorderRadius,
        color: t.surfaceBase,
        border: Border.all(color: t.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Text(tr(language, 'notifications'),
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted)),
                const Spacer(),
                if (state.items.isNotEmpty) ...[
                  GestureDetector(
                    onTap: () => ref.read(notificationProvider).markAllRead(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text('mark read',
                        style: TextStyle(fontSize: 9, color: t.accentPrimary)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => ref.read(notificationProvider).clearAll(),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text(tr(language, 'clear_all'),
                        style: TextStyle(fontSize: 9, color: t.fgMuted)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Items
          if (state.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.notifications_none, size: 20, color: t.fgPlaceholder),
                  const SizedBox(height: 6),
                  Text(tr(language, 'no_notifications'),
                    style: TextStyle(fontSize: 10, color: t.fgPlaceholder)),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 2),
                itemCount: state.items.length,
                itemBuilder: (context, index) {
                  final item = state.items[index];
                  return _NotificationItem(
                    notification: item,
                    tokens: t,
                    theme: theme,
                    onDismiss: () =>
                      ref.read(notificationProvider).dismiss(item.id),
                    onTap: () =>
                      ref.read(notificationProvider).markRead(item.id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationItem extends StatefulWidget {
  final AppNotification notification;
  final ShellTokens tokens;
  final ThemeData theme;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _NotificationItem({
    required this.notification,
    required this.tokens,
    required this.theme,
    required this.onDismiss,
    required this.onTap,
  });

  @override
  State<_NotificationItem> createState() => _NotificationItemState();
}

class _NotificationItemState extends State<_NotificationItem> {
  bool _hovering = false;

  IconData _iconForType(String type) {
    switch (type) {
      case 'cron': return Icons.schedule;
      case 'hook': return Icons.webhook;
      case 'webhook': return Icons.link;
      case 'approval': return Icons.gavel;
      case 'connection': return Icons.wifi;
      case 'error': return Icons.error_outline;
      default: return Icons.notifications_none;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final n = widget.notification;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: n.read ? Colors.transparent : t.accentPrimary.withOpacity(0.03),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconForType(n.type), size: 12,
                color: n.read ? t.fgMuted : t.accentPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.title,
                      style: widget.theme.textTheme.labelSmall?.copyWith(
                        color: n.read ? t.fgTertiary : t.fgPrimary,
                        fontSize: 10,
                      )),
                    if (n.body.isNotEmpty)
                      Text(n.body,
                        style: TextStyle(fontSize: 9, color: t.fgMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    Text(_timeAgo(n.timestamp),
                      style: TextStyle(fontSize: 8, color: t.fgDisabled)),
                  ],
                ),
              ),
              if (_hovering)
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(Icons.close, size: 10, color: t.fgMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
