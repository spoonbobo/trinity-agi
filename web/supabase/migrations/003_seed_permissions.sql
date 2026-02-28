-- Seed: Permissions and role-permission bindings

-- Insert all permission actions
INSERT INTO rbac.permissions (action, description) VALUES
  -- Chat
  ('chat.read',                 'View chat messages'),
  ('chat.send',                 'Send chat messages'),
  -- Canvas
  ('canvas.view',               'View canvas/A2UI surfaces'),
  -- Memory
  ('memory.read',               'Read workspace memory'),
  ('memory.write',              'Write workspace memory'),
  -- Skills
  ('skills.list',               'List available skills'),
  ('skills.install',            'Install skills from ClawHub'),
  ('skills.manage',             'Manage/remove skills'),
  -- Crons
  ('crons.list',                'List cron jobs'),
  ('crons.manage',              'Create/edit/delete cron jobs'),
  -- Terminal
  ('terminal.exec.safe',        'Execute safe read-only terminal commands'),
  ('terminal.exec.standard',    'Execute standard terminal commands'),
  ('terminal.exec.privileged',  'Execute privileged terminal commands'),
  -- Settings
  ('settings.read',             'View settings'),
  ('settings.admin',            'Modify system settings'),
  -- Governance
  ('governance.view',           'View approval requests'),
  ('governance.resolve',        'Approve/reject governance requests'),
  -- ACP
  ('acp.spawn',                 'Spawn ACP agent sessions'),
  ('acp.manage',                'Manage ACP sessions (cancel/close/steer)'),
  -- Users
  ('users.list',                'List users and roles'),
  ('users.manage',              'Assign/revoke user roles'),
  -- Audit
  ('audit.read',                'View audit log');

-- Guest permissions (read-only)
INSERT INTO rbac.role_permissions (role_id, permission_id)
  SELECT r.id, p.id
  FROM rbac.roles r, rbac.permissions p
  WHERE r.name = 'guest' AND p.action IN (
    'chat.read',
    'canvas.view',
    'memory.read',
    'skills.list',
    'crons.list',
    'settings.read',
    'governance.view',
    'terminal.exec.safe'
  );

-- User permissions (standard operational)
INSERT INTO rbac.role_permissions (role_id, permission_id)
  SELECT r.id, p.id
  FROM rbac.roles r, rbac.permissions p
  WHERE r.name = 'user' AND p.action IN (
    'chat.send',
    'memory.write',
    'skills.install',
    'crons.manage',
    'terminal.exec.standard',
    'governance.resolve',
    'acp.spawn'
  );

-- Admin permissions (configuration + management)
INSERT INTO rbac.role_permissions (role_id, permission_id)
  SELECT r.id, p.id
  FROM rbac.roles r, rbac.permissions p
  WHERE r.name = 'admin' AND p.action IN (
    'skills.manage',
    'terminal.exec.privileged',
    'settings.admin',
    'acp.manage',
    'users.list',
    'users.manage',
    'audit.read'
  );
