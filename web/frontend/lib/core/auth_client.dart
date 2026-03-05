import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show ChangeNotifier, kDebugMode, debugPrint;

const _tokenKey = 'trinity_auth_token';
const _roleKey = 'trinity_auth_role';
const _permissionsKey = 'trinity_auth_permissions';
const _userIdKey = 'trinity_auth_user_id';
const _emailKey = 'trinity_auth_email';
const _activeOpenClawIdKey = 'trinity_active_openclaw_id';

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
  final List<OpenClawInfo> openclaws;
  final String? activeOpenClawId;

  const AuthState({
    this.token,
    this.userId,
    this.email,
    this.role = AuthRole.guest,
    this.permissions = const [],
    this.isGuest = true,
    this.openclaws = const [],
    this.activeOpenClawId,
  });

  bool hasPermission(String action) => permissions.contains(action);

  bool get isAuthenticated => !isGuest && token != null;

  /// The currently selected OpenClaw instance, or null if none selected.
  OpenClawInfo? get activeOpenClaw {
    if (activeOpenClawId == null) return null;
    try {
      return openclaws.firstWhere((oc) => oc.id == activeOpenClawId);
    } catch (_) {
      return null;
    }
  }

  AuthState copyWith({
    String? token,
    String? userId,
    String? email,
    AuthRole? role,
    List<String>? permissions,
    bool? isGuest,
    List<OpenClawInfo>? openclaws,
    String? activeOpenClawId,
    bool clearActiveOpenClawId = false,
  }) {
    return AuthState(
      token: token ?? this.token,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
      isGuest: isGuest ?? this.isGuest,
      openclaws: openclaws ?? this.openclaws,
      activeOpenClawId: clearActiveOpenClawId ? null : (activeOpenClawId ?? this.activeOpenClawId),
    );
  }
}

/// Status of the user's assigned OpenClaw instances.
enum OpenClawStatus { unknown, loading, ready, noOpenClaws, error }

/// Describes an admin-managed shared OpenClaw instance assigned to a user.
class OpenClawInfo {
  final String id;
  final String name;
  final String? description;
  final String status;
  final bool ready;
  final int? userCount;

  const OpenClawInfo({
    required this.id,
    required this.name,
    this.description,
    required this.status,
    required this.ready,
    this.userCount,
  });

  factory OpenClawInfo.fromJson(Map<String, dynamic> json) {
    return OpenClawInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      status: json['status'] as String? ?? 'unknown',
      ready: json['ready'] as bool? ?? false,
      userCount: json['userCount'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (description != null) 'description': description,
    'status': status,
    'ready': ready,
  };
}

class AuthClient extends ChangeNotifier {
  AuthState _state = const AuthState();
  AuthState get state => _state;

  final String authServiceBaseUrl;

  /// Status of the user's assigned OpenClaw instances.
  OpenClawStatus _openClawStatus = OpenClawStatus.unknown;
  OpenClawStatus get openClawStatus => _openClawStatus;

  /// Human-readable error when [openClawStatus] is [OpenClawStatus.error].
  String? _openClawError;
  String? get openClawError => _openClawError;

  AuthClient({required this.authServiceBaseUrl}) {
    _restoreFromStorage();
  }

