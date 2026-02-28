import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ws_frame.dart';
import '../../core/providers.dart';

/// Represents a pending exec approval request from the OpenClaw gateway.
class ApprovalRequest {
  final String requestId;
  final String command;
  final String? host;
  final String? sessionKey;
  final String? agentId;
  final DateTime timestamp;
  bool resolved;

  ApprovalRequest({
    required this.requestId,
    required this.command,
    this.host,
    this.sessionKey,
    this.agentId,
    DateTime? timestamp,
    this.resolved = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Represents a Lobster workflow approval gate.
class LobsterApproval {
  final String prompt;
  final String resumeToken;
  final List<dynamic> previewItems;
  final DateTime timestamp;
  bool resolved;

  LobsterApproval({
    required this.prompt,
    required this.resumeToken,
    this.previewItems = const [],
    DateTime? timestamp,
    this.resolved = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ApprovalPanel extends ConsumerStatefulWidget {
  final VoidCallback? onAllResolved;
  const ApprovalPanel({super.key, this.onAllResolved});

  @override
  ConsumerState<ApprovalPanel> createState() => _ApprovalPanelState();
}

class _ApprovalPanelState extends ConsumerState<ApprovalPanel> {
  final List<ApprovalRequest> _execApprovals = [];
  final List<LobsterApproval> _lobsterApprovals = [];
  StreamSubscription<WsEvent>? _approvalSub;
  StreamSubscription<WsEvent>? _chatSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final client = ref.read(gatewayClientProvider);

      // Exec approval requests
      _approvalSub = client.approvalEvents.listen((event) {
        final payload = event.payload;
        setState(() {
          _execApprovals.insert(
            0,
            ApprovalRequest(
              requestId: payload['requestId'] as String? ?? '',
              command: payload['command'] as String? ?? '<unknown>',
              host: payload['host'] as String?,
              sessionKey: payload['sessionKey'] as String?,
              agentId: payload['agentId'] as String?,
            ),
          );
        });
      });

      // Lobster workflow approvals surface through chat/agent events
      _chatSub = client.chatEvents.listen((event) {
        final payload = event.payload;
        if (event.event == 'agent' && payload['type'] == 'tool_result') {
          final result = payload['result'];
          if (result is Map<String, dynamic> &&
              result['status'] == 'needs_approval') {
            final approval = result['requiresApproval'] as Map<String, dynamic>?;
            if (approval != null) {
              setState(() {
                _lobsterApprovals.insert(
                  0,
                  LobsterApproval(
                    prompt: approval['prompt'] as String? ?? 'Approve action?',
                    resumeToken: approval['resumeToken'] as String? ?? '',
                    previewItems: approval['items'] as List<dynamic>? ?? [],
                  ),
                );
              });
            }
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _approvalSub?.cancel();
    _chatSub?.cancel();
    super.dispose();
  }

  Future<void> _resolveExecApproval(ApprovalRequest request, bool approve) async {
    final client = ref.read(gatewayClientProvider);
    await client.resolveApproval(request.requestId, approve);
    setState(() => request.resolved = true);
    _checkAllResolved();
  }

  Future<void> _resolveLobsterApproval(
      LobsterApproval approval, bool approve) async {
    final client = ref.read(gatewayClientProvider);
    // Resume the Lobster workflow by sending a chat message with the action
    await client.sendChatMessage(
      approve
          ? '/lobster resume ${approval.resumeToken} --approve'
          : '/lobster resume ${approval.resumeToken} --reject',
    );
    setState(() => approval.resolved = true);
    _checkAllResolved();
  }

  void _checkAllResolved() {
    final hasPending = _execApprovals.any((a) => !a.resolved) ||
        _lobsterApprovals.any((a) => !a.resolved);
    if (!hasPending) {
      widget.onAllResolved?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendingExec = _execApprovals.where((a) => !a.resolved).toList();
    final pendingLobster = _lobsterApprovals.where((a) => !a.resolved).toList();
    final resolvedExec = _execApprovals.where((a) => a.resolved).toList();
    final resolvedLobster = _lobsterApprovals.where((a) => a.resolved).toList();
    final hasPending = pendingExec.isNotEmpty || pendingLobster.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A))),
          ),
          child: Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 16,
                color: hasPending
                    ? const Color(0xFFFBBF24)
                    : const Color(0xFF6EE7B7),
              ),
              const SizedBox(width: 8),
              Text(
                'GOVERNANCE',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              if (hasPending)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${pendingExec.length + pendingLobster.length} PENDING',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFFFBBF24),
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: (pendingExec.isEmpty &&
                  pendingLobster.isEmpty &&
                  resolvedExec.isEmpty &&
                  resolvedLobster.isEmpty)
              ? _buildEmptyState(theme)
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (pendingExec.isNotEmpty) ...[
                      _sectionHeader('Exec Approvals', theme),
                      ...pendingExec
                          .map((a) => _ExecApprovalCard(
                                request: a,
                                onApprove: () =>
                                    _resolveExecApproval(a, true),
                                onReject: () =>
                                    _resolveExecApproval(a, false),
                              )),
                    ],
                    if (pendingLobster.isNotEmpty) ...[
                      _sectionHeader('Workflow Approvals', theme),
                      ...pendingLobster
                          .map((a) => _LobsterApprovalCard(
                                approval: a,
                                onApprove: () =>
                                    _resolveLobsterApproval(a, true),
                                onReject: () =>
                                    _resolveLobsterApproval(a, false),
                              )),
                    ],
                    if (resolvedExec.isNotEmpty ||
                        resolvedLobster.isNotEmpty) ...[
                      _sectionHeader('Resolved', theme),
                      ...resolvedExec.map((a) => _ResolvedCard(
                            label: a.command,
                            type: 'exec',
                          )),
                      ...resolvedLobster.map((a) => _ResolvedCard(
                            label: a.prompt,
                            type: 'workflow',
                          )),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 36,
            color: theme.colorScheme.primary.withOpacity(0.2),
          ),
          const SizedBox(height: 12),
          Text(
            'NO PENDING APPROVALS',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 2,
              color: const Color(0xFF3A3A3A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Exec and workflow approvals appear here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF4A4A4A),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: const Color(0xFF6B6B6B),
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _ExecApprovalCard extends StatelessWidget {
  final ApprovalRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ExecApprovalCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1500),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF4A3A00)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 14, color: Color(0xFFFBBF24)),
              const SizedBox(width: 6),
              Text(
                'EXEC APPROVAL',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFFFBBF24),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (request.host != null)
                Text(
                  request.host!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF6B6B6B),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              request.command,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 12,
                color: const Color(0xFFE5E5E5),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onReject,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text('REJECT', style: theme.textTheme.labelSmall),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: onApprove,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6EE7B7),
                  foregroundColor: const Color(0xFF0A0A0A),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text('APPROVE', style: theme.textTheme.labelSmall),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LobsterApprovalCard extends StatelessWidget {
  final LobsterApproval approval;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _LobsterApprovalCard({
    required this.approval,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1520),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E3A5F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_rounded,
                  size: 14, color: Color(0xFF3B82F6)),
              const SizedBox(width: 6),
              Text(
                'WORKFLOW APPROVAL',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF3B82F6),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            approval.prompt,
            style: theme.textTheme.bodyLarge,
          ),
          if (approval.previewItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: approval.previewItems
                    .take(5)
                    .map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            item.toString(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 11,
                              color: const Color(0xFF8B8B8B),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onReject,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Text('REJECT', style: theme.textTheme.labelSmall),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: onApprove,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text('APPROVE', style: theme.textTheme.labelSmall),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResolvedCard extends StatelessWidget {
  final String label;
  final String type;

  const _ResolvedCard({required this.label, required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1A1A1A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              size: 14, color: Color(0xFF3A3A3A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF3A3A3A),
                    fontSize: 11,
                  ),
            ),
          ),
          Text(
            type,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF2A2A2A),
                  fontSize: 9,
                ),
          ),
        ],
      ),
    );
  }
}
