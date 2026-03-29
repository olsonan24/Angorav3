-- Run this once in Supabase SQL Editor
-- Creates per-user key/value storage used by Angora Tools frontend.

create table if not exists public.angora_storage (
  user_id uuid not null references auth.users(id) on delete cascade,
  key text not null,
  value text not null default '',
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  constraint angora_storage_pkey primary key (user_id, key)
);

create index if not exists angora_storage_updated_at_idx
  on public.angora_storage (updated_at desc);

create or replace function public.set_angora_storage_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

create or replace function public.angora_is_super_admin()
returns boolean
language sql
stable
as $$
  select auth.role() = 'authenticated'
    and (
      lower(coalesce(auth.jwt() ->> 'email', '')) = lower('proabdulbasit.me@gmail.com')
      or lower(
        coalesce(
          auth.jwt() -> 'user_metadata' ->> 'role',
          auth.jwt() -> 'app_metadata' ->> 'role',
          'admin'
        )
      ) = 'super_admin'
    );
$$;

create or replace function public.angora_is_admin()
returns boolean
language sql
stable
as $$
  select auth.role() = 'authenticated'
    and lower(
      coalesce(
        auth.jwt() -> 'user_metadata' ->> 'role',
        auth.jwt() -> 'app_metadata' ->> 'role',
        'admin'
      )
    ) in ('admin', 'super_admin');
$$;

drop trigger if exists trg_angora_storage_updated_at on public.angora_storage;
create trigger trg_angora_storage_updated_at
before update on public.angora_storage
for each row
execute function public.set_angora_storage_updated_at();

alter table public.angora_storage enable row level security;

drop policy if exists "angora_storage_select_own" on public.angora_storage;
create policy "angora_storage_select_own"
on public.angora_storage
for select
using (auth.uid() = user_id or public.angora_is_admin());

drop policy if exists "angora_storage_insert_own" on public.angora_storage;
create policy "angora_storage_insert_own"
on public.angora_storage
for insert
with check (auth.uid() = user_id or public.angora_is_admin());

drop policy if exists "angora_storage_update_own" on public.angora_storage;
create policy "angora_storage_update_own"
on public.angora_storage
for update
using (auth.uid() = user_id or public.angora_is_admin())
with check (auth.uid() = user_id or public.angora_is_admin());

drop policy if exists "angora_storage_delete_own" on public.angora_storage;
create policy "angora_storage_delete_own"
on public.angora_storage
for delete
using (auth.uid() = user_id or public.angora_is_admin());

-- User profile storage for auth registration fields.
-- One row per Supabase auth user, populated from auth.users metadata.
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

create or replace function public.angora_user_role()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select lower(
    coalesce(
      (
        select profile.role
        from public.angora_user_profiles as profile
        where profile.user_id = auth.uid()
      ),
      auth.jwt() -> 'user_metadata' ->> 'role',
      auth.jwt() -> 'app_metadata' ->> 'role',
      'admin'
    )
  );
$$;

create or replace function public.angora_user_status()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select lower(
    coalesce(
      (
        select profile.approval_status
        from public.angora_user_profiles as profile
        where profile.user_id = auth.uid()
      ),
      auth.jwt() -> 'user_metadata' ->> 'approval_status',
      'pending'
    )
  );
$$;

create or replace function public.angora_is_active_user()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select auth.role() = 'authenticated'
    and public.angora_user_status() = 'active';
$$;

create or replace function public.angora_is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select (
      public.angora_is_active_user()
      and public.angora_user_role() = 'super_admin'
    )
    or lower(coalesce(auth.jwt() ->> 'email', '')) = lower('proabdulbasit.me@gmail.com');
$$;

create or replace function public.angora_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select public.angora_is_active_user()
    and public.angora_user_role() in ('admin', 'super_admin');
$$;

create index if not exists angora_user_profiles_email_idx
  on public.angora_user_profiles (lower(email));

create or replace function public.set_angora_user_profiles_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

create or replace function public.sync_angora_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  profile_first_name text := trim(coalesce(new.raw_user_meta_data ->> 'first_name', ''));
  profile_last_name text := trim(coalesce(new.raw_user_meta_data ->> 'last_name', ''));
  profile_role text := lower(coalesce(new.raw_user_meta_data ->> 'role', 'admin'));
  profile_status text := lower(coalesce(new.raw_user_meta_data ->> 'approval_status', 'pending'));
