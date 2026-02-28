class Permissions {
  static const chatRead = 'chat.read';
  static const chatSend = 'chat.send';
  
  static const canvasView = 'canvas.view';
  
  static const memoryRead = 'memory.read';
  static const memoryWrite = 'memory.write';
  
  static const skillsList = 'skills.list';
  static const skillsInstall = 'skills.install';
  static const skillsManage = 'skills.manage';
  
  static const cronsList = 'crons.list';
  static const cronsManage = 'crons.manage';
  
  static const terminalExecSafe = 'terminal.exec.safe';
  static const terminalExecStandard = 'terminal.exec.standard';
  static const terminalExecPrivileged = 'terminal.exec.privileged';
  
  static const settingsRead = 'settings.read';
  static const settingsAdmin = 'settings.admin';
  
  static const governanceView = 'governance.view';
  static const governanceResolve = 'governance.resolve';
  
  static const acpSpawn = 'acp.spawn';
  static const acpManage = 'acp.manage';
  
  static const usersList = 'users.list';
  static const usersManage = 'users.manage';
  
  static const auditRead = 'audit.read';

  static const List<String> guestPermissions = [
    chatRead,
    canvasView,
    memoryRead,
    skillsList,
    cronsList,
    settingsRead,
    governanceView,
    terminalExecSafe,
  ];

  static const List<String> userPermissions = [
    chatSend,
    memoryWrite,
    skillsInstall,
    cronsManage,
    terminalExecStandard,
    governanceResolve,
    acpSpawn,
  ];

  static const List<String> adminPermissions = [
    skillsManage,
    terminalExecPrivileged,
    settingsAdmin,
    acpManage,
    usersList,
    usersManage,
    auditRead,
  ];
}

class Roles {
  static const guest = 'guest';
  static const user = 'user';
  static const admin = 'admin';
  static const superadmin = 'superadmin';
}
