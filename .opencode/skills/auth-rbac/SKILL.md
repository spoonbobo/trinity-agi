---
name: auth-rbac
description: Manage the Trinity AGI auth service and RBAC system -- database schema, role hierarchy, permission management, JWT flow, audit logging, and API endpoints.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: trinity
---

## What This Skill Covers

The auth-service and RBAC system that powers Trinity AGI's access control. Covers the PostgreSQL schema, role hierarchy, permission enforcement, JWT authentication flow, audit logging, and API endpoints.

Source: `app/auth-service/`, `app/supabase/migrations/`, `app/rbac/`

## Architecture Overview

```
Browser -> GoTrue (email/password or Keycloak OIDC) -> JWT
       -> auth-service /auth/me (Bearer JWT)
       -> verifyToken middleware -> resolveRole middleware
       -> DB: ensureUserRole() -> effective_permissions() recursive CTE
       -> Response: {role, permissions[]}
       -> Frontend stores in localStorage + Riverpod AuthState
       -> GET /auth/openclaws -> orchestrator (3s timeout) -> enriched list
       -> Auto-select first ready instance -> connect gateway WebSocket
```

**Orchestrator dependency:** The auth-service makes outbound HTTP calls to the gateway-orchestrator (`ORCHESTRATOR_URL`) for OpenClaw lifecycle operations. All orchestrator calls use `AbortSignal.timeout()` to prevent hangs:
- `fetchAssignedOpenClawsForUser()`: 3s timeout
- Status enrichment per-claw: 2.5s timeout

If the orchestrator is down, `/auth/openclaws` will fail after 3s instead of hanging indefinitely.

**Guest flow:** `POST /auth/guest` issues a limited JWT (1hr TTL, role=guest, safe-tier permissions).

## Database Schema (`rbac` schema in PostgreSQL)

### Tables

| Table | Key Columns | Purpose |
|-------|-------------|---------|
| `rbac.roles` | id (UUID PK), name (unique), parent_id (self-FK), description | Role hierarchy |
| `rbac.permissions` | id (UUID PK), action (unique), description | Permission definitions |
| `rbac.role_permissions` | (role_id, permission_id) composite PK | Direct role-permission mapping |
| `rbac.user_roles` | (user_id, role_id) composite PK, granted_by, granted_at | User-role assignment |
| `rbac.audit_log` | id, user_id, action, resource, metadata (JSONB), ip, created_at | Audit trail |

Indexes on `audit_log`: `user_id`, `action`, `created_at DESC`.

### SQL Functions

| Function | Returns | Purpose |
|----------|---------|---------|
| `rbac.effective_permissions(user_id)` | TABLE(action TEXT) | Recursive CTE walks role hierarchy via parent_id, returns all inherited + direct permissions |
| `rbac.has_permission(user_id, action)` | BOOLEAN | Thin wrapper around effective_permissions |
| `rbac.user_role_name(user_id)` | TEXT | Returns highest-priority role (superadmin > admin > user > guest) |

### Role Hierarchy

```
superadmin (tier: privileged) -- 0 direct permissions, inherits all
  -> admin (tier: privileged) -- 7 direct: skills.manage, terminal.exec.privileged, settings.admin, acp.manage, users.list, users.manage, audit.read
    -> user (tier: standard) -- 7 direct: chat.send, memory.write, skills.install, crons.manage, terminal.exec.standard, governance.resolve, acp.spawn
      -> guest (tier: safe) -- 8 direct: chat.read, canvas.view, memory.read, skills.list, crons.list, settings.read, governance.view, terminal.exec.safe
```

The recursive CTE walks UP the parent chain. Admin inherits user + guest = 22 total permissions. Superadmin inherits everything.

### Migrations