  void _restoreFromStorage() {
    final token = html.window.localStorage[_tokenKey];
    final role = html.window.localStorage[_roleKey];
    final permsJson = html.window.localStorage[_permissionsKey];
    final userId = html.window.localStorage[_userIdKey];
    final email = html.window.localStorage[_emailKey];
    final activeOpenClawId = html.window.localStorage[_activeOpenClawIdKey];

    if (token != null && token.isNotEmpty) {
      List<String> permissions = [];
      if (permsJson != null && permsJson.isNotEmpty) {
        try {
          permissions = List<String>.from(jsonDecode(permsJson));
        } catch (e) {
          if (kDebugMode) debugPrint('[Auth] Failed to parse stored permissions: $e');
        }
      }
      _state = AuthState(
        token: token,
        userId: userId,
        email: email,
        role: parseRole(role),
        permissions: permissions,
        isGuest: role == 'guest',
        activeOpenClawId: activeOpenClawId,
      );
      notifyListeners();

      // Restored session — fetch the user's assigned OpenClaw instances.
      fetchUserOpenClaws();
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
    if (_state.activeOpenClawId != null) {
      html.window.localStorage[_activeOpenClawIdKey] = _state.activeOpenClawId!;
    } else {
      html.window.localStorage.remove(_activeOpenClawIdKey);
    }
  }

  Future<void> loginWithEmail(String email, String password) async {
    // Call GoTrue signup/signin
    final uri = Uri.parse('$authServiceBaseUrl/supabase/auth/token?grant_type=password');
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
    final uri = Uri.parse('$authServiceBaseUrl/supabase/auth/signup');
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

    // Fetch the user's assigned OpenClaw instances.
    fetchUserOpenClaws();
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

    // Fetch the user's assigned OpenClaw instances.
    // Fire-and-forget: the UI observes openClawStatus reactively.
    fetchUserOpenClaws();
  }

  /// Resolve session from an SSO access token (used after OAuth callback).
  Future<void> resolveSessionFromToken(String accessToken) async {
    await _resolveSession(accessToken);
  }

  // ---------------------------------------------------------------------------
  // OpenClaw instance management
  // ---------------------------------------------------------------------------

  /// Fetch the list of shared OpenClaw instances assigned to the current user
  /// via `GET /auth/openclaws`. Called automatically after login or session
  /// restore. The UI can observe [openClawStatus] reactively.
  Future<void> fetchUserOpenClaws() async {
    if (_state.token == null) return;

    _openClawStatus = OpenClawStatus.loading;
    _openClawError = null;
    notifyListeners();

    try {
      final uri = Uri.parse('$authServiceBaseUrl/auth/openclaws');
      final request = html.HttpRequest();
      request.open('GET', uri.toString());
      request.setRequestHeader('Authorization', 'Bearer ${_state.token}');

      final completer = _createRequestCompleter(request);
      request.send();

      final responseText = await completer.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Request timed out after 15 seconds');
        },
      );
      final decoded = jsonDecode(responseText);
      // The endpoint returns either a plain array or {"openclaws": [...]}
      final List rawList;
      if (decoded is List) {
        rawList = decoded;
      } else if (decoded is Map) {
        rawList = (decoded['openclaws'] as List?) ?? [];
      } else {
        rawList = [];
      }
      final openclaws = rawList
          .map((e) => OpenClawInfo.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      if (openclaws.isEmpty) {
        _state = _state.copyWith(
          openclaws: openclaws,
          clearActiveOpenClawId: true,
        );
        _openClawStatus = OpenClawStatus.noOpenClaws;
        _persistToStorage();
        notifyListeners();
        if (kDebugMode) debugPrint('[Auth] No OpenClaws assigned to user');
        return;
      }

      // Auto-select: prefer the previously persisted ID if it's still in the
      // list, otherwise pick the first ready instance, or just the first one.
      final persistedId = _state.activeOpenClawId;
      String selectedId;
      if (persistedId != null && openclaws.any((oc) => oc.id == persistedId)) {
        selectedId = persistedId;
      } else {
        final firstReady = openclaws.where((oc) => oc.ready).toList();
        selectedId = firstReady.isNotEmpty ? firstReady.first.id : openclaws.first.id;
      }

      _state = _state.copyWith(
        openclaws: openclaws,
        activeOpenClawId: selectedId,
      );
      _openClawStatus = OpenClawStatus.ready;
      _persistToStorage();
      notifyListeners();
      if (kDebugMode) {
        debugPrint('[Auth] Fetched ${openclaws.length} OpenClaw(s), active: $selectedId');
      }
    } catch (e) {
      _openClawStatus = OpenClawStatus.error;
      _openClawError = 'Failed to fetch OpenClaws: $e';
      notifyListeners();
      if (kDebugMode) debugPrint('[Auth] fetchUserOpenClaws error: $e');
    }
  }

