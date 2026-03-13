import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/http_utils.dart';
import '../../core/theme.dart';
import '../../main.dart' show authClientProvider;

class KnowledgeDialog extends ConsumerStatefulWidget {
  const KnowledgeDialog({super.key});

  @override
  ConsumerState<KnowledgeDialog> createState() => _KnowledgeDialogState();
}

class _KnowledgeDialogState extends ConsumerState<KnowledgeDialog> {
  static const int _graphDepthDefault = 2;
  static const int _graphNodesDefault = 120;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _graph;
  List<dynamic> _labels = const [];

  final TextEditingController _searchCtrl = TextEditingController();
  String? _selectedLabel;
  String _searchQuery = '';
  String _activeView = 'graph';
  String _graphMode = 'details';
  bool _docsLoading = false;
  String? _docsError;
  List<Map<String, dynamic>> _documents = const [];
  bool _uploading = false;
  bool _delegationTesting = false;
  String? _delegationStatus;
  String _docStatusFilter = 'all';
  String _docTypeFilter = 'all';
  final TextEditingController _docSearchCtrl = TextEditingController();
  String _docQuery = '';

  String? _selectedNodeId;
  final Map<String, GlobalKey> _wikiItemKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim());
    });
    _docSearchCtrl.addListener(() {
      setState(() => _docQuery = _docSearchCtrl.text.trim());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _docSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _loadWithParams(label: _selectedLabel);
  }

  Future<void> _loadDocuments() async {
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) {
      setState(() {
        _docsLoading = false;
        _docsError = 'no active claw selected';
      });
      return;
    }

    setState(() {
      _docsLoading = true;
      _docsError = null;
    });

    try {
      final query = <String, String>{
        'limit': '200',
        if (_docStatusFilter != 'all') 'status': _docStatusFilter,
        if (_docTypeFilter != 'all') 'type': _docTypeFilter,
        if (_docQuery.trim().isNotEmpty) 'q': _docQuery.trim(),
      };
      final qs = query.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');

      final url =
          '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-documents${qs.isEmpty ? '' : '?$qs'}';
      final request = html.HttpRequest();
      request.open('GET', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      final response = await _sendRequest(request);
      final decoded = Map<String, dynamic>.from(jsonDecode(response) as Map);
      final documents = (decoded['documents'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      if (!mounted) return;
      setState(() => _documents = documents);
    } catch (e) {
      if (!mounted) return;
      setState(() => _docsError = '$e');
    } finally {
      if (mounted) setState(() => _docsLoading = false);
    }
  }

  Future<void> _uploadDocument() async {
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) return;

    final picker = html.FileUploadInputElement()..accept = '.pdf,.docx,.txt,.md';
    final pickerCompleter = Completer<html.File?>();
    picker.onChange.first.then((_) {
      if (!pickerCompleter.isCompleted) {
        final file = picker.files?.isNotEmpty == true ? picker.files!.first : null;
        pickerCompleter.complete(file);
      }
    });
    // If the user cancels, onChange never fires on some browsers.
    // Use a focus listener as a fallback to detect cancel.
    html.window.onFocus.first.then((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!pickerCompleter.isCompleted) pickerCompleter.complete(null);
      });
    });
    picker.click();
    // Absolute safety net -- never block longer than 2 minutes.
    final file = await pickerCompleter.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => null,
    );
    if (file == null) return;

    setState(() {
      _uploading = true;
      _docsError = null;
    });

    try {
      final form = html.FormData();
      form.appendBlob('file', file, file.name);
      form.append('document_type', 'other');

      final url = '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-documents';
      final request = html.HttpRequest();
      request.open('POST', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      final createRaw = await _sendRequestWithBody(request, form);
      final created = Map<String, dynamic>.from(jsonDecode(createRaw) as Map);
      final documentId = (created['document_id'] ?? '').toString();
      if (documentId.isNotEmpty) {
        await _ingestDocument(documentId, silent: true);
      }
      await _loadDocuments();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _docsError = '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _ingestDocument(String documentId, {bool silent = false}) async {
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) return;

    try {
      final url =
          '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-documents/${Uri.encodeQueryComponent(documentId)}/ingest';
      final request = html.HttpRequest();
      request.open('POST', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      await _sendRequest(request);
      if (!silent) {
        await _loadDocuments();
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _docsError = '$e');
    }
  }

  Future<void> _deleteDocument(String documentId) async {
    final confirmed = html.window.confirm('Delete this document from knowledge base?');
    if (!confirmed) return;

    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) return;

    try {
      final url =
          '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-documents/${Uri.encodeQueryComponent(documentId)}';
      final request = html.HttpRequest();
      request.open('DELETE', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      await _sendRequest(request);
      await _loadDocuments();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _docsError = '$e');
    }
  }

  Future<void> _showDocumentChunks(String documentId) async {
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) return;

    try {
      final url =
          '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-documents/${Uri.encodeQueryComponent(documentId)}/chunks';
      final request = html.HttpRequest();
      request.open('GET', url);
      request.setRequestHeader('Authorization', 'Bearer $token');
      final raw = await _sendRequest(request);
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final chunks = (decoded['chunks'] as List? ?? const []);
      if (!mounted) return;

      // ignore: use_build_context_synchronously
      await showDialog<void>(
        context: context,
        builder: (context) {
          final theme = Theme.of(context);
          final t = ShellTokens.of(context);
          return Dialog(
            backgroundColor: t.surfaceBase,
            shape: RoundedRectangleBorder(
              borderRadius: kShellBorderRadius,
              side: BorderSide(color: t.border, width: 0.5),
            ),
            child: Container(
              width: 720,
              height: 520,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'document chunks · ${chunks.length}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: t.fgPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: chunks.length,
                      itemBuilder: (context, index) {
                        final c = Map<String, dynamic>.from(chunks[index] as Map);
                        final text = (c['text'] ?? '').toString();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: t.surfaceCard,
                            border: Border.all(color: t.border, width: 0.5),
                            borderRadius: kShellBorderRadiusSm,
                          ),
                          child: Text(
                            text.length > 260 ? '${text.substring(0, 260)}…' : text,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: t.fgSecondary,
                              height: 1.35,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _docsError = '$e');
    }
  }

  Future<void> _runDelegationSmokeTest() async {
    final auth = ref.read(authClientProvider);
    final token = auth.state.token;
    final openclawId = auth.state.activeOpenClawId;
    if (token == null || token.isEmpty || openclawId == null || openclawId.isEmpty) {
      setState(() => _delegationStatus = 'delegation test: no active claw selected');
      return;
    }

    setState(() {
      _delegationTesting = true;
      _delegationStatus = null;
    });

    try {
      final mintUrl = '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/delegation-token';
      final mintRequest = html.HttpRequest();
      mintRequest.open('POST', mintUrl);
      mintRequest.setRequestHeader('Authorization', 'Bearer $token');
      mintRequest.setRequestHeader('Content-Type', 'application/json');
      final mintRaw = await _sendRequestWithBody(
          mintRequest,
          jsonEncode({
            'scope': ['lightrag.read', 'lightrag.write'],
            'session_key': 'main',
          }));
      final mintJson = Map<String, dynamic>.from(jsonDecode(mintRaw) as Map);
      final delegation = (mintJson['token'] ?? '').toString();
      if (delegation.isEmpty) {
        throw 'delegation token was not returned';
      }

      final docsUrl = '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-documents?limit=50';
      final docsRequest = html.HttpRequest();
      docsRequest.open('GET', docsUrl);
      docsRequest.setRequestHeader('X-Trinity-Delegation', delegation);
      final docsRaw = await _sendRequest(docsRequest);
      final docsJson = Map<String, dynamic>.from(jsonDecode(docsRaw) as Map);
      final docs = (docsJson['documents'] as List? ?? const []);

      final queryUrl = '${auth.authServiceBaseUrl}/auth/openclaws/$openclawId/lightrag-query';
      final queryRequest = html.HttpRequest();
      queryRequest.open('POST', queryUrl);
      queryRequest.setRequestHeader('X-Trinity-Delegation', delegation);
      queryRequest.setRequestHeader('Content-Type', 'application/json');
      final queryRaw = await _sendRequestWithBody(
          queryRequest,
          jsonEncode({
            'query': 'delegation smoke test',
            'top_k': 3,
            'mode': 'hybrid',
          }));
      final queryJson = Map<String, dynamic>.from(jsonDecode(queryRaw) as Map);
      final hasData = queryJson.isNotEmpty;

      if (!mounted) return;
      setState(() {
        _delegationStatus =
            'delegation ok · docs ${docs.length} · query ${hasData ? 'ok' : 'empty'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _delegationStatus = 'delegation failed: $e');
    } finally {
      if (mounted) setState(() => _delegationTesting = false);
    }
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
        'max_depth': _graphDepthDefault.toString(),
        'max_nodes': _graphNodesDefault.toString(),
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

  Future<String> _sendRequest(html.HttpRequest request) =>
      safeXhr(request);

  Future<String> _sendRequestWithBody(html.HttpRequest request, dynamic body) =>
      safeXhr(request, body: body);

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

  ({List<Map<String, dynamic>> nodes, List<Map<String, dynamic>> edges})
      _computeVisibleGraph() {
    return (nodes: _graphNodes, edges: _graphEdges);
  }

  List<Map<String, dynamic>> _sortedWikiNodes() {
    final q = _searchQuery.trim().toLowerCase();
    final items = _graphNodes.where((n) {
      if (q.isEmpty) return true;
      final label = _nodeLabel(n).toLowerCase();
      final preview = _nodePreview(n).toLowerCase();
      final id = (n['id'] ?? n['identity'] ?? '').toString().toLowerCase();
      return label.contains(q) || preview.contains(q) || id.contains(q);
    }).toList()
      ..sort((a, b) => _nodeLabel(a).toLowerCase().compareTo(_nodeLabel(b).toLowerCase()));
    return items;
  }

  String? _firstWikiNodeId() {
    final items = _sortedWikiNodes();
    if (items.isEmpty) return null;
    final first = items.first;
    final id = (first['id'] ?? first['identity'] ?? '').toString();
    return id.isEmpty ? null : id;
  }

  GlobalKey _wikiItemKey(String id) {
    return _wikiItemKeys.putIfAbsent(id, () => GlobalKey());
  }

  void _syncWikiIndexToSelection() {
    final id = _selectedNodeId;
    if (id == null || id.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _wikiItemKeys[id]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 180),
          alignment: 0.3,
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _ensureSelectedNodeExists() {
    final exists = _selectedNodeId != null &&
        _selectedNodeId!.isNotEmpty &&
        _graphNodes.any((n) => (n['id'] ?? n['identity'] ?? '').toString() == _selectedNodeId);
    final fallback = _firstWikiNodeId();
    if (exists) {
      _syncWikiIndexToSelection();
      return;
    }
    if (fallback == null) return;
    setState(() {
      _selectedNodeId = fallback;
    });
    _syncWikiIndexToSelection();
  }

  void _selectNodeFromResult(String id) {
    if (id.isEmpty) return;
    setState(() {
      _selectedNodeId = id;
    });
    _syncWikiIndexToSelection();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);
    final visible = _computeVisibleGraph();
    final isTruncated = _graph?['is_truncated'] == true;
    final isGraphView = _activeView == 'graph';

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
            _activeView == 'graph'
                ? _buildControls(context, t, theme)
                : _buildDocumentsControls(context, t, theme),
            Expanded(
              child: isGraphView
                  ? _loading
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
                                SizedBox(
                                  width: 300,
                                  child: _buildWikiIndexPanel(context, t, theme),
                                ),
                                Container(width: 0.5, color: t.border),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _graphMode == 'details'
                                      ? _buildDetailsPanel(context, t, theme, selectedNode)
                                      : _KnowledgeGraphCanvas(
                                          nodes: visible.nodes,
                                          edges: visible.edges,
                                          selectedNodeId: _selectedNodeId,
                                          onNodeTap: _selectNodeFromResult,
                                          isTruncated: isTruncated,
                                        ),
                                ),
                              ],
                            ),
                          )
                  : _buildDocumentsBody(context, t, theme),
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
            _activeView == 'graph' ? 'knowledge graph' : 'knowledge documents',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: t.fgPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _activeView == 'graph'
                ? '$nodeCount nodes · $edgeCount edges'
                : '${_documents.length} documents',
            style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
          ),
          const SizedBox(width: 10),
          _headerToggleLink(context, t, theme, 'graph', active: _activeView == 'graph', onTap: () {
            setState(() => _activeView = 'graph');
          }),
          Text('|', style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted)),
          _headerToggleLink(context, t, theme, 'documents', active: _activeView == 'documents', onTap: () {
            setState(() => _activeView = 'documents');
            _loadDocuments();
          }),
          const Spacer(),
          GestureDetector(
            onTap: _activeView == 'graph'
                ? (_loading ? null : _load)
                : (_docsLoading ? null : _loadDocuments),
            child: Text(
              _activeView == 'graph'
                  ? (_loading ? 'loading...' : 'refresh')
                  : (_docsLoading ? 'loading...' : 'refresh'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: (_activeView == 'graph' ? _loading : _docsLoading)
                    ? t.fgDisabled
                    : t.accentPrimary,
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

  Widget _headerToggleLink(
    BuildContext context,
    ShellTokens t,
    ThemeData theme,
    String label, {
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: active ? t.accentPrimary : t.fgMuted,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context, ShellTokens t, ThemeData theme) {
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
            width: 250,
            child: _compactInput(
              controller: _searchCtrl,
              hint: 'search nodes',
              t: t,
              theme: theme,
            ),
          ),
          _headerToggleLink(
            context,
            t,
            theme,
            'wiki page',
            active: _graphMode == 'details',
            onTap: () => setState(() => _graphMode = 'details'),
          ),
          Text('|', style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted)),
          _headerToggleLink(
            context,
            t,
            theme,
            'graph',
            active: _graphMode == 'graph',
            onTap: () => setState(() => _graphMode = 'graph'),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsControls(BuildContext context, ShellTokens t, ThemeData theme) {
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
            width: 260,
            child: _compactInput(
              controller: _docSearchCtrl,
              hint: 'search documents',
              t: t,
              theme: theme,
            ),
          ),
          SizedBox(
            width: 120,
            child: _compactDropdown<String>(
              value: _docStatusFilter,
              items: const ['all', 'uploaded', 'indexed', 'failed'],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _docStatusFilter = v);
                _loadDocuments();
              },
              t: t,
              theme: theme,
            ),
          ),
          SizedBox(
            width: 120,
            child: _compactDropdown<String>(
              value: _docTypeFilter,
              items: const ['all', 'other', 'handbook', 'tender'],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _docTypeFilter = v);
                _loadDocuments();
              },
              t: t,
              theme: theme,
            ),
          ),
          _presetChip(
            context,
            t,
            theme,
            _uploading ? 'uploading...' : 'upload document',
            onTap: _uploading ? null : _uploadDocument,
          ),
          _presetChip(
            context,
            t,
            theme,
            'apply filters',
            onTap: _loadDocuments,
          ),
          _presetChip(
            context,
            t,
            theme,
            _delegationTesting ? 'testing delegation...' : 'test delegation',
            onTap: _delegationTesting ? null : _runDelegationSmokeTest,
          ),
          if (_delegationStatus != null)
            Text(
              _delegationStatus!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: _delegationStatus!.startsWith('delegation ok')
                    ? t.accentPrimary
                    : t.statusError,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDocumentsBody(BuildContext context, ShellTokens t, ThemeData theme) {
    if (_docsLoading) {
      return Center(
        child: Text(
          'loading documents...',
          style: theme.textTheme.bodyMedium?.copyWith(color: t.fgPlaceholder),
        ),
      );
    }
    if (_docsError != null) {
      return Center(
        child: Text(
          _docsError!,
          style: theme.textTheme.bodyMedium?.copyWith(color: t.statusError),
        ),
      );
    }
    if (_documents.isEmpty) {
      return Center(
        child: Text(
          'no documents yet',
          style: theme.textTheme.bodyMedium?.copyWith(color: t.fgMuted),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: ListView.separated(
        itemCount: _documents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = _documents[index];
          final documentId = (item['document_id'] ?? '').toString();
          final filename = (item['filename'] ?? '').toString();
          final status = (item['status'] ?? 'unknown').toString();
          final type = (item['document_type'] ?? 'other').toString();
          final chunkCount = (item['chunk_count'] as num?)?.toInt() ?? 0;
          final updatedAt = (item['updated_at'] ?? '').toString();
          final updatedShort = updatedAt.length >= 19 ? updatedAt.substring(0, 19) : updatedAt;

          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.surfaceCard,
              border: Border.all(color: t.border, width: 0.5),
              borderRadius: kShellBorderRadiusSm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        filename.isEmpty ? documentId : filename,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: t.fgPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$type · $status · $chunkCount chunks · $updatedShort',
                        style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _inlineAction(context, t, theme, 'ingest', onTap: () => _ingestDocument(documentId)),
                const SizedBox(width: 8),
                _inlineAction(context, t, theme, 'chunks', onTap: () => _showDocumentChunks(documentId)),
                const SizedBox(width: 8),
                _inlineAction(context, t, theme, 'delete', onTap: () => _deleteDocument(documentId), danger: true),
              ],
            ),
          );
        },
      ),
    );
  }

  String _nodeLabel(Map<String, dynamic> n) {
    return (((n['labels'] as List?)?.first) ?? n['label'] ?? n['id'] ?? '').toString();
  }

  String _nodePreview(Map<String, dynamic> n) {
    return ((n['properties'] as Map?)?['description'] ?? (n['metadata'] as Map?)?['preview'] ?? '')
        .toString();
  }

  String _nodeKind(Map<String, dynamic> n) {
    return ((n['entity_type'] ?? n['kind']) ?? 'node').toString();
  }

  String _alphaBucket(String label) {
    final s = label.trim();
    if (s.isEmpty) return 'Others';
    final ch = s[0].toUpperCase();
    final code = ch.codeUnitAt(0);
    if (code >= 65 && code <= 90) return ch;
    return 'Others';
  }

  List<Map<String, dynamic>> _connectedEdges(String nodeId) {
    return _graphEdges.where((e) {
      final s = (e['source'] ?? '').toString();
      final t = (e['target'] ?? '').toString();
      return s == nodeId || t == nodeId;
    }).toList();
  }

  Widget _buildWikiIndexPanel(BuildContext context, ShellTokens t, ThemeData theme) {
    final all = _sortedWikiNodes();

    final bucketed = <String, List<Map<String, dynamic>>>{};
    for (final n in all) {
      final bucket = _alphaBucket(_nodeLabel(n));
      bucketed.putIfAbsent(bucket, () => []).add(n);
    }
    final bucketKeys = bucketed.keys.toList()..sort();
    if (bucketKeys.remove('Others')) bucketKeys.add('Others');

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _searchQuery.isEmpty ? 'wiki index' : 'wiki search',
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
                itemCount: bucketKeys.length,
                itemBuilder: (context, index) {
                  final bucket = bucketKeys[index];
                  final items = bucketed[bucket] ?? const [];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$bucket (${items.length})',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: t.fgMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...items.map((n) {
                          final id = (n['id'] ?? n['identity'] ?? '').toString();
                          final isSelected = id == _selectedNodeId;
                          return GestureDetector(
                            onTap: () => _selectNodeFromResult(id),
                            child: Container(
                              key: _wikiItemKey(id),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                              margin: const EdgeInsets.only(bottom: 2),
                              color: isSelected
                                  ? t.accentPrimary.withOpacity(0.12)
                                  : Colors.transparent,
                              child: Text(
                                _nodeLabel(n),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: isSelected ? t.fgPrimary : t.fgSecondary,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsPanel(
    BuildContext context,
    ShellTokens t,
    ThemeData theme,
    Map<String, dynamic>? selectedNode,
  ) {
    final preview = selectedNode == null ? '' : _nodePreview(selectedNode);
    final kind = selectedNode == null ? 'node' : _nodeKind(selectedNode);
    final label = selectedNode == null ? '' : _nodeLabel(selectedNode);
    final selectedId = (selectedNode?['id'] ?? selectedNode?['identity'] ?? '').toString();
    final linkages = selectedId.isEmpty ? const <Map<String, dynamic>>[] : _connectedEdges(selectedId);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: t.border, width: 0.5),
        borderRadius: kShellBorderRadiusSm,
        color: t.surfaceCard,
      ),
      child: selectedNode == null
          ? Text(
              'select an entity from wiki index',
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
                  '$kind · $selectedId',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (preview.isNotEmpty)
                          SelectableText(
                            preview,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: t.fgSecondary,
                              height: 1.4,
                            ),
                          ),
                        if (linkages.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'related info (${linkages.length})',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: t.fgMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          ...linkages.take(24).map((e) {
                            final src = (e['source'] ?? '').toString();
                            final tgt = (e['target'] ?? '').toString();
                            final relatedId = src == selectedId ? tgt : src;
                            final relatedNode = _graphNodes.cast<Map<String, dynamic>?>().firstWhere(
                                  (n) =>
                                      (n?['id'] ?? n?['identity'] ?? '').toString() == relatedId,
                                  orElse: () => null,
                                );
                            final relatedLabel = relatedNode == null
                                ? relatedId
                                : _nodeLabel(relatedNode);
                            final props =
                                Map<String, dynamic>.from((e['properties'] as Map?) ?? const {});
                            final desc = (props['description'] ?? '').toString();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: relatedId.isEmpty ? null : () => _selectNodeFromResult(relatedId),
                                    child: MouseRegion(
                                      cursor: relatedId.isEmpty
                                          ? SystemMouseCursors.basic
                                          : SystemMouseCursors.click,
                                      child: Text(
                                        relatedLabel,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: t.accentPrimary,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$src -> $tgt',
                                    style: theme.textTheme.labelSmall?.copyWith(color: t.fgSecondary),
                                  ),
                                  if (desc.isNotEmpty)
                                    Text(
                                      desc,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: t.fgMuted,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
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
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: kShellBorderRadiusSm,
            border: Border.all(color: t.border, width: 0.5),
            color: onTap == null ? t.surfaceCard : t.surfaceBase,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: onTap == null ? t.fgDisabled : t.fgMuted,
              fontSize: 10,
            ),
          ),
        ),
      ),
    );
  }

  Widget _inlineAction(
    BuildContext context,
    ShellTokens t,
    ThemeData theme,
    String label, {
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: danger ? t.statusError : t.accentPrimary,
          ),
        ),
      ),
    );
  }
}

