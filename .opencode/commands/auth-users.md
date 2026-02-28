---
description: List users and their RBAC roles from the auth-service database
---

Query the auth-service database for all users and their roles:

!`docker exec trinity-supabase-db psql -U postgres -d supabase -c "SELECT ur.user_id, r.name AS role, ur.granted_at FROM rbac.user_roles ur JOIN rbac.roles r ON r.id = ur.role_id ORDER BY ur.granted_at DESC;"`

Also show the role hierarchy:

!`docker exec trinity-supabase-db psql -U postgres -d supabase -c "SELECT r.name, p.name AS parent FROM rbac.roles r LEFT JOIN rbac.roles p ON r.parent_id = p.id ORDER BY CASE r.name WHEN 'superadmin' THEN 0 WHEN 'admin' THEN 1 WHEN 'user' THEN 2 WHEN 'guest' THEN 3 END;"`

Summarize the user list, their roles, and the role hierarchy.
