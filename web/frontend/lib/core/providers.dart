import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'gateway_client.dart' as gw;
import 'auth.dart';
import 'terminal_client.dart';
import 'auth_client.dart' show AuthClient, AuthRole, OpenClawInfo, OpenClawStatus, roleToString;

const _authBaseUrl = String.fromEnvironment(
  'AUTH_SERVICE_URL',
  defaultValue: 'http://localhost',
);

final authClientProvider = ChangeNotifierProvider<AuthClient>((ref) {
  return AuthClient(authServiceBaseUrl: _authBaseUrl);
});

final _sharedDevice = DeviceIdentity.generate();

/// Shared [GatewayAuth] that uses the JWT from the current auth session.
/// The token is updated by [_syncAuthToken] whenever the auth state changes.
final _sharedAuth = GatewayAuth(token: '', device: _sharedDevice);

const _gatewayWsUrl = String.fromEnvironment(
  'GATEWAY_WS_URL',
  defaultValue: 'ws://localhost:18789',
);
const _terminalWsUrl = String.fromEnvironment(
  'TERMINAL_WS_URL',
  defaultValue: 'ws://localhost/terminal/',
);

/// Keep [_sharedAuth] in sync with the current JWT from [AuthClient].
void _syncAuthToken(AuthClient authClient) {
  final jwt = authClient.state.token ?? '';
  if (_sharedAuth.token != jwt) {
    _sharedAuth.updateToken(jwt);
  }
}

final gatewayClientProvider = ChangeNotifierProvider<gw.GatewayClient>((ref) {
  final authClient = ref.read(authClientProvider);
  _syncAuthToken(authClient);
  // Listen for future auth state changes and push new JWT to gateway auth.
  authClient.addListener(() => _syncAuthToken(authClient));
  return gw.GatewayClient(url: _gatewayWsUrl, auth: _sharedAuth);
});

final terminalClientProvider = ChangeNotifierProvider<TerminalProxyClient>((ref) {
  final authClient = ref.read(authClientProvider);
  _syncAuthToken(authClient);
  final role = roleToString(authClient.state.role);
  return TerminalProxyClient(url: _terminalWsUrl, auth: _sharedAuth, role: role);
});

/// Create an independent TerminalProxyClient for scoped use (e.g. per-channel
/// onboarding terminal). Caller is responsible for calling dispose() when done.
TerminalProxyClient createScopedTerminalClient(WidgetRef ref) {
  final authClient = ref.read(authClientProvider);
  _syncAuthToken(authClient);
  final role = roleToString(authClient.state.role);
  return TerminalProxyClient(url: _terminalWsUrl, auth: _sharedAuth, role: role);
}

/// Active session key — defaults to 'main'.
final activeSessionProvider = StateProvider<String>((ref) => 'main');

/// The currently selected OpenClaw instance ID.
final activeOpenClawProvider = StateProvider<String?>((ref) => null);
