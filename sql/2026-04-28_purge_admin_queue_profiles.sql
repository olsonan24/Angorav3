-- Purge developer / QA / test profiles from angora_user_profiles so they
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

-- 1. Delete by exact email (case-insensitive). Add new ones to this list as
--    needed; keep ben@joinangora.com and alex@joinangora.com OFF this list.
DELETE FROM public.angora_user_profiles
WHERE LOWER(TRIM(email)) IN (
  'proabdulbasit.me@gmail.com',
  'proabulbasit.me@gmail.com',
  'user@gmail.com',
  'user2@gmail.com',
  'user4@gmail.com',
  'qa-viktor@joinangora.com',
  'bast1@gmail.com',
  'bart@gmail.com',
  'abc123@gmail.com',
  'team-bot-3026@joinangora.com',
  'youwillalertme@gmail.com',
  'test1243059@gmail.com',
  'test1@gmail.com',
  'test2@gmail.com',
  'test3@gmail.com',
  'test12345@gmail.com',
  'test12345432@gmail.com',
  'test12345654334543@gmail.com',
  'test1234565434543@gmail.com',
  'testteestteststest@gmail.com',
  'test@gmil.com'
);

-- 2. Delete anything whose email or name contains 'viktor' or 'basit'.
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

-- 3. Delete anything whose email looks like a test / placeholder account.
--    Keep ben@joinangora.com + alex@joinangora.com explicitly safe so they
--    can never be caught by an over-eager pattern.
DELETE FROM public.angora_user_profiles
WHERE LOWER(email) NOT IN ('ben@joinangora.com', 'alex@joinangora.com')
  AND (
       email      ILIKE 'test%@%'
    OR email      ILIKE '%test%@gmil.com'
    OR email      ILIKE '%@gmil.com'           -- common 'gmail' typo on test accounts
    OR email      ~* '^user[0-9]*@gmail\.com$'
    OR email      ILIKE 'team-bot-%@%'
    OR email      ILIKE 'youwillalertme@%'
    OR email      ILIKE 'abc%@%'
    OR full_name  ILIKE '%test%'
  );

-- 4. Sanity check — show what's left so you can confirm only your account
--    (ben@joinangora.com / alex@joinangora.com) and any real teammates
--    remain. Uncomment to run.
-- SELECT email, full_name, role, approval_status, created_at
--   FROM public.angora_user_profiles
--  ORDER BY created_at DESC;

COMMIT;
