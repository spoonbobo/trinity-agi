/**
 * RBAC constants — 1:1 port of core/rbac_constants.dart
 */

export const Permissions = {
  chatRead: 'chat.read',
  chatSend: 'chat.send',
  canvasView: 'canvas.view',
  memoryRead: 'memory.read',
  memoryWrite: 'memory.write',
  skillsList: 'skills.list',
  skillsInstall: 'skills.install',
  skillsManage: 'skills.manage',
  cronsList: 'crons.list',
  cronsManage: 'crons.manage',
  terminalExecSafe: 'terminal.exec.safe',
  terminalExecStandard: 'terminal.exec.standard',
  terminalExecPrivileged: 'terminal.exec.privileged',
  settingsRead: 'settings.read',
  settingsAdmin: 'settings.admin',
  governanceView: 'governance.view',
  governanceResolve: 'governance.resolve',
  acpSpawn: 'acp.spawn',
  acpManage: 'acp.manage',
  usersList: 'users.list',
  usersManage: 'users.manage',
  auditRead: 'audit.read',
} as const;

export const guestPermissions = [
  Permissions.chatRead,
  Permissions.chatSend,
  Permissions.canvasView,
  Permissions.memoryRead,
  Permissions.skillsList,
  Permissions.cronsList,
  Permissions.settingsRead,
  Permissions.governanceView,
];

export const userPermissions = [
  Permissions.memoryWrite,
  Permissions.skillsInstall,
  Permissions.cronsManage,
  Permissions.terminalExecSafe,
  Permissions.terminalExecStandard,
  Permissions.governanceResolve,
  Permissions.acpSpawn,
];

export const adminPermissions = [
  Permissions.skillsManage,
  Permissions.terminalExecPrivileged,
  Permissions.settingsAdmin,
  Permissions.acpManage,
  Permissions.usersList,
  Permissions.usersManage,
  Permissions.auditRead,
];

export const Roles = {
  guest: 'guest',
  user: 'user',
  admin: 'admin',
  superadmin: 'superadmin',
} as const;
