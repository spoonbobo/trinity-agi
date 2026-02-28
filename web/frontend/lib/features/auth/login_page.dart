import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import '../../core/auth_client.dart';
import '../../core/toast_provider.dart';
import '../../main.dart' show authClientProvider;

class LoginPage extends ConsumerStatefulWidget {
  final VoidCallback? onLoginSuccess;

  const LoginPage({super.key, this.onLoginSuccess});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true; // true=login, false=signup
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
              ),
              const SizedBox(height: 12),
              // Password
              TextField(
                controller: _passwordController,
                obscureText: true,
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
                onTap: _loading
                    ? null
                    : () {
                        final authClient = ref.read(authClientProvider);
                        final url = authClient.getKeycloakLoginUrl();
                        debugPrint('SSO URL: $url (not yet implemented)');
                      },
                child: Tooltip(
                  message: 'SSO integration coming soon',
                  child: Text(
                    'sign in with SSO',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: t.fgDisabled,
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
