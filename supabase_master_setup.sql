-- ============================================================
-- ANGORA GARDEN — MASTER SETUP SQL
-- Run this in your Supabase SQL Editor (project: temzkjhkqnrtdwxckioy)
-- Safe to re-run at any time — everything uses IF NOT EXISTS / ON CONFLICT
-- ============================================================


-- ════════════════════════════════════════════════
-- SECTION 1: BASE TABLES (skip if already exist)
-- ════════════════════════════════════════════════

create table if not exists public.angora_storage (
  user_id uuid not null references auth.users(id) on delete cascade,
  key text not null,
  value text not null default '',
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  constraint angora_storage_pkey primary key (user_id, key)
);

create table if not exists public.angora_user_profiles (
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null default '',
  first_name text not null default '',
  last_name text not null default '',
  full_name text not null default '',
  role text not null default 'admin',
  approval_status text not null default 'pending',
  rejection_reason text not null default '',
  reviewed_at timestamptz,
  reviewed_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  constraint angora_user_profiles_pkey primary key (user_id)
);

alter table public.angora_user_profiles
  add column if not exists role text not null default 'admin';
alter table public.angora_user_profiles
  add column if not exists approval_status text not null default 'pending';
alter table public.angora_user_profiles
  add column if not exists rejection_reason text not null default '';
alter table public.angora_user_profiles
  add column if not exists reviewed_at timestamptz;
alter table public.angora_user_profiles
  add column if not exists reviewed_by_user_id uuid references auth.users(id) on delete set null;

create table if not exists public.angora_product_library (
  user_id uuid not null references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  constraint angora_product_library_pkey primary key (user_id)
);

create table if not exists public.angora_audit_schedule (
  user_id uuid not null references auth.users(id) on delete cascade,
  schedule_data jsonb not null default '{}'::jsonb,
  completions_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  constraint angora_audit_schedule_pkey primary key (user_id)
);

create table if not exists public.angora_ops_audits (
  user_id uuid not null references auth.users(id) on delete cascade,
  audit_id text not null,
  week_key text not null,
  day_key text,
  date_key text,
  brand text,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  constraint angora_ops_audits_pkey primary key (user_id, audit_id, week_key)
);


-- ════════════════════════════════════════════════
-- SECTION 2: HELPER FUNCTIONS
-- ════════════════════════════════════════════════

create or replace function public.angora_user_role()
returns text language sql stable security definer
set search_path = public, auth as $$
  select lower(coalesce(
    (select profile.role from public.angora_user_profiles as profile where profile.user_id = auth.uid()),
    auth.jwt()->'user_metadata'->>'role',
    auth.jwt()->'app_metadata'->>'role',
    'admin'
  ));
$$;

create or replace function public.angora_user_status()
returns text language sql stable security definer
set search_path = public, auth as $$
  select lower(coalesce(
    (select profile.approval_status from public.angora_user_profiles as profile where profile.user_id = auth.uid()),
    auth.jwt()->'user_metadata'->>'approval_status',
    'active'
  ));
$$;

create or replace function public.angora_is_active_user()
returns boolean language sql stable security definer
set search_path = public, auth as $$
  select auth.role() = 'authenticated';
$$;

create or replace function public.angora_is_admin()
returns boolean language sql stable security definer
set search_path = public, auth as $$
  select auth.role() = 'authenticated';
$$;

create or replace function public.angora_is_super_admin()
returns boolean language sql stable security definer
set search_path = public, auth as $$
  select auth.role() = 'authenticated'
    and (
      lower(coalesce(auth.jwt()->>'email', '')) = lower('proabdulbasit.me@gmail.com')
      or lower(coalesce(auth.jwt()->>'email', '')) = lower('alex@joinangora.com')
      or public.angora_user_role() = 'super_admin'
    );
$$;


-- ════════════════════════════════════════════════
-- SECTION 3: RLS — ENABLE + POLICIES
-- (Any authenticated user can read/write all shared data)
-- ════════════════════════════════════════════════

alter table public.angora_storage enable row level security;
alter table public.angora_user_profiles enable row level security;
alter table public.angora_product_library enable row level security;
alter table public.angora_audit_schedule enable row level security;
alter table public.angora_ops_audits enable row level security;

-- angora_storage
drop policy if exists "angora_storage_select_own" on public.angora_storage;
create policy "angora_storage_select_own" on public.angora_storage for select
  using (auth.role() = 'authenticated');
drop policy if exists "angora_storage_insert_own" on public.angora_storage;
create policy "angora_storage_insert_own" on public.angora_storage for insert
  with check (auth.uid() = user_id);
drop policy if exists "angora_storage_update_own" on public.angora_storage;
create policy "angora_storage_update_own" on public.angora_storage for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "angora_storage_delete_own" on public.angora_storage;
create policy "angora_storage_delete_own" on public.angora_storage for delete
  using (auth.role() = 'authenticated');

-- angora_user_profiles
drop policy if exists "angora_user_profiles_select_own" on public.angora_user_profiles;
create policy "angora_user_profiles_select_own" on public.angora_user_profiles for select
  using (auth.role() = 'authenticated');
