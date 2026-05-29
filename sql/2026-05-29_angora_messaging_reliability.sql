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
