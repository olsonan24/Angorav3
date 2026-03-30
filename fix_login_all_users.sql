-- ============================================================
-- EMERGENCY FIX: Allow all existing users to log in
-- Run in Supabase SQL Editor on project: temzkjhkqnrtdwxckioy
-- ============================================================

-- Step 1: Create profiles for ANY auth user who doesn't have one yet
INSERT INTO public.angora_user_profiles (
  user_id, email, first_name, last_name, full_name,
  role, approval_status, rejection_reason, reviewed_at
)
SELECT
  u.id,
  coalesce(u.email, ''),
  trim(coalesce(u.raw_user_meta_data->>'first_name', '')),
  trim(coalesce(u.raw_user_meta_data->>'last_name', '')),
  trim(concat_ws(' ',
    trim(coalesce(u.raw_user_meta_data->>'first_name', '')),
    trim(coalesce(u.raw_user_meta_data->>'last_name', ''))
  )),
  'admin',
  'active',
  '',
  now()
FROM auth.users u
ON CONFLICT (user_id) DO UPDATE SET
  approval_status = 'active',
  role = coalesce(
    CASE WHEN excluded.role IN ('admin','super_admin') THEN excluded.role END,
    'admin'
  ),
  reviewed_at = now(),
  updated_at = now();

-- Step 2: Make absolutely sure EVERYONE is active
UPDATE public.angora_user_profiles
SET approval_status = 'active', reviewed_at = now(), updated_at = now()
WHERE approval_status != 'active';

-- Step 3: Sync active status back into auth user metadata
-- (so the JWT also reflects active status)
UPDATE auth.users
SET raw_user_meta_data =
  coalesce(raw_user_meta_data, '{}'::jsonb) ||
  jsonb_build_object('approval_status', 'active', 'role', 'admin')
WHERE id IN (
  SELECT user_id FROM public.angora_user_profiles WHERE approval_status = 'active'
);

-- Verify: see all users and their status
SELECT email, role, approval_status FROM public.angora_user_profiles ORDER BY created_at;