  /// Switch the active OpenClaw instance. The [id] must be present in the
  /// current [state.openclaws] list.
  void selectOpenClaw(String id) {
    if (!_state.openclaws.any((oc) => oc.id == id)) {
      if (kDebugMode) debugPrint('[Auth] selectOpenClaw: unknown id $id');
      return;
    }
    _state = _state.copyWith(activeOpenClawId: id);
    _persistToStorage();
    notifyListeners();
    if (kDebugMode) debugPrint('[Auth] Active OpenClaw switched to $id');
  }

  void logout() {
    _state = const AuthState();
    _openClawStatus = OpenClawStatus.unknown;
    _openClawError = null;
    html.window.localStorage.remove(_tokenKey);
    html.window.localStorage.remove(_roleKey);
    html.window.localStorage.remove(_permissionsKey);
    html.window.localStorage.remove(_userIdKey);
    html.window.localStorage.remove(_emailKey);
    html.window.localStorage.remove(_activeOpenClawIdKey);
    notifyListeners();
  }

  /// Fetch all users with roles. Requires [users.list] permission.
  Future<List<Map<String, dynamic>>> fetchUsers() async {
    final uri = Uri.parse('$authServiceBaseUrl/auth/users');
    final request = html.HttpRequest();
    request.open('GET', uri.toString());
    request.setRequestHeader('Authorization', 'Bearer ${_state.token}');

    final completer = _createRequestCompleter(request);
    request.send();

    final response = await completer;
    final body = jsonDecode(response);
    return List<Map<String, dynamic>>.from(
      (body['users'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? [],
    );
  }

  /// Assign a role to a user. Requires [users.manage] permission.
  Future<void> assignUserRole(String userId, String role) async {
    final uri = Uri.parse('$authServiceBaseUrl/auth/users/$userId/role');
    final request = html.HttpRequest();
    request.open('POST', uri.toString());
    request.setRequestHeader('Content-Type', 'application/json');
    request.setRequestHeader('Authorization', 'Bearer ${_state.token}');

    final completer = _createRequestCompleter(request);
    request.send(jsonEncode({'role': role}));

    await completer;
  }

  /// Fetch paginated audit log. Requires [audit.read] permission.
  Future<List<Map<String, dynamic>>> fetchAuditLog({int limit = 50, int offset = 0}) async {
    final uri = Uri.parse('$authServiceBaseUrl/auth/users/audit?limit=$limit&offset=$offset');
    final request = html.HttpRequest();
    request.open('GET', uri.toString());
    request.setRequestHeader('Authorization', 'Bearer ${_state.token}');

    final completer = _createRequestCompleter(request);
    request.send();

    final response = await completer;
    final body = jsonDecode(response);
    return List<Map<String, dynamic>>.from(
      (body['logs'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? [],
    );
  }

  /// Fetch role-permission matrix. Requires [users.list] permission.
  Future<Map<String, dynamic>> fetchRolePermissionMatrix() async {
    final uri = Uri.parse('$authServiceBaseUrl/auth/users/roles/permissions');
    final request = html.HttpRequest();
    request.open('GET', uri.toString());
    request.setRequestHeader('Authorization', 'Bearer ${_state.token}');

    final completer = _createRequestCompleter(request);
    request.send();

    final response = await completer;
    return Map<String, dynamic>.from(jsonDecode(response) as Map);
  }

  /// Update permissions for a role. Requires [users.manage] permission.
  Future<void> updateRolePermissions(String role, List<String> permissions) async {
    final uri = Uri.parse('$authServiceBaseUrl/auth/users/roles/$role/permissions');
    final request = html.HttpRequest();
    request.open('PUT', uri.toString());
    request.setRequestHeader('Content-Type', 'application/json');
    request.setRequestHeader('Authorization', 'Bearer ${_state.token}');

    final completer = _createRequestCompleter(request);
    request.send(jsonEncode({'permissions': permissions}));

    await completer;
  }

  String getKeycloakLoginUrl() {
    return '$authServiceBaseUrl/supabase/auth/authorize?provider=keycloak';
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