begin
  insert into public.angora_user_profiles (
    user_id,
    email,
    first_name,
    last_name,
    full_name,
    role,
    approval_status,
    rejection_reason
  )
  values (
    new.id,
    coalesce(new.email, ''),
    profile_first_name,
    profile_last_name,
    trim(concat_ws(' ', profile_first_name, profile_last_name)),
    case when profile_role in ('admin', 'super_admin') then profile_role else 'admin' end,
    case when profile_status in ('active', 'pending', 'rejected') then profile_status else 'pending' end,
    trim(coalesce(new.raw_user_meta_data ->> 'rejection_reason', ''))
  )
  on conflict (user_id) do update
  set
    email = excluded.email,
    first_name = excluded.first_name,
    last_name = excluded.last_name,
    full_name = excluded.full_name,
    updated_at = timezone('utc'::text, now());

  return new;
end;
$$;

drop trigger if exists trg_angora_user_profiles_updated_at on public.angora_user_profiles;
create trigger trg_angora_user_profiles_updated_at
before update on public.angora_user_profiles
for each row
execute function public.set_angora_user_profiles_updated_at();

drop trigger if exists trg_angora_user_profiles_sync on auth.users;
create trigger trg_angora_user_profiles_sync
after insert or update of email, raw_user_meta_data on auth.users
for each row
execute function public.sync_angora_user_profile();

insert into public.angora_user_profiles (
  user_id,
  email,
  first_name,
  last_name,
  full_name,
  role,
  approval_status,
  rejection_reason
)
select
  users.id,
  coalesce(users.email, ''),
  trim(coalesce(users.raw_user_meta_data ->> 'first_name', '')),
  trim(coalesce(users.raw_user_meta_data ->> 'last_name', '')),
  trim(
    concat_ws(
      ' ',
      trim(coalesce(users.raw_user_meta_data ->> 'first_name', '')),
      trim(coalesce(users.raw_user_meta_data ->> 'last_name', ''))
    )
  ),
  case
    when lower(coalesce(users.raw_user_meta_data ->> 'role', 'admin')) = 'super_admin' then 'super_admin'
    else 'admin'
  end,
  case
    when lower(coalesce(users.email, '')) = lower('proabdulbasit.me@gmail.com') then 'active'
    when lower(coalesce(users.raw_user_meta_data ->> 'approval_status', 'pending')) in ('active', 'pending', 'rejected')
      then lower(coalesce(users.raw_user_meta_data ->> 'approval_status', 'pending'))
    else 'pending'
  end,
  trim(coalesce(users.raw_user_meta_data ->> 'rejection_reason', ''))
from auth.users as users
on conflict (user_id) do update
set
  email = excluded.email,
  first_name = excluded.first_name,
  last_name = excluded.last_name,
  full_name = excluded.full_name,
  updated_at = timezone('utc'::text, now());

alter table public.angora_user_profiles enable row level security;

drop policy if exists "angora_user_profiles_select_own" on public.angora_user_profiles;
create policy "angora_user_profiles_select_own"
on public.angora_user_profiles
for select
using (auth.uid() = user_id or public.angora_is_super_admin());

drop policy if exists "angora_user_profiles_insert_own" on public.angora_user_profiles;
create policy "angora_user_profiles_insert_own"
on public.angora_user_profiles
for insert
with check (auth.uid() = user_id or public.angora_is_super_admin());

drop policy if exists "angora_user_profiles_update_own" on public.angora_user_profiles;
create policy "angora_user_profiles_update_own"
on public.angora_user_profiles
for update
using (auth.uid() = user_id or public.angora_is_super_admin())
with check (auth.uid() = user_id or public.angora_is_super_admin());

drop policy if exists "angora_user_profiles_delete_own" on public.angora_user_profiles;
create policy "angora_user_profiles_delete_own"
on public.angora_user_profiles
for delete
using (auth.uid() = user_id or public.angora_is_super_admin());

grant select, insert, update, delete on table public.angora_user_profiles to authenticated;

