import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

const _tokenKey = 'trinity_auth_token';
const _roleKey = 'trinity_auth_role';
const _permissionsKey = 'trinity_auth_permissions';
const _userIdKey = 'trinity_auth_user_id';
const _emailKey = 'trinity_auth_email';

enum AuthRole { guest, user, admin, superadmin }

AuthRole parseRole(String? name) {
  switch (name) {
    case 'superadmin':
      return AuthRole.superadmin;
    case 'admin':
      return AuthRole.admin;
    case 'user':
      return AuthRole.user;
    default:
      return AuthRole.guest;
  }
}

String roleToString(AuthRole role) {
  switch (role) {
    case AuthRole.superadmin:
      return 'superadmin';
    case AuthRole.admin:
      return 'admin';
    case AuthRole.user:
      return 'user';
    case AuthRole.guest:
      return 'guest';
  }
}

class AuthState {
  final String? token;
  final String? userId;
  final String? email;
  final AuthRole role;
  final List<String> permissions;
  final bool isGuest;

  const AuthState({
    this.token,
    this.userId,
    this.email,
    this.role = AuthRole.guest,
    this.permissions = const [],
    this.isGuest = true,
  });

  bool hasPermission(String action) => permissions.contains(action);

  bool get isAuthenticated => !isGuest && token != null;

  AuthState copyWith({
    String? token,
    String? userId,
    String? email,
    AuthRole? role,
    List<String>? permissions,
    bool? isGuest,
  }) {
    return AuthState(
      token: token ?? this.token,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
      isGuest: isGuest ?? this.isGuest,
    );
  }
}

class AuthClient extends ChangeNotifier {
  AuthState _state = const AuthState();
  AuthState get state => _state;

  final String authServiceBaseUrl;

  AuthClient({required this.authServiceBaseUrl}) {
    _restoreFromStorage();
  }

  void _restoreFromStorage() {
    final token = html.window.localStorage[_tokenKey];
    final role = html.window.localStorage[_roleKey];
    final permsJson = html.window.localStorage[_permissionsKey];
    final userId = html.window.localStorage[_userIdKey];
    final email = html.window.localStorage[_emailKey];

    if (token != null && token.isNotEmpty) {
      List<String> permissions = [];
      if (permsJson != null && permsJson.isNotEmpty) {
        try {
          permissions = List<String>.from(jsonDecode(permsJson));
        } catch (_) {}
      }
      _state = AuthState(
        token: token,
        userId: userId,
        email: email,
        role: parseRole(role),
        permissions: permissions,
        isGuest: role == 'guest',
      );
      notifyListeners();
    }
  }

  void _persistToStorage() {
    if (_state.token != null) {
      html.window.localStorage[_tokenKey] = _state.token!;
    } else {
      html.window.localStorage.remove(_tokenKey);
    }
    html.window.localStorage[_roleKey] = roleToString(_state.role);
    html.window.localStorage[_permissionsKey] = jsonEncode(_state.permissions);
    if (_state.userId != null) {
      html.window.localStorage[_userIdKey] = _state.userId!;
    }
    if (_state.email != null) {
      html.window.localStorage[_emailKey] = _state.email!;
    }
  }

  Future<void> loginWithEmail(String email, String password) async {
    // Call GoTrue signup/signin
    final uri = Uri.parse('$authServiceBaseUrl/supabase/auth/v1/token?grant_type=password');
    final request = html.HttpRequest();
    request.open('POST', uri.toString());
    request.setRequestHeader('Content-Type', 'application/json');
    request.setRequestHeader('apikey', const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: ''));

    final completer = _createRequestCompleter(request);
    request.send(jsonEncode({'email': email, 'password': password}));

    final response = await completer;
    final body = jsonDecode(response);
    final accessToken = body['access_token'] as String;

    await _resolveSession(accessToken, email: email);
  }

  Future<void> signUpWithEmail(String email, String password) async {
    final uri = Uri.parse('$authServiceBaseUrl/supabase/auth/v1/signup');
    final request = html.HttpRequest();
    request.open('POST', uri.toString());
    request.setRequestHeader('Content-Type', 'application/json');
    request.setRequestHeader('apikey', const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: ''));

    final completer = _createRequestCompleter(request);
    request.send(jsonEncode({'email': email, 'password': password}));

    final response = await completer;
    final body = jsonDecode(response);
    final accessToken = body['access_token'] as String?;

    if (accessToken != null) {
      await _resolveSession(accessToken, email: email);
    }
  }

  Future<void> loginAsGuest() async {
    final uri = Uri.parse('$authServiceBaseUrl/auth/guest');
    final request = html.HttpRequest();
    request.open('POST', uri.toString());
    request.setRequestHeader('Content-Type', 'application/json');

    final completer = _createRequestCompleter(request);
    request.send('{}');

    final response = await completer;
    final body = jsonDecode(response);

    _state = AuthState(
      token: body['token'] as String,
      role: AuthRole.guest,
      permissions: List<String>.from(body['permissions'] ?? []),
      isGuest: true,
    );
    _persistToStorage();
    notifyListeners();
  }

  Future<void> _resolveSession(String accessToken, {String? email}) async {
    final uri = Uri.parse('$authServiceBaseUrl/auth/me');
    final request = html.HttpRequest();
    request.open('GET', uri.toString());
    request.setRequestHeader('Authorization', 'Bearer $accessToken');

    final completer = _createRequestCompleter(request);
    request.send();

    final response = await completer;
    final body = jsonDecode(response);

    _state = AuthState(
      token: accessToken,
      userId: body['id'] as String?,
      email: email ?? body['email'] as String?,
      role: parseRole(body['role'] as String?),
      permissions: List<String>.from(body['permissions'] ?? []),
      isGuest: body['isGuest'] == true,
    );
    _persistToStorage();
    notifyListeners();
  }

  void logout() {
    _state = const AuthState();
    html.window.localStorage.remove(_tokenKey);
    html.window.localStorage.remove(_roleKey);
    html.window.localStorage.remove(_permissionsKey);
    html.window.localStorage.remove(_userIdKey);
    html.window.localStorage.remove(_emailKey);
    notifyListeners();
  }

  String getKeycloakLoginUrl() {
    return '$authServiceBaseUrl/supabase/auth/v1/authorize?provider=keycloak';
  }

  Future<String> _createRequestCompleter(html.HttpRequest request) {
    final completer = Future<String>.delayed(Duration.zero, () async {
      await request.onLoadEnd.first;
      if (request.status! >= 200 && request.status! < 300) {
        return request.responseText ?? '{}';
      }
      throw Exception('HTTP ${request.status}: ${request.responseText}');
    });
    return completer;
  }
}
