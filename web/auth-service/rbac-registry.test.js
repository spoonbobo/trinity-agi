const {
  loadRegistry,
  getAllPermissions,
  getPermissionActions,
  getPermissionsByTier,
  getRoleConfig,
  getTerminalCommands,
  isCommandAllowedForTier,
  getRoleTier,
} = require('./src/rbac-registry');

describe('RBAC Permission Registry', () => {
  
  describe('loadRegistry', () => {
    it('should load the permissions.yaml file', () => {
      const registry = loadRegistry();
      expect(registry).not.toBeNull();
      expect(registry.permissions).toBeDefined();
      expect(registry.roles).toBeDefined();
    });
  });

  describe('permissions', () => {
    it('should have all required permission categories', () => {
      const actions = getPermissionActions();
      
      expect(actions).toContain('chat.read');
      expect(actions).toContain('chat.send');
      expect(actions).toContain('canvas.view');
      expect(actions).toContain('memory.read');
      expect(actions).toContain('memory.write');
      expect(actions).toContain('skills.list');
      expect(actions).toContain('skills.install');
      expect(actions).toContain('skills.manage');
      expect(actions).toContain('crons.list');
      expect(actions).toContain('crons.manage');
      expect(actions).toContain('terminal.exec.safe');
      expect(actions).toContain('terminal.exec.standard');
      expect(actions).toContain('terminal.exec.privileged');
      expect(actions).toContain('settings.read');
      expect(actions).toContain('settings.admin');
      expect(actions).toContain('governance.view');
      expect(actions).toContain('governance.resolve');
      expect(actions).toContain('acp.spawn');
      expect(actions).toContain('acp.manage');
      expect(actions).toContain('users.list');
      expect(actions).toContain('users.manage');
      expect(actions).toContain('audit.read');
    });

    it('should have unique permission actions', () => {
      const actions = getPermissionActions();
      const unique = new Set(actions);
      expect(unique.size).toBe(actions.length);
    });

    it('should have description for each permission', () => {
      const perms = getAllPermissions();
      perms.forEach(p => {
        expect(p.action).toBeDefined();
        expect(p.description).toBeDefined();
        expect(p.tier).toBeDefined();
      });
    });

    it('should have valid tier values', () => {
      const validTiers = ['guest', 'user', 'admin'];
      const perms = getAllPermissions();
      perms.forEach(p => {
        expect(validTiers).toContain(p.tier);
      });
    });
  });

  describe('roles', () => {
    it('should have guest, user, admin, superadmin roles', () => {
      const guest = getRoleConfig('guest');
      const user = getRoleConfig('user');
      const admin = getRoleConfig('admin');
      const superadmin = getRoleConfig('superadmin');

      expect(guest).not.toBeNull();
      expect(user).not.toBeNull();
      expect(admin).not.toBeNull();
      expect(superadmin).not.toBeNull();
    });

    it('should have valid tier for each role', () => {
      const validTiers = ['safe', 'standard', 'privileged'];
      ['guest', 'user', 'admin', 'superadmin'].forEach(roleName => {
        const config = getRoleConfig(roleName);
        expect(validTiers).toContain(config.tier);
      });
    });

    it('should map guest to safe tier', () => {
      expect(getRoleTier('guest')).toBe('safe');
    });

    it('should map user to standard tier', () => {
      expect(getRoleTier('user')).toBe('standard');
    });

    it('should map admin to privileged tier', () => {
      expect(getRoleTier('admin')).toBe('privileged');
    });

    it('should map superadmin to privileged tier', () => {
      expect(getRoleTier('superadmin')).toBe('privileged');
    });

    it('should default unknown roles to safe tier', () => {
      expect(getRoleTier('unknown')).toBe('safe');
    });
  });

  describe('permissions by tier', () => {
    it('should get guest permissions for safe tier', () => {
      const perms = getPermissionsByTier('safe');
      expect(perms).toContain('chat.read');
      expect(perms).toContain('canvas.view');
      expect(perms).toContain('terminal.exec.safe');
    });

    it('should include safe permissions in standard tier', () => {
      const standard = getPermissionsByTier('standard');
      const safe = getPermissionsByTier('safe');
      safe.forEach(p => expect(standard).toContain(p));
    });

    it('should include standard permissions in privileged tier', () => {
      const privileged = getPermissionsByTier('privileged');
      const standard = getPermissionsByTier('standard');
      standard.forEach(p => expect(privileged).toContain(p));
    });
  });

  describe('terminal commands', () => {
    it('should have safe commands for guest', () => {
      const commands = getTerminalCommands('safe');
      expect(commands).toContain('status');
      expect(commands).toContain('health');
      expect(commands).toContain('models');
    });

    it('should have standard commands for user', () => {
      const commands = getTerminalCommands('standard');
      expect(commands).toContain('doctor');
      expect(commands).toContain('skills');
      expect(commands).toContain('sessions list');
    });

    it('should have privileged commands for admin', () => {
      const commands = getTerminalCommands('privileged');
      expect(commands).toContain('doctor --fix');
      expect(commands).toContain('configure');
      expect(commands).toContain('config set');
    });

    it('should allow safe commands for standard tier', () => {
      expect(isCommandAllowedForTier('status', 'standard')).toBe(true);
      expect(isCommandAllowedForTier('health', 'standard')).toBe(true);
    });

    it('should allow standard commands for privileged tier', () => {
      expect(isCommandAllowedForTier('doctor', 'privileged')).toBe(true);
      expect(isCommandAllowedForTier('sessions list', 'privileged')).toBe(true);
    });

    it('should NOT allow privileged commands for safe tier', () => {
      expect(isCommandAllowedForTier('configure', 'safe')).toBe(false);
      expect(isCommandAllowedForTier('doctor --fix', 'safe')).toBe(false);
    });

    it('should NOT allow privileged commands for standard tier', () => {
      expect(isCommandAllowedForTier('configure', 'standard')).toBe(false);
      expect(isCommandAllowedForTier('doctor --fix', 'standard')).toBe(false);
    });

    it('should handle commands with openclaw prefix', () => {
      expect(isCommandAllowedForTier('openclaw status', 'safe')).toBe(true);
      expect(isCommandAllowedForTier('openclaw configure', 'safe')).toBe(false);
    });
  });

  describe('security invariants', () => {
    it('should NOT have admin permissions in guest tier', () => {
      const safe = getPermissionsByTier('safe');
      expect(safe).not.toContain('settings.admin');
      expect(safe).not.toContain('users.manage');
      expect(safe).not.toContain('audit.read');
    });

    it('should NOT have user permissions in guest tier', () => {
      const safe = getPermissionsByTier('safe');
      expect(safe).not.toContain('chat.send');
      expect(safe).not.toContain('memory.write');
      expect(safe).not.toContain('skills.install');
    });

    it('should require superadmin/admin for settings.admin', () => {
      const safe = getPermissionsByTier('safe');
      const standard = getPermissionsByTier('standard');
      const privileged = getPermissionsByTier('privileged');
      
      expect(safe).not.toContain('settings.admin');
      expect(standard).not.toContain('settings.admin');
      expect(privileged).toContain('settings.admin');
    });
  });
});
