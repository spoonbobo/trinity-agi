import 'package:flutter_test/flutter_test.dart';
import 'package:trinity_shell/core/rbac_constants.dart';

void main() {
  group('RBAC Constants', () {
    test('guest permissions contain expected safe permissions', () {
      expect(Permissions.guestPermissions, contains('chat.read'));
      expect(Permissions.guestPermissions, contains('canvas.view'));
      expect(Permissions.guestPermissions, contains('memory.read'));
      expect(Permissions.guestPermissions, contains('skills.list'));
      expect(Permissions.guestPermissions, contains('terminal.exec.safe'));
    });

    test('guest permissions do not contain elevated permissions', () {
      expect(Permissions.guestPermissions, isNot(contains('chat.send')));
      expect(Permissions.guestPermissions, isNot(contains('users.list')));
      expect(Permissions.guestPermissions, isNot(contains('terminal.exec.privileged')));
    });

    test('user permissions contain standard permissions', () {
      expect(Permissions.userPermissions, contains('chat.send'));
      expect(Permissions.userPermissions, contains('memory.write'));
      expect(Permissions.userPermissions, contains('skills.install'));
      expect(Permissions.userPermissions, contains('crons.manage'));
      expect(Permissions.userPermissions, contains('governance.resolve'));
    });

    test('admin permissions contain elevated permissions', () {
      expect(Permissions.adminPermissions, contains('users.list'));
      expect(Permissions.adminPermissions, contains('users.manage'));
      expect(Permissions.adminPermissions, contains('audit.read'));
      expect(Permissions.adminPermissions, contains('terminal.exec.privileged'));
      expect(Permissions.adminPermissions, contains('settings.admin'));
    });

    test('role constants are correct', () {
      expect(Roles.guest, 'guest');
      expect(Roles.user, 'user');
      expect(Roles.admin, 'admin');
      expect(Roles.superadmin, 'superadmin');
    });

    test('all permission strings are unique', () {
      final all = [
        ...Permissions.guestPermissions,
        ...Permissions.userPermissions,
        ...Permissions.adminPermissions,
      ];
      expect(all.toSet().length, all.length);
    });

    test('permission hierarchy: guest < user < admin', () {
      // Guest permissions should not overlap with user or admin
      for (final guestPerm in Permissions.guestPermissions) {
        expect(Permissions.userPermissions, isNot(contains(guestPerm)));
        expect(Permissions.adminPermissions, isNot(contains(guestPerm)));
      }
      for (final userPerm in Permissions.userPermissions) {
        expect(Permissions.adminPermissions, isNot(contains(userPerm)));
      }
    });
  });
}