| File | Purpose |
|------|---------|
| `001_rbac_schema.sql` | Creates schema, tables, functions, indexes |
| `002_seed_roles.sql` | Seeds 4 roles with parent hierarchy |
| `003_seed_permissions.sql` | Seeds 22 permissions + role-permission bindings |
| `004_seed_default_admin.sql` | Documentation: admin created via GoTrue at bootstrap |

## Auth Service (`app/auth-service/`)

Stack: Express.js, jsonwebtoken, pg, js-yaml

### Middleware Chain

1. **`verifyToken`** -- Extracts `Authorization: Bearer <token>`, verifies JWT with `JWT_SECRET`. Missing token = guest.
2. **`resolveRole`** -- Calls `ensureUserRole(userId)` then `getEffectivePermissions(userId)`.
3. **`requirePermission(action)`** -- Checks `req.user.permissions.includes(action)`. 403 + audit log on denial.

### API Endpoints

| Method | Path | Auth | Permission | Purpose |
|--------|------|------|------------|---------|
| GET | /auth/health | none | none | Health check |
| GET | /auth/me | Bearer JWT | none | Current user info + permissions |
| GET | /auth/permissions | Bearer JWT | none | Flat permission list |
| POST | /auth/session | Bearer JWT | none | Exchange JWT for gateway session token |
| POST | /auth/guest | none | none | Issue guest JWT (1hr TTL) |
| GET | /auth/users | Bearer JWT | users.list | List all users with roles |
| POST | /auth/users/:id/role | Bearer JWT | users.manage | Assign role (guest/user/admin) |
| GET | /auth/users/audit | Bearer JWT | audit.read | Paginated audit log |
| GET | /auth/users/roles/permissions | Bearer JWT | users.list | Role-permission matrix |
| PUT | /auth/users/roles/:role/permissions | Bearer JWT | users.manage | Update role permissions |

#### OpenClaw Management Endpoints

| Method | Path | Auth | Permission | Purpose |
|--------|------|------|------------|---------|
| GET | /auth/openclaws | Bearer JWT | none (non-guest) | List assigned OpenClaw instances (calls orchestrator, 3s timeout) |
| GET | /auth/openclaws/:id/status | Bearer JWT | access check | OpenClaw pod status |
| GET | /auth/openclaws/:id/config | Bearer JWT | access check | Get OpenClaw config (openclaw.json) |
| PATCH | /auth/openclaws/:id/config | Bearer JWT | access check | Update OpenClaw config |
| GET | /auth/openclaws/:id/delegation-token | Bearer JWT | access check | Get delegation token |
| POST | /auth/openclaws/create | Bearer JWT | admin+ | Create new OpenClaw instance |
| DELETE | /auth/openclaws/:id | Bearer JWT | admin+ | Delete OpenClaw instance |
| POST | /auth/openclaws/:id/assign | Bearer JWT | admin+ | Assign OpenClaw to user |
| POST | /auth/openclaws/:id/unassign | Bearer JWT | admin+ | Unassign OpenClaw from user |
| GET | /auth/openclaws/fleet/sessions | Bearer JWT | admin+ | Fleet-wide session overview |
| GET | /auth/openclaws/fleet/health | Bearer JWT | admin+ | Fleet-wide health overview |

Access check: user must own the OpenClaw (via orchestrator lookup) or be admin+.

### Key rbac.js Functions

| Function | Purpose |
|----------|---------|
| `getEffectivePermissions(userId)` | Calls recursive CTE, returns action[] |
| `hasPermission(userId, action)` | Boolean check via SQL function |
| `getUserRoleName(userId)` | Highest-priority role name |
| `assignRole(userId, roleName, grantedBy)` | DELETE all + INSERT (single-role enforcement) |
| `ensureRole(userId, roleName, grantedBy)` | INSERT ON CONFLICT DO NOTHING (additive) |
| `ensureUserRole(userId, defaultRole)` | Auto-assign default role on first login |
| `listUsers()` | All users with role names |
| `getRolePermissionMatrix()` | Full matrix for admin UI |
| `setRolePermissions(roleName, actions)` | Transactional replace of role-permission bindings |
| `writeAuditLog(...)` | Insert audit record |
| `getAuditLog(limit, offset)` | Paginated audit query |

