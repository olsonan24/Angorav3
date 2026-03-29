-- ============================================================
-- FIX: Allow any active/approved user to read all shared data
-- Run this in your Supabase SQL Editor (the auth project:
--   temzkjhkqnrtdwxckioy)
-- ============================================================

-- 1. angora_product_library  ─ any active user can SELECT all rows
drop policy if exists "angora_product_library_select_own" on public.angora_product_library;
create policy "angora_product_library_select_own"
on public.angora_product_library
for select
using (
  auth.uid() = user_id
  or public.angora_is_active_user()   -- any approved user can see all brands
);

-- 2. angora_storage  ─ any active user can SELECT all rows
drop policy if exists "angora_storage_select_own" on public.angora_storage;
create policy "angora_storage_select_own"
on public.angora_storage
for select
using (
  auth.uid() = user_id
  or public.angora_is_active_user()   -- any approved user can see all storage keys
);

-- 3. angora_audit_schedule  ─ any active user can SELECT all rows
drop policy if exists "angora_audit_schedule_select_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_select_own"
on public.angora_audit_schedule
for select
using (
  auth.uid() = user_id
  or public.angora_is_active_user()
);

-- 4. angora_ops_audits  ─ any active user can SELECT all rows
drop policy if exists "angora_ops_audits_select_own" on public.angora_ops_audits;
create policy "angora_ops_audits_select_own"
on public.angora_ops_audits
for select
using (
  auth.uid() = user_id
  or public.angora_is_active_user()
);