class _KnowledgeGraphCanvas extends StatefulWidget {
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> edges;
  final String? selectedNodeId;
  final ValueChanged<String> onNodeTap;
  final bool isTruncated;

  const _KnowledgeGraphCanvas({
    required this.nodes,
    required this.edges,
    required this.selectedNodeId,
    required this.onNodeTap,
    this.isTruncated = false,
  });

  @override
  State<_KnowledgeGraphCanvas> createState() => _KnowledgeGraphCanvasState();
}

class _KnowledgeGraphCanvasState extends State<_KnowledgeGraphCanvas> {
  static const int _maxRelatedNodes = 14;

  String _nodeId(Map<String, dynamic> node) {
    return (node['id'] ?? node['identity'] ?? '').toString();
  }

  String _nodeLabel(Map<String, dynamic> node) {
    return (((node['labels'] as List?)?.first) ?? node['label'] ?? node['id'] ?? '')
        .toString();
  }

  String _nodeKind(Map<String, dynamic> node) {
    return ((node['entity_type'] ?? node['kind']) ?? 'node').toString();
  }

  String _nodePreview(Map<String, dynamic> node) {
    return ((node['properties'] as Map?)?['description'] ??
            (node['metadata'] as Map?)?['preview'] ??
            '')
        .toString();
  }

