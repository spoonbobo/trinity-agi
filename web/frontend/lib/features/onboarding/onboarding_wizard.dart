import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/terminal_client.dart';
import '../terminal/terminal_view.dart';
import '../shell/shell_page.dart' show terminalClientProvider;

enum OnboardingStep { welcome, status, configure, terminal }

class OnboardingWizard extends ConsumerStatefulWidget {
  final VoidCallback? onComplete;
  final OnboardingStep initialStep;

  const OnboardingWizard({
    super.key,
    this.onComplete,
    this.initialStep = OnboardingStep.welcome,
  });

  @override
  ConsumerState<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends ConsumerState<OnboardingWizard> {
  late OnboardingStep _currentStep;
  final PageController _pageController = PageController();
  bool _isConnecting = false;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.initialStep;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectTerminal();
      _pageController.jumpToPage(_currentStep.index);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _connectTerminal() async {
    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });

    try {
      final client = ref.read(terminalClientProvider);
      await client.connect();
      await Future.delayed(const Duration(milliseconds: 500));

      if (client.isAuthenticated) {
        setState(() {
          _isConnecting = false;
        });
        client.executeCommand('doctor');
      } else {
        setState(() {
          _isConnecting = false;
          _connectionError = 'Failed to authenticate with terminal proxy';
        });
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _connectionError = 'Failed to connect: $e';
      });
    }
  }

  void _nextStep() {
    final nextIndex = _currentStep.index + 1;
    if (nextIndex < OnboardingStep.values.length) {
      setState(() {
        _currentStep = OnboardingStep.values[nextIndex];
      });
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      widget.onComplete?.call();
    }
  }

  void _previousStep() {
    final prevIndex = _currentStep.index - 1;
    if (prevIndex >= 0) {
      setState(() {
        _currentStep = OnboardingStep.values[prevIndex];
      });
      _pageController.animateToPage(
        prevIndex,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _goToStep(OnboardingStep step) {
    setState(() {
      _currentStep = step;
    });
    _pageController.animateToPage(
      step.index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    return Container(
      color: t.surfaceBase,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _connectionError != null
                ? _buildErrorView()
                : PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildWelcomeStep(),
                      _buildStatusStep(),
                      _buildConfigureStep(),
                      _buildTerminalStep(),
                    ],
                  ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            'setup',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: t.fgPrimary,
            ),
          ),
          const SizedBox(width: 16),
          ...OnboardingStep.values.map((step) {
            final isActive = step == _currentStep;
            final isPast = step.index < _currentStep.index;
            final isFuture = step.index > _currentStep.index;

            return GestureDetector(
              onTap: isFuture ? null : () => _goToStep(step),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  _getStepTitle(step),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isActive
                        ? t.accentPrimary
                        : isPast
                            ? t.fgTertiary
                            : t.fgDisabled,
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          if (_isConnecting)
            Text(
              'connecting...',
              style: theme.textTheme.labelSmall?.copyWith(
                color: t.fgTertiary,
              ),
            ),
        ],
      ),
    );
  }

  String _getStepTitle(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.welcome:
        return 'welcome';
      case OnboardingStep.status:
        return 'status';
      case OnboardingStep.configure:
        return 'configure';
      case OnboardingStep.terminal:
        return 'terminal';
    }
  }

  Widget _buildErrorView() {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'connection error',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: t.statusError,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _connectionError!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: t.fgTertiary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _connectTerminal,
            child: Text(
              'retry',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: t.accentPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeStep() {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OpenClaw Gateway powers the agent runtime, multi-provider LLM, '
            'tool execution, sessions, memory, and governance.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: t.fgSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          _buildFeatureLine('health check', 'verify OpenClaw is running'),
          _buildFeatureLine('configuration', 'set up LLM providers and keys'),
          _buildFeatureLine('terminal', 'run OpenClaw commands from browser'),
          const SizedBox(height: 24),
          Text(
            'The wizard will connect to the OpenClaw Gateway running in Docker.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: t.fgTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureLine(String title, String description) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '- ',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: t.fgTertiary,
            ),
          ),
          Text(
            '$title  ',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: t.fgPrimary,
            ),
          ),
          Flexible(
            child: Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: t.fgTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStep() {
    return Consumer(
      builder: (context, ref, child) {
        final client = ref.watch(terminalClientProvider);
        return TerminalView(
          client: client,
          showInput: false,
          suggestedCommands: const ['status', 'doctor', 'models'],
        );
      },
    );
  }

  Widget _buildConfigureStep() {
    return Consumer(
      builder: (context, ref, child) {
        final client = ref.watch(terminalClientProvider);
        final t = ShellTokens.of(context);

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: t.border, width: 0.5),
                ),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _buildConfigLink(client, 'configure', 'configure'),
                  _buildConfigLink(client, 'web tools', 'configure --section web'),
                  _buildConfigLink(client, 'channels', 'channels login'),
                  _buildConfigLink(client, 'auto-fix', 'doctor --fix'),
                ],
              ),
            ),
            Expanded(
              child: TerminalView(
                client: client,
                showInput: true,
                suggestedCommands: const [
                  'configure --section providers',
                  'configure --section web',
                  'channels list',
                  'sessions list',
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConfigLink(TerminalProxyClient client, String label, String command) {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return GestureDetector(
      onTap: client.isExecuting ? null : () => client.executeCommand(command),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: client.isExecuting ? t.fgDisabled : t.accentPrimary,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTerminalStep() {
    return Consumer(
      builder: (context, ref, child) {
        final client = ref.watch(terminalClientProvider);
        return TerminalView(
          client: client,
          showInput: true,
          suggestedCommands: const ['status', 'models', 'sessions list', 'logs'],
        );
      },
    );
  }

  Widget _buildFooter() {
    final theme = Theme.of(context);
    final t = ShellTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep.index > 0)
            GestureDetector(
              onTap: _previousStep,
              child: Text(
                'back',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: t.fgTertiary,
                ),
              ),
            ),
          const Spacer(),
          GestureDetector(
            onTap: _isConnecting ? null : _nextStep,
            child: Text(
              _currentStep == OnboardingStep.terminal ? 'done' : 'next',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _isConnecting ? t.fgDisabled : t.accentPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
