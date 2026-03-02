import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/auth_client.dart';
import '../../core/toast_provider.dart';
import '../../main.dart' show authClientProvider;

const _rememberEmailKey = 'trinity_remember_email';
const _savedEmailKey = 'trinity_saved_email';

class LoginPage extends ConsumerStatefulWidget {
  final VoidCallback? onLoginSuccess;

  const LoginPage({super.key, this.onLoginSuccess});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _isLogin = true; // true=login, false=signup
  bool _loading = false;
  bool _rememberEmail = false;

  @override
  void initState() {
    super.initState();
    final stored = html.window.localStorage[_rememberEmailKey];
    if (stored == 'true') {
      _rememberEmail = true;
      final savedEmail = html.window.localStorage[_savedEmailKey] ?? '';
      _emailController.text = savedEmail;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() => _loading = true);

    try {
      final authClient = ref.read(authClientProvider);
      if (_isLogin) {
        await authClient.loginWithEmail(email, password);
      } else {
        await authClient.signUpWithEmail(email, password);
      }

      // Persist or clear remembered email
      if (_rememberEmail) {
        html.window.localStorage[_savedEmailKey] = email;
        html.window.localStorage[_rememberEmailKey] = 'true';
      } else {
        html.window.localStorage.remove(_savedEmailKey);
        html.window.localStorage.remove(_rememberEmailKey);
      }

      widget.onLoginSuccess?.call();
    } catch (e) {
      final errMsg = e.toString().replaceAll('Exception: ', '');
      ToastService.showError(context, errMsg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithSSO() async {
    setState(() => _loading = true);

    try {
      final authClient = ref.read(authClientProvider);
      final ssoUrl = authClient.getKeycloakLoginUrl();

      // Open SSO URL in a popup window
      final popup = html.window.open(ssoUrl, 'sso_login',
        'width=500,height=600,scrollbars=yes,resizable=yes');

      // Listen for the callback message from the popup
      // Security: validate the origin of the postMessage to prevent token injection
      final expectedOrigin = Uri.parse(authClient.authServiceBaseUrl).origin;
      late final html.EventListener messageHandler;
      messageHandler = (html.Event event) {
        if (event is html.MessageEvent) {
          // Validate origin matches our auth service
          final eventOrigin = event.origin;
          if (eventOrigin.isNotEmpty && eventOrigin != expectedOrigin && eventOrigin != html.window.location!.origin) {
            return; // Reject messages from unexpected origins
          }
          final data = event.data;
          if (data is Map && data.containsKey('access_token')) {
            final accessToken = data['access_token'] as String;
            html.window.removeEventListener('message', messageHandler);
            _completeSSOLogin(accessToken);
          } else if (data is String && data.startsWith('sso_token:')) {
            final accessToken = data.substring('sso_token:'.length);
            html.window.removeEventListener('message', messageHandler);
            _completeSSOLogin(accessToken);
          }
        }
      };
      html.window.addEventListener('message', messageHandler);

      // Also poll the popup URL for hash fragments (fallback for redirects)
      _pollSSOPopup(popup, messageHandler);
    } catch (e) {
      final errMsg = e.toString().replaceAll('Exception: ', '');
      ToastService.showError(context, errMsg);
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pollSSOPopup(html.WindowBase? popup, html.EventListener messageHandler) {
    if (popup == null) {
      html.window.removeEventListener('message', messageHandler);
      setState(() => _loading = false);
      return;
    }
    // Poll every 500ms to check if popup closed or has a token in URL
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        if (popup.closed == true) {
          html.window.removeEventListener('message', messageHandler);
          if (mounted) setState(() => _loading = false);
          return false; // Stop polling
        }
      } catch (_) {}
      if (!mounted || !_loading) {
        // Widget disposed or login completed -- clean up listener
        html.window.removeEventListener('message', messageHandler);
        return false;
      }
      return true; // Keep polling
    });
  }

  Future<void> _completeSSOLogin(String accessToken) async {
    try {
      final authClient = ref.read(authClientProvider);
      await authClient.resolveSessionFromToken(accessToken);
      widget.onLoginSuccess?.call();
    } catch (e) {
      final errMsg = e.toString().replaceAll('Exception: ', '');
      ToastService.showError(context, errMsg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginAsGuest() async {
    setState(() {
      _loading = true;
    });

    try {
      final authClient = ref.read(authClientProvider);
      await authClient.loginAsGuest();
      widget.onLoginSuccess?.call();
    } catch (e) {
      final errMsg = e.toString().replaceAll('Exception: ', '');
      ToastService.showError(context, errMsg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShellTokens.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: t.surfaceBase,
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'trinity',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: t.accentPrimary,
                ),
              ),
              const SizedBox(height: 24),
              // Email
              TextField(
                controller: _emailController,
                focusNode: _emailFocusNode,
                autofocus: !_rememberEmail,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'email',
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: t.border),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: t.accentPrimary),
                  ),
                ),
                onSubmitted: (_) {
                  FocusScope.of(context).requestFocus(_passwordFocusNode);
                },
              ),
              const SizedBox(height: 12),
              // Password
              TextField(
                controller: _passwordController,
                focusNode: _passwordFocusNode,
                autofocus: _rememberEmail,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'password',
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: t.border),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: t.accentPrimary),
                  ),
                ),
                onSubmitted: (_) => _submitEmail(),
              ),
              const SizedBox(height: 12),
              // Remember email
              GestureDetector(
                onTap: () => setState(() => _rememberEmail = !_rememberEmail),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(Radius.circular(3)),
                        color: _rememberEmail ? t.accentPrimary : Colors.transparent,
                        border: Border.all(
                          color: _rememberEmail ? t.accentPrimary : t.border,
                          width: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'remember email',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: t.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Actions
              Row(
                children: [
                  GestureDetector(
                    onTap: _loading ? null : _submitEmail,
                    child: Text(
                      _isLogin ? 'login' : 'sign up',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _loading ? t.fgDisabled : t.accentPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () => setState(() => _isLogin = !_isLogin),
                    child: Text(
                      _isLogin ? 'create account' : 'have an account',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: t.fgMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Divider(color: t.border, thickness: 0.5),
              const SizedBox(height: 16),
              // SSO
              GestureDetector(
                onTap: _loading ? null : _loginWithSSO,
                child: MouseRegion(
                  cursor: _loading ? SystemMouseCursors.basic : SystemMouseCursors.click,
                  child: Text(
                    'sign in with SSO',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _loading ? t.fgDisabled : t.accentSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Guest
              GestureDetector(
                onTap: _loading ? null : _loginAsGuest,
                child: Text(
                  'continue as guest',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: t.fgTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
