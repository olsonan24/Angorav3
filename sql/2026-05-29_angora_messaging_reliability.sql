-- Angora messaging reliability/performance fixes.
-- Run once in the Supabase SQL editor for project temzkjhkqnrtdwxckioy.

-- Thread history and latest-message reads must be able to seek by thread_id
-- and walk created_at order instead of scanning/sorting angora_messages.
create index if not exists angora_messages_thread_created_idx
  on public.angora_messages (thread_id, created_at);

-- Department/inbox badge checks commonly filter sender_type inside a thread.
create index if not exists angora_messages_thread_sender_created_idx
  on public.angora_messages (thread_id, sender_type, created_at desc);

-- Inbox lists are scoped by account and ordered by recent activity.
create index if not exists angora_message_threads_account_updated_idx
  on public.angora_message_threads (account_id, updated_at desc);

-- Store latest-message metadata on the thread so inboxes can render quickly
-- and do not depend on a frontend follow-up update after every send.
alter table public.angora_message_threads
  add column if not exists last_message text,
  add column if not exists last_sender_type text,
  add column if not exists last_message_at timestamptz;

create or replace function public.angora_touch_message_thread()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.angora_message_threads
  set
    updated_at = coalesce(new.created_at, now()),
    last_message = new.content,
    last_sender_type = new.sender_type,
    last_message_at = coalesce(new.created_at, now())
  where id = new.thread_id;

  return new;
end;
$$;

drop trigger if exists angora_messages_touch_thread on public.angora_messages;
create trigger angora_messages_touch_thread
after insert on public.angora_messages
for each row
execute function public.angora_touch_message_thread();

with latest as (
  select distinct on (thread_id)
    thread_id,
    content,
    sender_type,
    created_at
  from public.angora_messages
  order by thread_id, created_at desc
)
update public.angora_message_threads t
set
  updated_at = greatest(coalesce(t.updated_at, latest.created_at), latest.created_at),
  last_message = latest.content,
  last_sender_type = latest.sender_type,
  last_message_at = latest.created_at
from latest
where t.id = latest.thread_id;

-- RLS helper used by thread/message policies. It mirrors the app access model:
-- Angora admins, account PSM/contact emails, optional OSM email, and explicit
-- partner access rows can use messaging for the account.
create or replace function public.angora_can_access_account(p_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(
    -- Angora internal admins / global message users
    lower(coalesce(auth.jwt() ->> 'email', '')) in (
      'alex@joinangora.com',
      'ben@joinangora.com',
      'kenny@joinangora.com',
      'edgar@joinangora.com',
      'corby@joinangora.com',
      'jared@joinangora.com',
      'collin@joinangora.com',
      'logan@joinangora.com',
      'kate@joinangora.com',
      'jj@joinangora.com',
      'aimec@joinangora.com'
    )

    -- Account contact / owner fields. psm_email or osm_email may contain
    -- comma-separated emails, so split + trim before comparing.
    or exists (
      select 1
      from public.angora_accounts a
      where a.id = p_account_id
        and (
          lower(coalesce(a.contact_email, '')) = lower(coalesce(auth.jwt() ->> 'email', ''))
          or lower(coalesce(auth.jwt() ->> 'email', '')) = any (
            select lower(trim(x))
            from unnest(string_to_array(coalesce(a.psm_email, ''), ',')) as x
          )
          or lower(coalesce(auth.jwt() ->> 'email', '')) = any (
            select lower(trim(x))
            from unnest(string_to_array(coalesce(to_jsonb(a) ->> 'osm_email', ''), ',')) as x
          )
        )
    )

    -- Explicit partner grants. IMPORTANT: angora_partner_access stores user_id,
    -- not email. The old helper checked pa.email, which always failed.
    or exists (
      select 1
      from public.angora_partner_access pa
      where pa.account_id = p_account_id
        and pa.user_id = auth.uid()
    ),
    false
  );
$fn$;

revoke all on function public.angora_can_access_account(uuid) from public;
grant execute on function public.angora_can_access_account(uuid) to authenticated;

alter table public.angora_message_threads enable row level security;
alter table public.angora_messages enable row level security;

drop policy if exists angora_message_threads_select_access on public.angora_message_threads;
create policy angora_message_threads_select_access
  on public.angora_message_threads
  for select
  to authenticated
  using (public.angora_can_access_account(account_id));

drop policy if exists angora_message_threads_insert_access on public.angora_message_threads;
create policy angora_message_threads_insert_access
  on public.angora_message_threads
  for insert
  to authenticated
  with check (
    public.angora_can_access_account(account_id)
    and (created_by is null or created_by = auth.uid())
  );

drop policy if exists angora_message_threads_update_access on public.angora_message_threads;
create policy angora_message_threads_update_access
  on public.angora_message_threads
  for update
  to authenticated
  using (public.angora_can_access_account(account_id))
  with check (public.angora_can_access_account(account_id));

drop policy if exists angora_messages_select_access on public.angora_messages;
create policy angora_messages_select_access
  on public.angora_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.angora_message_threads t
      where t.id = thread_id
        and public.angora_can_access_account(t.account_id)
    )
  );

drop policy if exists angora_messages_insert_access on public.angora_messages;
create policy angora_messages_insert_access
  on public.angora_messages
  for insert
  to authenticated
  with check (
    (sender_id is null or sender_id = auth.uid())
    and exists (
      select 1
      from public.angora_message_threads t
      where t.id = thread_id
        and public.angora_can_access_account(t.account_id)
    )
  );

-- Collapse exact duplicate threads so one account/department does not split
-- messages across two visually identical conversations.
do $$
begin
  with ranked_threads as (
    select
      id,
      first_value(id) over (
        partition by account_id, subject
        order by updated_at desc nulls last, id desc
      ) as keep_id
    from public.angora_message_threads
  )
  update public.angora_messages m
  set thread_id = r.keep_id
  from ranked_threads r
  where m.thread_id = r.id
    and r.id <> r.keep_id;

  with ranked_threads as (
    select
      id,
      first_value(id) over (
        partition by account_id, subject
        order by updated_at desc nulls last, id desc
      ) as keep_id
    from public.angora_message_threads
  )
  delete from public.angora_message_threads t
  using ranked_threads r
  where t.id = r.id
    and r.id <> r.keep_id;
end $$;

create unique index if not exists angora_message_threads_account_subject_uidx
  on public.angora_message_threads (account_id, subject);

-- Realtime needs the table in the supabase_realtime publication.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'angora_messages'
  ) then
    alter publication supabase_realtime add table public.angora_messages;
  end if;
end $$;

-- Keep this select handy after applying:
-- select schemaname, tablename, indexname, indexdef
-- from pg_indexes
-- where schemaname = 'public'
--   and tablename in ('angora_messages', 'angora_message_threads')
-- order by tablename, indexname;