### Key auth.js Functions (OpenClaw routes)

| Function | Purpose |
|----------|---------|
| `fetchAssignedOpenClawsForUser(userId)` | Calls orchestrator `GET /users/:id/openclaws` with 3s `AbortSignal.timeout` |
| `assertOpenClawAccess(req, openclawId)` | Verifies user owns the claw or is admin+; throws 401/403 |

### Audit Events

Automatically logged: `login.success`, `login.failed`, `permission.denied`, `auth.session.create`, `users.role.assign`, `role.assigned`, `role.ensured`, `permissions.updated`

## YAML Registry (`app/rbac/permissions.yaml`)

Three identical copies at: `app/rbac/`, `app/auth-service/rbac/`, `app/terminal-proxy/rbac/`

The YAML is the declarative specification. The DB is the runtime store. They encode the same information in different formats:
- YAML `tier` field = which role gets this permission (denormalized)
- DB `role_permissions` = many-to-many join rows (normalized)
- YAML terminal tiers = command classification for terminal proxy (not in DB)

### Terminal Command Tiers

| Tier | Commands |
|------|----------|
| safe | status, health, models, skills list [--json], crons/cron list [--json], cat MEMORY.md |
| standard | doctor, skills, cron, clawhub, sessions list, logs, channels, tools, memory, config get, config validate |
| privileged | doctor --fix, configure, onboard, dashboard, config set |

**Matching algorithm:** Most-specific (longest) prefix match wins across all tiers. `doctor --fix` matches privileged even though `doctor` is standard.

## Bootstrap Flow

On auth-service startup (`ensureDefaultSuperadmin()`):
1. Check `ENABLE_DEFAULT_SUPERADMIN` env
2. Sign up/in via GoTrue with `DEFAULT_SUPERADMIN_EMAIL` / `DEFAULT_SUPERADMIN_PASSWORD`
3. Check `SUPERADMIN_ALLOWLIST` for allowed user IDs
4. Call `ensureRole(userId, 'superadmin')` to assign all hierarchy roles

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| AUTH_SERVICE_PORT | 18791 | Express listen port |
| JWT_SECRET | (= SUPABASE_JWT_SECRET) | JWT verification secret |
| SUPABASE_AUTH_URL | http://supabase-auth:9999 | GoTrue API base URL |
| ENABLE_DEFAULT_SUPERADMIN | true | Bootstrap admin on startup |
| DEFAULT_SUPERADMIN_EMAIL | admin@trinity.work | Default admin email |
| DEFAULT_SUPERADMIN_PASSWORD | admin | Default admin password |
| SUPERADMIN_ALLOWLIST | (empty) | Comma-separated allowed superadmin IDs |
| POSTGRES_HOST | supabase-db | DB host |
| POSTGRES_DB | supabase | DB name |
| OPENCLAW_GATEWAY_TOKEN | (from .env) | For issuing gateway session tokens |
| ORCHESTRATOR_URL | http://gateway-orchestrator:18801 | Gateway orchestrator base URL (outbound calls) |
| ORCHESTRATOR_SERVICE_TOKEN | (from Vault) | Bearer token for orchestrator API calls |

## Common Tasks

**Add a new permission:**
1. Add to `app/supabase/migrations/003_seed_permissions.sql`
2. Add to `app/rbac/permissions.yaml` (all 3 copies)
3. Add to `app/frontend/lib/core/rbac_constants.dart`
4. Assign to a role in the migration + YAML
5. Run migration or use admin UI matrix editor

**Change role hierarchy:**
Modify `parent_id` in `002_seed_roles.sql`. The recursive CTE automatically handles inheritance.

**Check effective permissions for a user:**
```sql
SELECT * FROM rbac.effective_permissions('user-uuid-here');
```