drop policy if exists "angora_user_profiles_insert_own" on public.angora_user_profiles;
create policy "angora_user_profiles_insert_own" on public.angora_user_profiles for insert
  with check (auth.uid() = user_id);
drop policy if exists "angora_user_profiles_update_own" on public.angora_user_profiles;
create policy "angora_user_profiles_update_own" on public.angora_user_profiles for update
  using (auth.uid() = user_id or public.angora_is_super_admin())
  with check (auth.uid() = user_id or public.angora_is_super_admin());
drop policy if exists "angora_user_profiles_delete_own" on public.angora_user_profiles;
create policy "angora_user_profiles_delete_own" on public.angora_user_profiles for delete
  using (auth.uid() = user_id or public.angora_is_super_admin());

-- angora_product_library
drop policy if exists "angora_product_library_select_own" on public.angora_product_library;
create policy "angora_product_library_select_own" on public.angora_product_library for select
  using (auth.role() = 'authenticated');
drop policy if exists "angora_product_library_insert_own" on public.angora_product_library;
create policy "angora_product_library_insert_own" on public.angora_product_library for insert
  with check (auth.uid() = user_id);
drop policy if exists "angora_product_library_update_own" on public.angora_product_library;
create policy "angora_product_library_update_own" on public.angora_product_library for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "angora_product_library_delete_own" on public.angora_product_library;
create policy "angora_product_library_delete_own" on public.angora_product_library for delete
  using (auth.role() = 'authenticated');

-- angora_audit_schedule
drop policy if exists "angora_audit_schedule_select_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_select_own" on public.angora_audit_schedule for select
  using (auth.role() = 'authenticated');
drop policy if exists "angora_audit_schedule_insert_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_insert_own" on public.angora_audit_schedule for insert
  with check (auth.uid() = user_id);
drop policy if exists "angora_audit_schedule_update_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_update_own" on public.angora_audit_schedule for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "angora_audit_schedule_delete_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_delete_own" on public.angora_audit_schedule for delete
  using (auth.role() = 'authenticated');

-- angora_ops_audits
drop policy if exists "angora_ops_audits_select_own" on public.angora_ops_audits;
create policy "angora_ops_audits_select_own" on public.angora_ops_audits for select
  using (auth.role() = 'authenticated');
drop policy if exists "angora_ops_audits_insert_own" on public.angora_ops_audits;
create policy "angora_ops_audits_insert_own" on public.angora_ops_audits for insert
  with check (auth.uid() = user_id);
drop policy if exists "angora_ops_audits_update_own" on public.angora_ops_audits;
create policy "angora_ops_audits_update_own" on public.angora_ops_audits for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "angora_ops_audits_delete_own" on public.angora_ops_audits;
create policy "angora_ops_audits_delete_own" on public.angora_ops_audits for delete
  using (auth.role() = 'authenticated');

-- grants
grant select, insert, update, delete on table public.angora_storage to authenticated;
grant select, insert, update, delete on table public.angora_user_profiles to authenticated;
grant select, insert, update, delete on table public.angora_product_library to authenticated;
grant select, insert, update, delete on table public.angora_audit_schedule to authenticated;
grant select, insert, update, delete on table public.angora_ops_audits to authenticated;


-- ════════════════════════════════════════════════
-- SECTION 4: ACTIVATE ALL USERS
-- (Create profiles for anyone missing one, set all to active)
-- ════════════════════════════════════════════════

insert into public.angora_user_profiles (
  user_id, email, first_name, last_name, full_name,
  role, approval_status, rejection_reason, reviewed_at
)
select
  u.id,
  coalesce(u.email, ''),
  trim(coalesce(u.raw_user_meta_data->>'first_name', '')),
  trim(coalesce(u.raw_user_meta_data->>'last_name', '')),
  trim(concat_ws(' ',
    trim(coalesce(u.raw_user_meta_data->>'first_name', '')),
    trim(coalesce(u.raw_user_meta_data->>'last_name', ''))
  )),
  'admin', 'active', '', now()
from auth.users u
on conflict (user_id) do update set
  approval_status = 'active',
  reviewed_at     = now(),
  updated_at      = now();

-- Confirm all email addresses so users can sign in immediately
update auth.users
set email_confirmed_at = coalesce(email_confirmed_at, now())
where email_confirmed_at is null;

-- Sync active status into JWT metadata
update auth.users
set raw_user_meta_data =
  coalesce(raw_user_meta_data, '{}'::jsonb) ||
  jsonb_build_object('approval_status', 'active', 'role', 'admin')
where id in (select user_id from public.angora_user_profiles);


-- ════════════════════════════════════════════════
-- SECTION 5: VERIFY — see all users and their status
-- ════════════════════════════════════════════════
select
  u.email,
  u.email_confirmed_at is not null as email_confirmed,
  p.role,
  p.approval_status
from auth.users u
left join public.angora_user_profiles p on p.user_id = u.id
order by u.created_at;
