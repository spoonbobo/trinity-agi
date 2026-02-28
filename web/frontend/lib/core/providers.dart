import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'gateway_client.dart' as gw;
import 'auth.dart';
import 'terminal_client.dart';
import 'auth_client.dart';

const _authBaseUrl = String.fromEnvironment(
  'AUTH_SERVICE_URL',
  defaultValue: 'http://localhost',
);

final authClientProvider = ChangeNotifierProvider<AuthClient>((ref) {
  return AuthClient(authServiceBaseUrl: _authBaseUrl);
});

final _sharedDevice = DeviceIdentity.generate();
final _sharedAuth = GatewayAuth(
  token: const String.fromEnvironment(
    'GATEWAY_TOKEN',
    defaultValue: 'replace-me-with-a-real-token',
  ),
  device: _sharedDevice,
);
const _gatewayWsUrl = String.fromEnvironment(
  'GATEWAY_WS_URL',
  defaultValue: 'ws://localhost:18789',
);
const _terminalWsUrl = String.fromEnvironment(
  'TERMINAL_WS_URL',
  defaultValue: 'ws://localhost/terminal/',
);

final gatewayClientProvider = ChangeNotifierProvider<gw.GatewayClient>((ref) {
  return gw.GatewayClient(url: _gatewayWsUrl, auth: _sharedAuth);
});

final terminalClientProvider = ChangeNotifierProvider<TerminalProxyClient>((ref) {
  final authState = ref.watch(authClientProvider).state;
  final role = roleToString(authState.role);
  return TerminalProxyClient(url: _terminalWsUrl, auth: _sharedAuth, role: role);
});
