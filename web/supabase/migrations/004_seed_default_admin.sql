-- Seed default superadmin account: admin@trinity.local / admin
-- GoTrue auto-confirms email (GOTRUE_MAILER_AUTOCONFIRM=true)
-- This migration is idempotent; it only inserts if the user doesn't exist.

-- Note: GoTrue manages auth.users directly via its API, so we create
-- the admin user through GoTrue signup at bootstrap time instead of
-- inserting directly into auth.users (which would bypass password hashing).
-- See bootstrap-openclaw.sh for the curl call that creates this user.
-- This file only assigns the superadmin role once the user exists.

-- The bootstrap script sets the user_id after signup and runs:
--   INSERT INTO rbac.user_roles ...
-- This file is kept as documentation of the default admin policy.
