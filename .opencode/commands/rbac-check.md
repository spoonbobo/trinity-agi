---
description: Check RBAC permissions -- show role-permission matrix and effective permissions
---

Show the full role-permission matrix from the database:

!`docker exec trinity-supabase-db psql -U postgres -d supabase -c "SELECT r.name AS role, p.action AS permission FROM rbac.role_permissions rp JOIN rbac.roles r ON r.id = rp.role_id JOIN rbac.permissions p ON p.id = rp.permission_id ORDER BY CASE r.name WHEN 'guest' THEN 0 WHEN 'user' THEN 1 WHEN 'admin' THEN 2 WHEN 'superadmin' THEN 3 END, p.action;"`

Count permissions per role (direct only, not inherited):

!`docker exec trinity-supabase-db psql -U postgres -d supabase -c "SELECT r.name AS role, COUNT(rp.permission_id) AS direct_perms FROM rbac.roles r LEFT JOIN rbac.role_permissions rp ON rp.role_id = r.id GROUP BY r.name ORDER BY CASE r.name WHEN 'guest' THEN 0 WHEN 'user' THEN 1 WHEN 'admin' THEN 2 WHEN 'superadmin' THEN 3 END;"`

Check recent audit log entries:

!`docker exec trinity-supabase-db psql -U postgres -d supabase -c "SELECT created_at, action, resource, ip FROM rbac.audit_log ORDER BY created_at DESC LIMIT 10;"`

Analyze the RBAC configuration: are permissions properly distributed? Any anomalies?