create or replace function public.angora_list_admin_accounts()
returns table (
  user_id uuid,
  email text,
  first_name text,
  last_name text,
  full_name text,
  role text,
  approval_status text,
  rejection_reason text,
  reviewed_at timestamptz,
  reviewed_by_user_id uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.angora_is_super_admin() then
    raise exception 'Only super admins can view admin accounts.';
  end if;

  return query
  select
    profile.user_id,
    profile.email,
    profile.first_name,
    profile.last_name,
    profile.full_name,
    profile.role,
    profile.approval_status,
    profile.rejection_reason,
    profile.reviewed_at,
    profile.reviewed_by_user_id,
    profile.created_at,
    profile.updated_at
  from public.angora_user_profiles as profile
  order by profile.created_at desc;
end;
$$;

grant execute on function public.angora_list_admin_accounts() to authenticated;

create or replace function public.angora_set_admin_approval(
  target_user_id uuid,
  next_status text,
  next_reason text default null
)
returns public.angora_user_profiles
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  normalized_status text := lower(trim(coalesce(next_status, 'pending')));
  normalized_reason text := trim(coalesce(next_reason, ''));
  updated_row public.angora_user_profiles;
begin
  if not public.angora_is_super_admin() then
    raise exception 'Only super admins can update admin approvals.';
  end if;

  if target_user_id is null then
    raise exception 'Target user id is required.';
  end if;

  if normalized_status not in ('pending', 'active', 'rejected') then
    raise exception 'Invalid approval status.';
  end if;

  if normalized_status <> 'rejected' then
    normalized_reason := '';
  end if;

  update public.angora_user_profiles as profile
  set
    approval_status = normalized_status,
    rejection_reason = normalized_reason,
    reviewed_at = timezone('utc'::text, now()),
    reviewed_by_user_id = auth.uid(),
    updated_at = timezone('utc'::text, now())
  where profile.user_id = target_user_id
    and profile.role <> 'super_admin'
  returning profile.* into updated_row;

  if updated_row.user_id is null then
    raise exception 'Target admin account was not found or is locked.';
  end if;

  update auth.users as auth_user
  set raw_user_meta_data = coalesce(auth_user.raw_user_meta_data, '{}'::jsonb)
    || jsonb_build_object(
      'approval_status', normalized_status,
      'rejection_reason', normalized_reason
    )
  where auth_user.id = target_user_id;

  return updated_row;
end;
$$;

grant execute on function public.angora_set_admin_approval(uuid, text, text) to authenticated;

-- Bootstrap the initial super admin.
-- Run this after the user account exists in auth.users.
update auth.users
set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
  || jsonb_build_object(
    'role', 'super_admin',
    'approval_status', 'active'
  )
where lower(email) = lower('proabdulbasit.me@gmail.com');

insert into public.angora_user_profiles (
  user_id,
  email,
  first_name,
  last_name,
  full_name,
  role,
  approval_status,
  rejection_reason,
  reviewed_at
)
select
  users.id,
  coalesce(users.email, ''),
  trim(coalesce(users.raw_user_meta_data ->> 'first_name', '')),
  trim(coalesce(users.raw_user_meta_data ->> 'last_name', '')),
  trim(
    concat_ws(
      ' ',
      trim(coalesce(users.raw_user_meta_data ->> 'first_name', '')),
      trim(coalesce(users.raw_user_meta_data ->> 'last_name', ''))
    )
  ),
  'super_admin',
  'active',
  '',
  timezone('utc'::text, now())
from auth.users as users
where lower(users.email) = lower('proabdulbasit.me@gmail.com')
on conflict (user_id) do update
set
  email = excluded.email,
  first_name = excluded.first_name,
  last_name = excluded.last_name,
  full_name = excluded.full_name,
  role = 'super_admin',
  approval_status = 'active',
  rejection_reason = '',
  reviewed_at = timezone('utc'::text, now()),
  updated_at = timezone('utc'::text, now());

-- Product library storage for Account Library bulk upload/import.
-- One row per authenticated user, containing full brand->product JSON.
create table if not exists public.angora_product_library (
  user_id uuid not null references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  constraint angora_product_library_pkey primary key (user_id)
);

create index if not exists angora_product_library_updated_at_idx
  on public.angora_product_library (updated_at desc);

create or replace function public.set_angora_product_library_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

drop trigger if exists trg_angora_product_library_updated_at on public.angora_product_library;
create trigger trg_angora_product_library_updated_at
before update on public.angora_product_library
for each row
execute function public.set_angora_product_library_updated_at();

alter table public.angora_product_library enable row level security;

drop policy if exists "angora_product_library_select_own" on public.angora_product_library;
create policy "angora_product_library_select_own"
on public.angora_product_library
for select
using (auth.uid() = user_id or public.angora_is_admin());

drop policy if exists "angora_product_library_insert_own" on public.angora_product_library;
create policy "angora_product_library_insert_own"
on public.angora_product_library
for insert
with check (auth.uid() = user_id or public.angora_is_admin());

drop policy if exists "angora_product_library_update_own" on public.angora_product_library;
create policy "angora_product_library_update_own"
on public.angora_product_library
for update
using (auth.uid() = user_id or public.angora_is_admin())
with check (auth.uid() = user_id or public.angora_is_admin());

drop policy if exists "angora_product_library_delete_own" on public.angora_product_library;
create policy "angora_product_library_delete_own"
on public.angora_product_library
for delete
using (auth.uid() = user_id or public.angora_is_admin());

grant select, insert, update, delete on table public.angora_product_library to authenticated;

-- Audit schedule storage for weekly scheduler page and modal.
-- One row per authenticated user with recurring schedule + completion map.
create table if not exists public.angora_audit_schedule (
  user_id uuid not null references auth.users(id) on delete cascade,
  schedule_data jsonb not null default '{}'::jsonb,
  completions_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  constraint angora_audit_schedule_pkey primary key (user_id)
);

create index if not exists angora_audit_schedule_updated_at_idx
  on public.angora_audit_schedule (updated_at desc);

create or replace function public.set_angora_audit_schedule_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

drop trigger if exists trg_angora_audit_schedule_updated_at on public.angora_audit_schedule;
create trigger trg_angora_audit_schedule_updated_at
before update on public.angora_audit_schedule
for each row
execute function public.set_angora_audit_schedule_updated_at();

alter table public.angora_audit_schedule enable row level security;

drop policy if exists "angora_audit_schedule_select_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_select_own"
on public.angora_audit_schedule
for select
using (auth.uid() = user_id or public.angora_is_admin());

drop policy if exists "angora_audit_schedule_insert_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_insert_own"
on public.angora_audit_schedule
for insert
with check (auth.uid() = user_id or public.angora_is_admin());

drop policy if exists "angora_audit_schedule_update_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_update_own"
on public.angora_audit_schedule
for update
using (auth.uid() = user_id or public.angora_is_admin())
with check (auth.uid() = user_id or public.angora_is_admin());

drop policy if exists "angora_audit_schedule_delete_own" on public.angora_audit_schedule;
create policy "angora_audit_schedule_delete_own"
on public.angora_audit_schedule
for delete
using (auth.uid() = user_id or public.angora_is_admin());

grant select, insert, update, delete on table public.angora_audit_schedule to authenticated;

do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'angora_audit_schedule'
  ) then
    execute 'alter publication supabase_realtime add table public.angora_audit_schedule';
  end if;
