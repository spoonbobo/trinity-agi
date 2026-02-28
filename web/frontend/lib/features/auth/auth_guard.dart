import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth_client.dart';
import '../../main.dart' show authClientProvider;
import 'login_page.dart';

class AuthGuard extends ConsumerWidget {
  final Widget child;

  const AuthGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authClient = ref.watch(authClientProvider);
    final authState = authClient.state;

    // If no token at all, show login
    if (authState.token == null || authState.token!.isEmpty) {
      return LoginPage(
        onLoginSuccess: () {
          // Force rebuild by notifying
          (context as Element).markNeedsBuild();
        },
      );
    }

    // Authenticated (user or guest) -> show shell
    return child;
  }
}