  ({Map<String, dynamic>? center, List<Map<String, dynamic>> related, List<Map<String, dynamic>> edges, int extraCount})
      _buildEgoGraph() {
    final nodeById = <String, Map<String, dynamic>>{};
    for (final n in widget.nodes) {
      final id = _nodeId(n);
      if (id.isNotEmpty) nodeById[id] = n;
    }

    final centerId = widget.selectedNodeId != null && nodeById.containsKey(widget.selectedNodeId)
        ? widget.selectedNodeId!
        : (widget.nodes.isNotEmpty ? _nodeId(widget.nodes.first) : '');
    if (centerId.isEmpty || !nodeById.containsKey(centerId)) {
      return (center: null, related: const [], edges: const [], extraCount: 0);
    }

    final neighborIds = <String>{};
    final relevantEdges = <Map<String, dynamic>>[];
    for (final edge in widget.edges) {
      final src = (edge['source'] ?? '').toString();
      final tgt = (edge['target'] ?? '').toString();
      if (src == centerId || tgt == centerId) {
        relevantEdges.add(edge);
        if (src == centerId && tgt.isNotEmpty && nodeById.containsKey(tgt)) neighborIds.add(tgt);
        if (tgt == centerId && src.isNotEmpty && nodeById.containsKey(src)) neighborIds.add(src);
      }
    }

    final sortedNeighborIds = neighborIds.toList()
      ..sort((a, b) => _nodeLabel(nodeById[a]!).toLowerCase().compareTo(_nodeLabel(nodeById[b]!).toLowerCase()));
    final keptNeighborIds = sortedNeighborIds.take(_maxRelatedNodes).toSet();
    final related = sortedNeighborIds.take(_maxRelatedNodes).map((id) => nodeById[id]!).toList();
    final filteredEdges = relevantEdges.where((edge) {
      final src = (edge['source'] ?? '').toString();
      final tgt = (edge['target'] ?? '').toString();
      return src == centerId
          ? keptNeighborIds.contains(tgt)
          : tgt == centerId
              ? keptNeighborIds.contains(src)
              : false;
    }).toList();

    return (
      center: nodeById[centerId],
      related: related,
      edges: filteredEdges,
      extraCount: math.max(0, sortedNeighborIds.length - _maxRelatedNodes),
    );
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

    final ego = _buildEgoGraph();
    final center = ego.center;
    if (center == null) {
      return Center(
        child: Text(
          'select an entity to view graph',
          style: theme.textTheme.bodyMedium?.copyWith(color: t.fgMuted),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final centerPos = Offset(width * 0.32, height * 0.5);
        final related = ego.related;
        final positions = <String, Offset>{
          _nodeId(center): centerPos,
        };
        final count = related.length;
        for (var i = 0; i < count; i++) {
          final angle = count == 1 ? 0.0 : (-math.pi / 2) + ((i / math.max(1, count - 1)) * math.pi);
          final x = width * 0.72 + math.cos(angle) * width * 0.16;
          final y = height * 0.5 + math.sin(angle) * height * 0.34;
          positions[_nodeId(related[i])] = Offset(x, y);
        }

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kShellRadius),
            border: Border.all(color: t.border, width: 0.5),
            color: t.surfaceCard,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _KnowledgeGraphPainter(
                    positions: positions,
                    edges: ego.edges,
                    selectedNodeId: widget.selectedNodeId,
                    borderColor: t.border,
                    accentColor: t.accentPrimary,
                    mutedColor: t.fgMuted,
                  ),
                ),
              ),
              ...positions.entries.map((entry) {
                final id = entry.key;
                final node = id == _nodeId(center)
                    ? center
                    : related.firstWhere((n) => _nodeId(n) == id, orElse: () => {'id': id});
                final pos = entry.value;
                final selected = id == widget.selectedNodeId;
                final isCenter = id == _nodeId(center);
                final widthCard = isCenter ? 210.0 : 170.0;
                final heightCard = isCenter ? 82.0 : 64.0;
                return Positioned(
                  left: (pos.dx - widthCard / 2).clamp(8.0, math.max(8.0, width - widthCard - 8)),
                  top: (pos.dy - heightCard / 2).clamp(8.0, math.max(8.0, height - heightCard - 8)),
                  width: widthCard,
                  height: heightCard,
                  child: GestureDetector(
                    onTap: () => widget.onNodeTap(id),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: selected ? t.accentPrimary.withOpacity(0.12) : t.surfaceBase,
                        border: Border.all(
                          color: selected || isCenter ? t.accentPrimary : t.border,
                          width: 0.8,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _nodeLabel(node),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: t.fgPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _nodeKind(node),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: t.fgMuted,
                              fontSize: 10,
                            ),
                          ),
                          if (_nodePreview(node).isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _nodePreview(node),
                              maxLines: isCenter ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: t.fgSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }),
              Positioned(
                left: 12,
                top: 12,
                child: Text(
                  ego.extraCount > 0
                      ? '${related.length} related shown · +${ego.extraCount} more'
                      : '${related.length} related items',
                  style: theme.textTheme.labelSmall?.copyWith(color: t.fgMuted),
                ),
              ),
              if (widget.isTruncated)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Text(
                    'graph slice',
                    style: theme.textTheme.labelSmall?.copyWith(color: t.statusWarning),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _KnowledgeGraphPainter extends CustomPainter {
  final Map<String, Offset> positions;
  final List<Map<String, dynamic>> edges;
  final String? selectedNodeId;
  final Color borderColor;
  final Color accentColor;
  final Color mutedColor;

  const _KnowledgeGraphPainter({
    required this.positions,
    required this.edges,
    required this.selectedNodeId,
    required this.borderColor,
    required this.accentColor,
    required this.mutedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = borderColor.withOpacity(0.55)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final selectedPaint = Paint()
      ..color = accentColor.withOpacity(0.8)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final src = (edge['source'] ?? '').toString();
      final tgt = (edge['target'] ?? '').toString();
      final a = positions[src];
      final b = positions[tgt];
      if (a == null || b == null) continue;
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2 - 18);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy);
      final selected = src == selectedNodeId || tgt == selectedNodeId;
      canvas.drawPath(path, selected ? selectedPaint : basePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _KnowledgeGraphPainter oldDelegate) {
    return oldDelegate.positions != positions ||
        oldDelegate.edges != edges ||
        oldDelegate.selectedNodeId != selectedNodeId;
  }
}