end;
$$;

-- OPS guided audit workflow state (Search Terms, SCP, SQP, Weekly Report).
-- One row per authenticated user + audit card + week.
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

create index if not exists angora_ops_audits_updated_at_idx
  on public.angora_ops_audits (updated_at desc);

create index if not exists angora_ops_audits_brand_idx
  on public.angora_ops_audits (brand);

create or replace function public.set_angora_ops_audits_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

drop trigger if exists trg_angora_ops_audits_updated_at on public.angora_ops_audits;
create trigger trg_angora_ops_audits_updated_at
before update on public.angora_ops_audits
for each row
execute function public.set_angora_ops_audits_updated_at();

alter table public.angora_ops_audits enable row level security;

drop policy if exists "angora_ops_audits_select_own" on public.angora_ops_audits;
create policy "angora_ops_audits_select_own"
on public.angora_ops_audits
for select
using (auth.uid() = user_id or public.angora_is_admin());

drop policy if exists "angora_ops_audits_insert_own" on public.angora_ops_audits;
create policy "angora_ops_audits_insert_own"
on public.angora_ops_audits
for insert
with check (auth.uid() = user_id or public.angora_is_admin());

drop policy if exists "angora_ops_audits_update_own" on public.angora_ops_audits;
create policy "angora_ops_audits_update_own"
on public.angora_ops_audits
for update
using (auth.uid() = user_id or public.angora_is_admin())
with check (auth.uid() = user_id or public.angora_is_admin());

drop policy if exists "angora_ops_audits_delete_own" on public.angora_ops_audits;
create policy "angora_ops_audits_delete_own"
on public.angora_ops_audits
for delete
using (auth.uid() = user_id or public.angora_is_admin());

grant select, insert, update, delete on table public.angora_ops_audits to authenticated;
