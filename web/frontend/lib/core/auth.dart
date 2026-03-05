import 'package:uuid/uuid.dart';

class DeviceIdentity {
  final String id;

  DeviceIdentity._(this.id);

  factory DeviceIdentity.generate() {
    return DeviceIdentity._(const Uuid().v4());
  }
}

class GatewayAuth {
  /// Current JWT token — updated when the auth session refreshes.
  String _token;
  final DeviceIdentity device;

  GatewayAuth({required String token, required this.device}) : _token = token;

  String get token => _token;

  /// Update the JWT token (e.g. after a token refresh).
  void updateToken(String newToken) {
    _token = newToken;
  }

  Map<String, dynamic> toConnectParams(String? nonce) => {
        'auth': {'token': _token},
        'device': {
          'id': device.id,
          'publicKey': device.id,
          'signature': 'nosig',
          'signedAt': DateTime.now().millisecondsSinceEpoch,
          'nonce': nonce ?? '',
        },
      };
}
