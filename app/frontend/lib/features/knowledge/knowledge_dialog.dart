import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:force_graph/force_graph.dart';

import '../../core/theme.dart';
import '../../main.dart' show authClientProvider;

class KnowledgeDialog extends ConsumerStatefulWidget {
  const KnowledgeDialog({super.key});

  @override
  ConsumerState<KnowledgeDialog> createState() => _KnowledgeDialogState();
}

class _KnowledgeDialogState extends ConsumerState<KnowledgeDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _graph;
  List<dynamic> _labels = const [];

  final TextEditingController _labelFilterCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  Timer? _labelSearchDebounce;

  String? _selectedLabel;
  String _labelFilter = '';
  String _searchQuery = '';
  String _entityKindFilter = 'all';
  int _maxDepth = 3;
  int _maxNodes = 500;
  bool _neighborsOnly = false;
  bool _searchingRemote = false;
  bool _sidePanelCollapsed = false;
  bool _labelSearching = false;

  String? _selectedNodeId;
  List<Map<String, dynamic>> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    _labelFilterCtrl.addListener(() {
      setState(() => _labelFilter = _labelFilterCtrl.text.trim());
      _debouncedLabelSearch();
    });
    _searchCtrl.addListener(() {
      _searchQuery = _searchCtrl.text.trim();
      _refreshLocalSearch();
      _debouncedRemoteSearch();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _labelSearchDebounce?.cancel();
    _labelFilterCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _loadWithParams(label: _selectedLabel);
  }

  Future<void> _loadWithParams({String? label}) async {
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'no active claw selected';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final query = <String, String>{
        if (label != null && label.isNotEmpty) 'label': label,
        'max_depth': _maxDepth.toString(),
        'max_nodes': _maxNodes.toString(),
      };
      final qs = query.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      final url =
          '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-graph${qs.isEmpty ? '' : '?$qs'}';

      final request = html.HttpRequest();
      request.open('GET', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      final response = await _sendRequest(request);
      final decoded = jsonDecode(response);
      if (!mounted) return;

      setState(() {
        final data = Map<String, dynamic>.from(decoded as Map);
        _labels = (data['labels'] as List?) ?? const [];
        _selectedLabel = data['selectedLabel']?.toString();
        _graph = Map<String, dynamic>.from((data['graph'] as Map?) ?? const {});
      });

      _refreshLocalSearch();
      _ensureSelectedNodeExists();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _remoteSearch() async {
    final query = _searchQuery.trim();
    if (query.length < 2) return;
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) return;

    setState(() => _searchingRemote = true);
    try {
      final params = <String, String>{
        'q': query,
        if (_selectedLabel != null && _selectedLabel!.isNotEmpty) 'label': _selectedLabel!,
        'max_depth': _maxDepth.toString(),
        'max_nodes': _maxNodes.toString(),
        'limit': '30',
      };
      final qs = params.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');

      final url = '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-search?$qs';
      final request = html.HttpRequest();
      request.open('GET', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      final response = await _sendRequest(request);
      final decoded = Map<String, dynamic>.from(jsonDecode(response) as Map);
      final remote = (decoded['results'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      if (!mounted) return;
      final merged = <String, Map<String, dynamic>>{
        for (final r in _searchResults) (r['id'] ?? '').toString(): r,
      };
      for (final r in remote) {
        final id = (r['id'] ?? '').toString();
        if (id.isEmpty) continue;
        merged[id] = {
          ...r,
          'score': (r['score'] as num?)?.toDouble() ?? 0.0,
          'source': 'remote',
        };
      }
      final items = merged.values.toList()
        ..sort((a, b) =>
            ((b['score'] as num?) ?? 0).compareTo((a['score'] as num?) ?? 0));

      setState(() {
        _searchResults = items.take(60).toList();
      });
    } catch (_) {
      // Keep local results if remote search fails.
    } finally {
      if (mounted) setState(() => _searchingRemote = false);
    }
  }

  void _debouncedRemoteSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), _remoteSearch);
  }

  void _debouncedLabelSearch() {
    final q = _labelFilter.trim();
    _labelSearchDebounce?.cancel();
    if (q.isEmpty) return;
    _labelSearchDebounce = Timer(const Duration(milliseconds: 260), _remoteLabelSearch);
  }

  Future<void> _remoteLabelSearch() async {
    final q = _labelFilter.trim();
    if (q.length < 2) return;
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) return;

    setState(() => _labelSearching = true);
    try {
      final url =
          '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-label-search?q=${Uri.encodeQueryComponent(q)}&limit=80';
      final request = html.HttpRequest();
      request.open('GET', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      final response = await _sendRequest(request);
      final decoded = Map<String, dynamic>.from(jsonDecode(response) as Map);
      final labels = (decoded['labels'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
      if (!mounted) return;
      if (labels.isNotEmpty) {
        setState(() {
          _labels = labels;
        });
      }
    } catch (_) {
      // Keep local list if remote label search fails.
    } finally {
      if (mounted) setState(() => _labelSearching = false);
    }
  }

  Future<String> _sendRequest(html.HttpRequest request) {
    final completer = Completer<String>();
    request.onLoad.listen((_) {
      final status = request.status ?? 0;
      if (status >= 200 && status < 300) {
        completer.complete(request.responseText ?? '{}');
      } else {
        completer.completeError('HTTP $status: ${request.responseText}');
      }
    });
    request.onError.listen((_) => completer.completeError('request failed'));
    request.send();
    return completer.future;
  }

  List<String> get _filteredLabels {
    if (_labelFilter.isEmpty) return _labels.map((e) => e.toString()).toList();
    final lower = _labelFilter.toLowerCase();
    return _labels
        .map((e) => e.toString())
        .where((l) => l.toLowerCase().contains(lower))
        .toList();
  }

  List<Map<String, dynamic>> get _graphNodes {
    return (_graph?['nodes'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const [];
  }

  List<Map<String, dynamic>> get _graphEdges {
    return (_graph?['edges'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const [];
  }

  Set<String> get _entityKinds {
    final out = <String>{};
    for (final n in _graphNodes) {
      final kind = ((n['entity_type'] ?? n['kind']) ?? 'unknown').toString();
      out.add(kind);
    }
    return out;
  }

  ({List<Map<String, dynamic>> nodes, List<Map<String, dynamic>> edges})
      _computeVisibleGraph() {
    var nodes = _graphNodes;
    var edges = _graphEdges;

    if (_entityKindFilter != 'all') {
      nodes = nodes
          .where((n) =>
              (((n['entity_type'] ?? n['kind']) ?? 'unknown').toString() ==
                  _entityKindFilter))
          .toList();
      final allowed = nodes
          .map((n) => (n['id'] ?? n['identity'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      edges = edges
          .where((e) =>
              allowed.contains((e['source'] ?? '').toString()) &&
              allowed.contains((e['target'] ?? '').toString()))
          .toList();
    }

    if (_neighborsOnly && _selectedNodeId != null && _selectedNodeId!.isNotEmpty) {
      final center = _selectedNodeId!;
      final hasCenter = nodes.any(
        (n) => (n['id'] ?? n['identity'] ?? '').toString() == center,
      );
      if (!hasCenter) {
        return (nodes: nodes, edges: edges);
      }
      final keep = <String>{center};
      for (final e in edges) {
        final s = (e['source'] ?? '').toString();
        final t = (e['target'] ?? '').toString();
        if (s == center) keep.add(t);
        if (t == center) keep.add(s);
      }
      nodes = nodes
          .where((n) => keep.contains((n['id'] ?? n['identity'] ?? '').toString()))
          .toList();
      edges = edges
          .where((e) {
            final s = (e['source'] ?? '').toString();
            final t = (e['target'] ?? '').toString();
            return keep.contains(s) && keep.contains(t);
          })
          .toList();
    }

    return (nodes: nodes, edges: edges);
  }

  void _refreshLocalSearch() {
    final edges = _graphEdges;
    final degree = <String, int>{};
    for (final e in edges) {
      final s = (e['source'] ?? '').toString();
      final t = (e['target'] ?? '').toString();
      if (s.isNotEmpty) degree[s] = (degree[s] ?? 0) + 1;
      if (t.isNotEmpty) degree[t] = (degree[t] ?? 0) + 1;
    }

    final q = _searchQuery.trim().toLowerCase();
    final scored = <Map<String, dynamic>>[];
    for (final n in _graphNodes) {
      final id = (n['id'] ?? n['identity'] ?? '').toString();
      if (id.isEmpty) continue;
      final labels = (n['labels'] as List?)?.map((e) => e.toString()).toList() ?? const [];
      final label = (labels.isNotEmpty ? labels.first : (n['label'] ?? id)).toString();
      final kind = ((n['entity_type'] ?? n['kind']) ?? 'unknown').toString();
      final preview = ((n['properties'] as Map?)?['description'] ??
              (n['metadata'] as Map?)?['preview'] ??
              '')
          .toString();

      var score = 0.0;
      if (q.isNotEmpty) {
        final candidates = [id, label, kind, preview];
        for (final c in candidates) {
          final v = c.toLowerCase();
          if (v == q) {
            score += 100;
          } else if (v.startsWith(q)) {
            score += 60;
          } else if (v.contains(q)) {
            score += 25;
          }
        }
      } else {
        score = (degree[id] ?? 0).toDouble();
      }
      if (score > 0) {
        score += (degree[id] ?? 0).clamp(0, 15);
        scored.add({
          'id': id,
          'label': label,
          'kind': kind,
          'preview': preview,
          'degree': degree[id] ?? 0,
          'score': score,
          'source': 'local',
        });
      }
    }

    scored.sort((a, b) =>
        ((b['score'] as num?) ?? 0).compareTo((a['score'] as num?) ?? 0));

    setState(() {
      _searchResults = scored.take(60).toList();
    });
  }

  void _ensureSelectedNodeExists() {
    if (_selectedNodeId == null || _selectedNodeId!.isEmpty) return;
    final exists = _graphNodes.any((n) =>
        (n['id'] ?? n['identity'] ?? '').toString() == _selectedNodeId);
    if (!exists) {
      setState(() {
        _selectedNodeId = null;
        _neighborsOnly = false;
      });
    }
  }

  void _selectNodeFromResult(String id) {
    if (id.isEmpty) return;
    final visibleNow = _computeVisibleGraph();
    final existsInVisible = visibleNow.nodes.any(
      (n) => (n['id'] ?? n['identity'] ?? '').toString() == id,
    );

    setState(() {
      _selectedNodeId = id;
      if (!existsInVisible) {
        _neighborsOnly = false;
        _entityKindFilter = 'all';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final visible = _computeVisibleGraph();
    final isTruncated = _graph?['is_truncated'] == true;

    final selectedNode = _selectedNodeId == null
        ? null
        : _graphNodes.cast<Map<String, dynamic>?>().firstWhere(
              (n) => (n?['id'] ?? n?['identity'] ?? '').toString() == _selectedNodeId,
              orElse: () => null,
            );

    return Dialog(
      backgroundColor: t.surfaceBase,
      shape: RoundedRectangleBorder(
        borderRadius: kShellBorderRadius,
        side: BorderSide(color: t.border, width: 0.5),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.92,
        height: MediaQuery.of(context).size.height * 0.9,
        constraints: const BoxConstraints(maxWidth: 1380, maxHeight: 920),
        child: Column(
          children: [
            _buildHeader(context, t, theme, visible.nodes.length, visible.edges.length),
            _buildControls(context, t, theme),
            Expanded(
              child: _loading
                  ? Center(
                      child: Text(
                        'loading graph...',
                        style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodyMedium?.copyWith(color: t.statusError),
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 7,
                                child: _KnowledgeGraphCanvas(
                                  nodes: visible.nodes,
                                  edges: visible.edges,
                                  isTruncated: isTruncated,
                                ),
                              ),
                              Container(width: 0.5, color: t.border),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                width: _sidePanelCollapsed ? 36 : 280,
                                child: _sidePanelCollapsed
                                    ? _buildSidePanelCollapsed(context, t)
                                    : _buildSidePanel(context, t, theme, selectedNode),
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ShellTokens t,
    ThemeData theme,
    int nodeCount,
    int edgeCount,
  ) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Text(
            'knowledge graph',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: t.fgPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$nodeCount nodes · $edgeCount edges',
            style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _loading ? null : _load,
            child: Text(
              _loading ? 'loading...' : 'refresh',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _loading ? t.fgDisabled : t.accentPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => setState(() => _sidePanelCollapsed = !_sidePanelCollapsed),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(
                _sidePanelCollapsed ? Icons.chevron_left : Icons.chevron_right,
                size: 14,
                color: t.fgMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(Icons.close, size: 14, color: t.fgMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context, ShellTokens t, ThemeData theme) {
    final labels = _filteredLabels;
    final kinds = ['all', ..._entityKinds.toList()..sort()];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 170,
            child: _compactInput(
              controller: _labelFilterCtrl,
              hint: 'filter labels',
              t: t,
              theme: theme,
            ),
          ),
          if (_labelSearching)
            Text(
              'labels...',
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
            ),
          SizedBox(
            width: 200,
            child: _compactDropdown<String>(
              value: labels.contains(_selectedLabel)
                  ? _selectedLabel
                  : (labels.isNotEmpty ? labels.first : null),
              items: labels,
              onChanged: _loading
                  ? null
                  : (v) {
                      if (v == null) return;
                      _loadWithParams(label: v);
                    },
              t: t,
              theme: theme,
            ),
          ),
          SizedBox(
            width: 66,
            child: _compactDropdown<int>(
              value: _maxDepth,
              items: const [1, 2, 3, 4, 5],
              onChanged: _loading
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _maxDepth = v);
                      _load();
                    },
              t: t,
              theme: theme,
            ),
          ),
          SizedBox(
            width: 88,
            child: _compactDropdown<int>(
              value: _maxNodes,
              items: const [100, 250, 500, 1000, 1500],
              onChanged: _loading
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _maxNodes = v);
                      _load();
                    },
              t: t,
              theme: theme,
            ),
          ),
          SizedBox(
            width: 220,
            child: _compactInput(
              controller: _searchCtrl,
              hint: 'search nodes (label/id/kind)',
              t: t,
              theme: theme,
            ),
          ),
          SizedBox(
            width: 120,
            child: _compactDropdown<String>(
              value: kinds.contains(_entityKindFilter) ? _entityKindFilter : 'all',
              items: kinds,
              onChanged: (v) {
                if (v == null) return;
                setState(() => _entityKindFilter = v);
                _refreshLocalSearch();
              },
              t: t,
              theme: theme,
            ),
          ),
          if (_searchingRemote)
            Text(
              'searching...',
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildSidePanel(
    BuildContext context,
    ShellTokens t,
    ThemeData theme,
    Map<String, dynamic>? selectedNode,
  ) {
    final preview = ((selectedNode?['properties'] as Map?)?['description'] ??
            (selectedNode?['metadata'] as Map?)?['preview'] ??
            '')
        .toString();
    final kind = ((selectedNode?['entity_type'] ?? selectedNode?['kind']) ?? 'node').toString();
    final label = (((selectedNode?['labels'] as List?)?.first) ??
            selectedNode?['label'] ??
            selectedNode?['id'] ??
            '')
        .toString();

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _searchQuery.isEmpty ? 'top nodes' : 'search results (${_searchResults.length})',
            style: theme.textTheme.bodySmall?.copyWith(color: t.fgSecondary),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: t.border, width: 0.5),
                borderRadius: kShellBorderRadiusSm,
              ),
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final item = _searchResults[index];
                  final id = (item['id'] ?? '').toString();
                  final isSelected = id == _selectedNodeId;
                  return GestureDetector(
                    onTap: () => _selectNodeFromResult(id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: t.border, width: 0.5),
                        ),
                        color: isSelected
                            ? t.accentPrimary.withOpacity(0.12)
                            : Colors.transparent,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (item['label'] ?? id).toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isSelected ? t.fgPrimary : t.fgSecondary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${item['kind'] ?? 'node'} · score ${(item['score'] as num?)?.toStringAsFixed(0) ?? '0'} · deg ${item['degree'] ?? 0}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: t.fgMuted,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'node inspector',
            style: theme.textTheme.bodySmall?.copyWith(color: t.fgSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _presetChip(context, t, theme, 'speed', onTap: () {
                setState(() {
                  _maxDepth = 2;
                  _maxNodes = 250;
                });
                _load();
              }),
              _presetChip(context, t, theme, 'detail', onTap: () {
                setState(() {
                  _maxDepth = 4;
                  _maxNodes = 1000;
                });
                _load();
              }),
              _presetChip(
                context,
                t,
                theme,
                _neighborsOnly ? 'neighbors: on' : 'neighbors: off',
                onTap: () => setState(() => _neighborsOnly = !_neighborsOnly),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 130),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: t.border, width: 0.5),
              borderRadius: kShellBorderRadiusSm,
              color: t.surfaceCard,
            ),
            child: selectedNode == null
                ? Text(
                    'select a search result to inspect',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: t.fgPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$kind · ${(selectedNode['id'] ?? '').toString()}',
                        style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        SelectableText(
                          preview,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: t.fgSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidePanelCollapsed(BuildContext context, ShellTokens t) {
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.border, width: 0.5)),
      ),
      child: Center(
        child: GestureDetector(
          onTap: () => setState(() => _sidePanelCollapsed = false),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Icon(Icons.chevron_left, size: 16, color: t.fgMuted),
          ),
        ),
      ),
    );
  }

  Widget _compactInput({
    required TextEditingController controller,
    required String hint,
    required ShellTokens t,
    required ThemeData theme,
  }) {
    return TextField(
      controller: controller,
      style: theme.textTheme.labelSmall?.copyWith(color: t.fgPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: t.fgPlaceholder, fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        enabledBorder: OutlineInputBorder(
          borderRadius: kShellBorderRadiusSm,
          borderSide: BorderSide(color: t.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: kShellBorderRadiusSm,
          borderSide: BorderSide(color: t.accentSecondary, width: 0.7),
        ),
      ),
    );
  }

  Widget _compactDropdown<T>({
    required T? value,
    required List<T> items,
    required ValueChanged<T?>? onChanged,
    required ShellTokens t,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: t.border, width: 0.5),
        borderRadius: kShellBorderRadiusSm,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          menuMaxHeight: 280,
          dropdownColor: t.surfaceCard,
          iconEnabledColor: t.fgMuted,
          style: theme.textTheme.labelSmall?.copyWith(color: t.fgPrimary),
          selectedItemBuilder: (context) => items
              .map(
                (v) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    v.toString(),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgPrimary),
                  ),
                ),
              )
              .toList(),
          items: items
              .map((v) => DropdownMenuItem<T>(
                    value: v,
                    child: Text(
                      v.toString(),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: t.fgPrimary),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _presetChip(
    BuildContext context,
    ShellTokens t,
    ThemeData theme,
    String label, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: kShellBorderRadiusSm,
            border: Border.all(color: t.border, width: 0.5),
            color: t.surfaceBase,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted, fontSize: 10),
          ),
        ),
      ),
    );
  }
}

class _KnowledgeGraphCanvas extends StatefulWidget {
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> edges;
  final bool isTruncated;

  const _KnowledgeGraphCanvas({
    required this.nodes,
    required this.edges,
    this.isTruncated = false,
  });

  @override
  State<_KnowledgeGraphCanvas> createState() => _KnowledgeGraphCanvasState();
}

class _KnowledgeGraphCanvasState extends State<_KnowledgeGraphCanvas> {
  late ForceGraphController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
  }

  @override
  void didUpdateWidget(covariant _KnowledgeGraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodes != widget.nodes || oldWidget.edges != widget.edges) {
      _controller = _buildController();
    }
  }

  ForceGraphController _buildController() {
    final forceNodes = _toForceGraphNodes(widget.nodes, widget.edges);
    return ForceGraphController(nodes: forceNodes);
  }

  List<ForceGraphNodeData> _toForceGraphNodes(
    List<Map<String, dynamic>> nodes,
    List<Map<String, dynamic>> edges,
  ) {
    final nodeMap = <String, Map<String, dynamic>>{};
    for (final n in nodes) {
      final id = (n['id'] ?? n['identity'] ?? '').toString();
      if (id.isNotEmpty) nodeMap[id] = Map<String, dynamic>.from(n);
    }
    for (final e in edges) {
      final src = (e['source'] ?? '').toString();
      final tgt = (e['target'] ?? '').toString();
      if (src.isNotEmpty && !nodeMap.containsKey(src)) {
        nodeMap[src] = {'id': src, 'label': src, 'kind': 'unknown'};
      }
      if (tgt.isNotEmpty && !nodeMap.containsKey(tgt)) {
        nodeMap[tgt] = {'id': tgt, 'label': tgt, 'kind': 'unknown'};
      }
    }

    final outgoing = <String, List<ForceGraphEdgeData>>{};
    for (final e in edges) {
      final src = (e['source'] ?? '').toString();
      final tgt = (e['target'] ?? '').toString();
      if (src.isEmpty || tgt.isEmpty) continue;
      outgoing.putIfAbsent(src, () => []).add(
            ForceGraphEdgeData.from(
              source: src,
              target: tgt,
              similarity: 1.0,
              data: e,
            ),
          );
    }

    return nodeMap.entries.map((entry) {
      final id = entry.key;
      final raw = entry.value;
      final kind = ((raw['entity_type'] ?? raw['kind']) ?? 'node').toString();
      final label = ((raw['labels'] as List?)?.first ?? raw['label'] ?? raw['id'] ?? id)
          .toString();
      return ForceGraphNodeData.from(
        id: id,
        edges: outgoing[id] ?? [],
        title: label,
        data: raw,
        removable: false,
        radius: kind == 'chunk' ? 0.15 : 0.2,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    if (widget.nodes.isEmpty && widget.edges.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined, size: 44, color: t.fgMuted),
            const SizedBox(height: 10),
            Text(
              'no graph data',
              style: theme.textTheme.bodyMedium?.copyWith(color: t.fgMuted),
            ),
            Text(
              'adjust filters or ingest more documents',
              style: theme.textTheme.labelSmall?.copyWith(color: t.fgPlaceholder),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isTruncated)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: t.statusWarning.withOpacity(0.15),
              border: Border.all(color: t.statusWarning.withOpacity(0.4), width: 0.5),
              borderRadius: kShellBorderRadiusSm,
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: t.statusWarning),
                const SizedBox(width: 6),
                Text(
                  'graph truncated — raise max nodes for broader context',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.statusWarning),
                ),
              ],
            ),
          ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kShellRadius),
            child: ForceGraphWidget(
              controller: _controller,
              showControlBar: true,
              defaultControlBarForegroundColor: t.fgPrimary,
              defaultControlBarBackgroundColor: t.surfaceCard,
              nodeTooltipBuilder: (context, node) {
                final raw = node.data.data as Map<String, dynamic>?;
                if (raw == null) return Text(node.data.title);
                final kind = ((raw['entity_type'] ?? raw['kind']) ?? 'node').toString();
                final label =
                    ((raw['labels'] as List?)?.first ?? raw['label'] ?? raw['id'] ?? '').toString();
                final preview = ((raw['properties'] as Map?)?['description'] ??
                        (raw['metadata'] as Map?)?['preview'] ??
                        '')
                    .toString();
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$kind: $label', style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(preview, style: TextStyle(fontSize: 11, color: t.fgSecondary)),
                      ],
                    ],
                  ),
                );
              },
              edgeTooltipBuilder: (context, edge) {
                final raw = edge.data.data as Map<String, dynamic>?;
                final kind = raw?['kind'] ?? 'link';
                return Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text('${edge.data.source} → ${edge.data.target} ($kind)'),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
