-- ════════════════════════════════════════════════
-- DISABLE AUTH / ALLOW ANON ACCESS SQL
-- Run this in your Supabase SQL Editor to make everything public
-- ════════════════════════════════════════════════

-- angora_storage
drop policy if exists "angora_storage_select_own" on public.angora_storage;
create policy "angora_storage_select_own" on public.angora_storage for select using (true);

drop policy if exists "angora_storage_insert_own" on public.angora_storage;
create policy "angora_storage_insert_own" on public.angora_storage for insert with check (true);

drop policy if exists "angora_storage_update_own" on public.angora_storage;
create policy "angora_storage_update_own" on public.angora_storage for update using (true) with check (true);

drop policy if exists "angora_storage_delete_own" on public.angora_storage;
create policy "angora_storage_delete_own" on public.angora_storage for delete using (true);

-- angora_user_profiles
drop policy if exists "angora_user_profiles_select_own" on public.angora_user_profiles;
create policy "angora_user_profiles_select_own" on public.angora_user_profiles for select using (true);

drop policy if exists "angora_user_profiles_insert_own" on public.angora_user_profiles;
create policy "angora_user_profiles_insert_own" on public.angora_user_profiles for insert with check (true);

drop policy if exists "angora_user_profiles_update_own" on public.angora_user_profiles;
create policy "angora_user_profiles_update_own" on public.angora_user_profiles for update using (true) with check (true);

drop policy if exists "angora_user_profiles_delete_own" on public.angora_user_profiles;
create policy "angora_user_profiles_delete_own" on public.angora_user_profiles for delete using (true);

-- angora_product_library
drop policy if exists "angora_product_library_select_own" on public.angora_product_library;
create policy "angora_product_library_select_own" on public.angora_product_library for select using (true);

drop policy if exists "angora_product_library_insert_own" on public.angora_product_library;
create policy "angora_product_library_insert_own" on public.angora_product_library for insert with check (true);

drop policy if exists "angora_product_library_update_own" on public.angora_product_library;
create policy "angora_product_library_update_own" on public.angora_product_library for update using (true) with check (true);

drop policy if exists "angora_product_library_delete_own" on public.angora_product_library;
create policy "angora_product_library_delete_own" on public.angora_product_library for delete using (true);

-- angora_audit_schedule
drop policy if exists "angora_audit_schedule_select_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_select_own" on public.angora_audit_schedule for select using (true);

drop policy if exists "angora_audit_schedule_insert_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_insert_own" on public.angora_audit_schedule for insert with check (true);

drop policy if exists "angora_audit_schedule_update_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_update_own" on public.angora_audit_schedule for update using (true) with check (true);

drop policy if exists "angora_audit_schedule_delete_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_delete_own" on public.angora_audit_schedule for delete using (true);

-- angora_ops_audits
drop policy if exists "angora_ops_audits_select_own" on public.angora_ops_audits;
create policy "angora_ops_audits_select_own" on public.angora_ops_audits for select using (true);

drop policy if exists "angora_ops_audits_insert_own" on public.angora_ops_audits;
create policy "angora_ops_audits_insert_own" on public.angora_ops_audits for insert with check (true);

drop policy if exists "angora_ops_audits_update_own" on public.angora_ops_audits;
create policy "angora_ops_audits_update_own" on public.angora_ops_audits for update using (true) with check (true);

drop policy if exists "angora_ops_audits_delete_own" on public.angora_ops_audits;
create policy "angora_ops_audits_delete_own" on public.angora_ops_audits for delete using (true);

-- Grants
grant select, insert, update, delete on table public.angora_storage to anon, authenticated;
grant select, insert, update, delete on table public.angora_user_profiles to anon, authenticated;
grant select, insert, update, delete on table public.angora_product_library to anon, authenticated;
grant select, insert, update, delete on table public.angora_audit_schedule to anon, authenticated;
grant select, insert, update, delete on table public.angora_ops_audits to anon, authenticated;

-- Drop foreign key constraints so anon/fake user_ids don't cause insert errors
ALTER TABLE public.angora_storage DROP CONSTRAINT IF EXISTS angora_storage_user_id_fkey;
ALTER TABLE public.angora_ops_audits DROP CONSTRAINT IF EXISTS angora_ops_audits_user_id_fkey;
ALTER TABLE public.angora_audit_schedule DROP CONSTRAINT IF EXISTS angora_audit_schedule_user_id_fkey;
ALTER TABLE public.angora_product_library DROP CONSTRAINT IF EXISTS angora_product_library_user_id_fkey;
ALTER TABLE public.angora_user_profiles DROP CONSTRAINT IF EXISTS angora_user_profiles_user_id_fkey;
