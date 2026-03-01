import 'package:flutter_test/flutter_test.dart';
import 'package:trinity_shell/core/auth_client.dart';

void main() {
  group('AuthRole', () {
    test('parseRole handles all roles', () {
      expect(parseRole('guest'), AuthRole.guest);
      expect(parseRole('user'), AuthRole.user);
      expect(parseRole('admin'), AuthRole.admin);
      expect(parseRole('superadmin'), AuthRole.superadmin);
    });

    test('parseRole defaults to guest for unknown', () {
      expect(parseRole(null), AuthRole.guest);
      expect(parseRole(''), AuthRole.guest);
      expect(parseRole('unknown'), AuthRole.guest);
    });

    test('roleToString is inverse of parseRole', () {
      for (final role in AuthRole.values) {
        expect(parseRole(roleToString(role)), role);
      }
    });
  });

  group('AuthState', () {
    test('default state is unauthenticated guest', () {
      const state = AuthState();
      expect(state.token, isNull);
      expect(state.role, AuthRole.guest);
      expect(state.isGuest, true);
      expect(state.isAuthenticated, false);
      expect(state.permissions, isEmpty);
    });

    test('authenticated state', () {
      const state = AuthState(
        token: 'jwt-token',
        userId: 'user-1',
        email: 'alice@test.com',
        role: AuthRole.admin,
        permissions: ['users.list', 'users.manage', 'chat.send'],
        isGuest: false,
      );
      expect(state.isAuthenticated, true);
      expect(state.isGuest, false);
      expect(state.hasPermission('users.list'), true);
      expect(state.hasPermission('nonexistent'), false);
    });

    test('hasPermission checks correctly', () {
      const state = AuthState(
        token: 'tok',
        permissions: ['chat.send', 'chat.read'],
        isGuest: false,
      );
      expect(state.hasPermission('chat.send'), true);
      expect(state.hasPermission('chat.read'), true);
      expect(state.hasPermission('users.list'), false);
    });

    test('copyWith preserves unmodified fields', () {
      const original = AuthState(
        token: 'tok',
        userId: 'u1',
        email: 'a@b.com',
        role: AuthRole.user,
        permissions: ['chat.send'],
        isGuest: false,
      );
      final updated = original.copyWith(role: AuthRole.admin);
      expect(updated.token, 'tok');
      expect(updated.userId, 'u1');
      expect(updated.email, 'a@b.com');
      expect(updated.role, AuthRole.admin);
      expect(updated.permissions, ['chat.send']);
      expect(updated.isGuest, false);
    });

    test('guest state is not authenticated even with token', () {
      const state = AuthState(token: 'tok', isGuest: true);
      expect(state.isAuthenticated, false);
    });
  });
}
