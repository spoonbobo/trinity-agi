const {
  loadRegistry,
  getRoleTier,
  isCommandAllowedForTier,
  getAllowedCommands,
  getInteractiveCommands,
} = require('./rbac-registry');

describe('Terminal Proxy RBAC Registry', () => {
  
  describe('loadRegistry', () => {
    it('should load the permissions.yaml file', () => {
      const registry = loadRegistry();
      expect(registry).not.toBeNull();
      expect(registry.terminal).toBeDefined();
    });
  });

  describe('role tier mapping', () => {
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
  });

  describe('command authorization', () => {
    it('should allow safe commands for guest', () => {
      expect(isCommandAllowedForTier('status', 'safe')).toBe(true);
      expect(isCommandAllowedForTier('health', 'safe')).toBe(true);
      expect(isCommandAllowedForTier('models', 'safe')).toBe(true);
      expect(isCommandAllowedForTier('skills list', 'safe')).toBe(true);
      expect(isCommandAllowedForTier('crons list', 'safe')).toBe(true);
    });

    it('should allow safe and standard commands for user', () => {
      expect(isCommandAllowedForTier('status', 'standard')).toBe(true);
      expect(isCommandAllowedForTier('doctor', 'standard')).toBe(true);
      expect(isCommandAllowedForTier('sessions list', 'standard')).toBe(true);
    });

    it('should allow all commands for admin', () => {
      expect(isCommandAllowedForTier('status', 'privileged')).toBe(true);
      expect(isCommandAllowedForTier('doctor', 'privileged')).toBe(true);
      expect(isCommandAllowedForTier('doctor --fix', 'privileged')).toBe(true);
      expect(isCommandAllowedForTier('configure', 'privileged')).toBe(true);
      expect(isCommandAllowedForTier('config set', 'privileged')).toBe(true);
    });

    it('should block privileged commands for safe tier', () => {
      expect(isCommandAllowedForTier('configure', 'safe')).toBe(false);
      expect(isCommandAllowedForTier('doctor --fix', 'safe')).toBe(false);
      expect(isCommandAllowedForTier('onboard', 'safe')).toBe(false);
      expect(isCommandAllowedForTier('dashboard', 'safe')).toBe(false);
      expect(isCommandAllowedForTier('config set', 'safe')).toBe(false);
    });

    it('should block privileged commands for standard tier', () => {
      expect(isCommandAllowedForTier('configure', 'standard')).toBe(false);
      expect(isCommandAllowedForTier('doctor --fix', 'standard')).toBe(false);
      expect(isCommandAllowedForTier('onboard', 'standard')).toBe(false);
    });
  });

  describe('allowed commands', () => {
    it('should return all allowed commands', () => {
      const commands = getAllowedCommands();
      expect(commands.length).toBeGreaterThan(0);
      expect(commands).toContain('status');
      expect(commands).toContain('doctor');
      expect(commands).toContain('configure');
    });

    it('should not have duplicates', () => {
      const commands = getAllowedCommands();
      const unique = new Set(commands);
      expect(unique.size).toBe(commands.length);
    });
  });

  describe('interactive commands', () => {
    it('should return interactive commands', () => {
      const interactive = getInteractiveCommands();
      expect(interactive).toContain('configure');
      expect(interactive).toContain('onboard');
      expect(interactive).toContain('channels login');
    });
  });
});
