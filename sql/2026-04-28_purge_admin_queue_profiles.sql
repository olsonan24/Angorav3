-- Purge developer / QA / unwanted profiles from angora_user_profiles so they
-- never show up in the admin approval queue, summary cards, or any future
-- super-admin tooling. The Garden frontend already filters these out client-
-- side as a belt-and-suspenders safeguard, but this SQL removes the rows from
-- the database itself so they truly aren't there anymore.
--
-- Run this once in Supabase → SQL editor. It's idempotent — re-running is a
-- no-op once the rows are gone.
--
-- NOTE: this only removes the row from angora_user_profiles. The matching
-- entry in auth.users (if any) is managed by Supabase Auth and lives in a
-- separate schema. To fully delete the auth account too, go to
-- Supabase Dashboard → Authentication → Users, find the email, and click
-- "Delete user". That step requires the dashboard (or the service-role admin
-- API) and can't be done from inside the SQL editor with normal privileges.

BEGIN;

-- 1. Delete by exact email (case-insensitive).
DELETE FROM public.angora_user_profiles
WHERE LOWER(TRIM(email)) IN (
  'proabdulbasit.me@gmail.com',
  'proabulbasit.me@gmail.com',  -- typo'd version, just in case
  'user@gmail.com',
  'qa-viktor@joinangora.com'
);

-- 2. Delete anything whose email or name contains 'viktor' or 'basit'.
--    Belt-and-suspenders: if a new test/dev account ever gets registered
--    with one of those keywords, this scrubs it on the next migration run.
DELETE FROM public.angora_user_profiles
WHERE
     email      ILIKE '%viktor%'
  OR email      ILIKE '%basit%'
  OR full_name  ILIKE '%viktor%'
  OR full_name  ILIKE '%basit%'
  OR first_name ILIKE '%viktor%'
  OR first_name ILIKE '%basit%'
  OR last_name  ILIKE '%viktor%'
  OR last_name  ILIKE '%basit%';

-- 3. Sanity check — show what's left so you can confirm only your account
--    (alex@joinangora.com) and any real teammates remain.
-- SELECT email, full_name, role, approval_status, created_at
--   FROM public.angora_user_profiles
--  ORDER BY created_at DESC;

COMMIT;
