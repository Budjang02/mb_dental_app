-- SUPERSEDED - DO NOT RUN. Use docs/realtime_data_sync_migration.sql instead.
-- This file was never applied to production. Its realtime section errors on a
-- table already in the publication, and it replaces RLS policies on
-- `patients`, `profiles` and `notifications` that the admin web portal relies
-- on. Kept for history only.
--
-- Cross-platform sync between the admin web platform, the patient web build
-- and the patient mobile app.
--
-- Run this in the Supabase SQL editor (service role). It is idempotent, so a
-- re-run is safe. Section 5 is verification only - read it before assuming the
-- app code is at fault.
--
-- Two problems are addressed:
--   1. A chart created on the admin platform never reaches the app, because
--      `patients.profile_id` is null and the app reads charts by that column.
--   2. An alert marked read on one platform stays unread on the other, because
--      the read state was not durable and nothing pushed the change across.


-- 1. Notification read state ------------------------------------------------

-- `is_read` already exists. `read_at` makes the read auditable and lets two
-- devices reporting a read at once be ordered.
alter table public.notifications
  add column if not exists read_at timestamptz;

-- Anything already read predates the column; stamp it so "read but no
-- timestamp" does not have to be a third state the clients handle.
update public.notifications
   set read_at = coalesce(read_at, created_at)
 where is_read and read_at is null;

-- The app lists a patient's alerts newest first and badges the unread ones.
create index if not exists notifications_recipient_created_idx
    on public.notifications (recipient_id, created_at desc);

create index if not exists notifications_recipient_unread_idx
    on public.notifications (recipient_id)
 where not is_read;

-- Keep the flag and the timestamp from drifting apart, whichever platform
-- writes them: a client that sets only `is_read` still gets a `read_at`.
create or replace function public.notifications_sync_read_at()
returns trigger
language plpgsql
as $fn$
begin
  if new.is_read and new.read_at is null then
    new.read_at := now();
  elsif not new.is_read then
    new.read_at := null;
  end if;
  return new;
end;
$fn$;

drop trigger if exists notifications_sync_read_at on public.notifications;
create trigger notifications_sync_read_at
  before insert or update of is_read, read_at on public.notifications
  for each row execute function public.notifications_sync_read_at();


-- 2. Row-level security -----------------------------------------------------

alter table public.notifications enable row level security;
alter table public.patients      enable row level security;
alter table public.profiles      enable row level security;

-- A patient reads their own alerts. `recipient_id` holds the auth user id, not
-- the patient chart id, so this is the column to compare.
drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own
  on public.notifications for select
  to authenticated
  using (recipient_id = auth.uid());

-- ...and may mark them read. Which columns they may touch is a grant, not a
-- policy: RLS cannot restrict columns on its own.
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own
  on public.notifications for update
  to authenticated
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

revoke update on public.notifications from authenticated;
grant update (is_read, read_at) on public.notifications to authenticated;

-- The chart. Read-only to the patient: the clinic owns its contents.
drop policy if exists patients_select_own on public.patients;
create policy patients_select_own
  on public.patients for select
  to authenticated
  using (profile_id = auth.uid());

-- The profile the patient maintains themselves.
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own
  on public.profiles for select
  to authenticated
  using (id = auth.uid());

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());


-- 3. Linking an admin-created chart to the account --------------------------

-- The clinic enters a chart before the patient has an account, so
-- `patients.profile_id` is null and the app - which reads charts by
-- `profile_id` - finds nothing. This links the two on the patient's first
-- load, matching on the email the account signed in with.
--
-- `security definer` on purpose: the patient must NOT be able to write
-- `profile_id` themselves, and the email has to come from the account rather
-- than from anything the client sends, or one patient could claim another's
-- chart. It links at most one chart, and only one that is still unclaimed.
--
-- NOTE: this trusts the email on the account, and only a confirmed one. If
-- sign-ups are possible without email confirmation, turn confirmation on
-- before installing this - otherwise drop the function and have the clinic set
-- `profile_id` by hand on the admin platform.
create or replace function public.claim_patient_chart()
returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
declare
  claimer_email text;
  claimed_id uuid;
begin
  if auth.uid() is null then
    return false;
  end if;

  -- Only a confirmed address may claim a chart.
  select lower(u.email) into claimer_email
    from auth.users u
   where u.id = auth.uid()
     and u.email_confirmed_at is not null;

  if claimer_email is null then
    return false;
  end if;

  -- Already linked: nothing to do, and not an error.
  if exists (select 1 from public.patients where profile_id = auth.uid()) then
    return false;
  end if;

  update public.patients p
     set profile_id = auth.uid(),
         updated_at = now()
   where p.id = (
           select p2.id
             from public.patients p2
            where p2.profile_id is null
              and lower(p2.email) = claimer_email
            order by p2.created_at
            limit 1
         )
  returning p.id into claimed_id;

  return claimed_id is not null;
end;
$fn$;

revoke all on function public.claim_patient_chart() from public;
grant execute on function public.claim_patient_chart() to authenticated;


-- 4. Realtime ---------------------------------------------------------------

-- Without this the clients get no push and only see changes on the next fetch.
-- RLS still applies, so a subscriber receives only their own rows.
alter publication supabase_realtime add table public.notifications;
alter publication supabase_realtime add table public.patients;
alter publication supabase_realtime add table public.profiles;

-- `replica identity full` puts the whole row in the change payload. The
-- clients filter on `recipient_id` / `profile_id`, which are not part of the
-- primary key, so without this an UPDATE can arrive without the column the
-- filter needs.
alter table public.notifications replica identity full;
alter table public.patients      replica identity full;
alter table public.profiles      replica identity full;


-- 5. Verification -----------------------------------------------------------

-- Charts the app cannot see, and whether an account exists to claim them.
-- Anything listed here is a patient whose profile will not appear in the app.
-- select p.id, p.patient_code, p.email, u.id as auth_user_id,
--        u.email_confirmed_at
--   from public.patients p
--   left join auth.users u on lower(u.email) = lower(p.email)
--  where p.profile_id is null
--  order by p.created_at desc;

-- Accounts with no chart at all - the clinic has to create one.
-- select u.id, u.email
--   from auth.users u
--   left join public.patients p on p.profile_id = u.id
--  where p.id is null;

-- Charts claimed by more than one account, which should return nothing.
-- select profile_id, count(*)
--   from public.patients
--  where profile_id is not null
--  group by profile_id having count(*) > 1;

-- Read state as the two platforms see it.
-- select recipient_id, count(*) as total,
--        count(*) filter (where is_read) as read,
--        count(*) filter (where is_read and read_at is null) as read_without_timestamp
--   from public.notifications group by recipient_id;

-- Tables actually published for realtime.
-- select schemaname, tablename from pg_publication_tables
--  where pubname = 'supabase_realtime' order by tablename;
