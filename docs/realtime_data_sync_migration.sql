-- Live data for the patient mobile app, written against the schema the
-- production project actually has (probed 2026-09-14), not against the older
-- `sync_migration.sql` / `service_doctor_wallet_migration.sql`, which were
-- never applied and assume columns that do not exist (`patients.wallet_balance`,
-- `appointments.total_amount`, `member_specializations`, ...).
--
-- Run in the Supabase SQL editor (service role). Idempotent: a re-run is safe.
-- Nothing here changes an existing RLS policy or column the admin web portal
-- writes, so the portal keeps working exactly as before. Section 6 is
-- verification only.
--
-- What it adds:
--   1. `notifications.read_at`, kept in step with `is_read` by a trigger.
--   2. `claim_patient_chart()` - links an admin-created chart to the account
--      that signs in with the same confirmed email.
--   3. `patient_doctor_roster()` - the dentist roster a patient session may see
--      (members + member_services + doctor_schedules + exceptions + photo),
--      without opening `members` or `profiles` to patients.
--   4. `book_appointment_with_wallet()` / `pay_appointment_from_wallet()` -
--      atomic wallet checkout on the live columns (`estimated_total`,
--      `downpayment_amount`, ledger `direction` in/out).
--   5. Realtime publication for every table the app displays.


-- 1. Notification read state ------------------------------------------------

alter table public.notifications
  add column if not exists read_at timestamptz;

update public.notifications
   set read_at = coalesce(read_at, created_at)
 where is_read and read_at is null;

create index if not exists notifications_recipient_created_idx
    on public.notifications (recipient_id, created_at desc);

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


-- 2. Linking an admin-created chart to the account --------------------------

-- `security definer`: the patient must never write `profile_id` themselves, and
-- the email comes from `auth.users` (confirmed only), never from the client.
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

  select lower(u.email) into claimer_email
    from auth.users u
   where u.id = auth.uid()
     and u.email_confirmed_at is not null;

  if claimer_email is null then
    return false;
  end if;

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
              and p2.archived_at is null
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


-- 3. Dentist roster for patient sessions ------------------------------------

-- Only what a patient needs to pick and recognise a dentist: no email, phone,
-- permissions or employment data. `clinic_days` uses Postgres numbering
-- (0 = Sunday); `off_dates` are upcoming whole-day exceptions.
create or replace function public.patient_doctor_roster()
returns table (
  id uuid,
  full_name text,
  specialization text,
  specialization_codes text[],
  clinic_days int[],
  procedure_ids uuid[],
  off_dates date[],
  avatar_url text
)
language sql
stable
security definer
set search_path = public
as $fn$
  select m.id,
         m.full_name,
         coalesce(nullif(lower(btrim(m.specialization)), ''), 'general'),
         coalesce(
           (select array_agg(distinct lower(btrim(c)))
              from unnest(coalesce(m.specializations::text[], '{}'::text[]) || array[m.specialization::text]) as c
             where c is not null and btrim(c) <> ''),
           array['general']
         ),
         coalesce(
           -- `day_of_week` is the enum `weekday` ('Mon' .. 'Sun'); mapped to
           -- Postgres numbering (0 = Sunday) for the app.
           (select array_agg(distinct case ds.day_of_week::text
                                        when 'Sun' then 0 when 'Mon' then 1 when 'Tue' then 2
                                        when 'Wed' then 3 when 'Thu' then 4 when 'Fri' then 5
                                        when 'Sat' then 6
                                      end)
              from public.doctor_schedules ds
             where ds.doctor_id = m.id),
           '{}'::int[]
         ),
         coalesce(
           (select array_agg(ms.procedure_id)
              from public.member_services ms
             where ms.member_id = m.id),
           '{}'::uuid[]
         ),
         coalesce(
           (select array_agg(ex.exception_date)
              from public.doctor_schedule_exceptions ex
             where ex.doctor_id = m.id
               and ex.is_off
               and ex.exception_date >= current_date),
           '{}'::date[]
         ),
         pr.avatar_url
    from public.members m
    left join public.profiles pr on pr.id = m.profile_id
   where auth.uid() is not null
     -- `role` is enum `user_role`, `status` is enum `member_status` ('Active').
     and m.role::text = 'doctor'
     and coalesce(m.status::text, 'Active') = 'Active'
   order by m.full_name;
$fn$;

revoke all on function public.patient_doctor_roster() from public;
grant execute on function public.patient_doctor_roster() to authenticated;


-- 4. Atomic wallet checkout -------------------------------------------------

-- The live schema keeps no balance column: the balance is the ledger. Locking
-- the patient row serialises two devices checking out at once, so the second
-- one re-reads the ledger after the first has written to it.
--
-- SQLSTATEs the app handles:
--   P0002  insufficient funds (message carries balance and amount required)
--   P0003  slot taken while the patient was checking out
--   P0004  chart does not belong to the caller
--   P0005  patient not yet approved by the clinic
create or replace function public.wallet_balance_of(p_patient_id uuid)
returns numeric
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(sum(case
           when lower(coalesce(t.direction, '')) in ('in', 'credit', 'topup', 'top_up', 'deposit')
             then t.amount
           else -t.amount
         end), 0)::numeric(12,2)
    from public.wallet_transactions t
   where t.patient_id = p_patient_id;
$fn$;

revoke all on function public.wallet_balance_of(uuid) from public;

create or replace function public.book_appointment_with_wallet(
  p_patient_id       uuid,
  p_procedure_ids    uuid[],
  p_appointment_date date,
  p_appointment_time time,
  p_duration_minutes int,
  p_total_amount     numeric,
  p_amount_to_pay    numeric,
  p_doctor_id        uuid default null,
  p_notes            text default null,
  p_method           text default 'Wallet',
  p_reference_no     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_balance     numeric(12,2);
  v_approved    timestamptz;
  v_appointment uuid;
  v_existing    uuid;
  v_end_time    time;
  v_clinic      uuid;
  v_reference   text := coalesce(nullif(btrim(p_reference_no), ''),
                                 'REF-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'));
begin
  if p_amount_to_pay is null or p_amount_to_pay < 0 then
    raise exception 'Amount to pay must not be negative' using errcode = '22023';
  end if;
  if array_length(p_procedure_ids, 1) is null then
    raise exception 'A booking needs at least one procedure' using errcode = '22023';
  end if;

  select p.approved_at, p.primary_clinic_id
    into v_approved, v_clinic
    from public.patients p
   where p.id = p_patient_id
     and p.profile_id = auth.uid()
   for update;

  if not found then
    raise exception 'That patient record does not belong to this account' using errcode = 'P0004';
  end if;
  if v_approved is null then
    raise exception 'This account is waiting for clinic approval' using errcode = 'P0005';
  end if;

  -- A retry with the same reference returns the first result.
  select a.id into v_existing
    from public.wallet_transactions t
    join public.appointments a on a.patient_id = t.patient_id
   where t.reference_no = v_reference
     and t.patient_id = p_patient_id
   order by a.created_at desc
   limit 1;

  if v_existing is not null then
    return jsonb_build_object('appointment_id', v_existing,
                              'wallet_balance', public.wallet_balance_of(p_patient_id),
                              'reference_no', v_reference,
                              'idempotent', true);
  end if;

  v_balance := public.wallet_balance_of(p_patient_id);
  if v_balance < p_amount_to_pay then
    raise exception 'Insufficient wallet balance: % available, % required',
      v_balance, p_amount_to_pay using errcode = 'P0002';
  end if;

  v_end_time := p_appointment_time + make_interval(mins => greatest(p_duration_minutes, 15));

  select a.id into v_existing
    from public.appointments a
    left join public.procedures pr on pr.id = a.procedure_id
   where a.appointment_date = p_appointment_date
     and a.archived_at is null
     -- enum `appointment_status`: Pending, Confirmed, Ongoing, Completed, Cancelled, No-Show
     and a.status::text not in ('Cancelled', 'No-Show')
     and (p_doctor_id is null or a.doctor_id is null or a.doctor_id = p_doctor_id)
     and a.appointment_time < v_end_time
     and (a.appointment_time + make_interval(mins => greatest(coalesce(pr.duration_min, 30), 15))) > p_appointment_time
   limit 1;

  if v_existing is not null then
    raise exception 'That time slot is no longer available' using errcode = 'P0003';
  end if;

  if v_clinic is null then
    select c.id into v_clinic from public.clinics c where c.is_active order by c.created_at limit 1;
  end if;

  insert into public.appointments (patient_id, doctor_id, procedure_id, clinic_id,
                                   appointment_date, appointment_time, status, notes,
                                   payment_method, created_by, estimated_total,
                                   downpayment_amount, downpayment_paid_at)
  values (p_patient_id, p_doctor_id, p_procedure_ids[1], v_clinic,
          p_appointment_date, p_appointment_time, 'Pending',
          nullif(btrim(coalesce(p_notes, '')), ''), p_method, auth.uid(), p_total_amount,
          p_amount_to_pay, case when p_amount_to_pay > 0 then now() end)
  returning id into v_appointment;

  if array_length(p_procedure_ids, 1) > 1 then
    insert into public.appointment_services (appointment_id, procedure_id, doctor_id,
                                             service_date, service_time)
    select v_appointment, unnest(p_procedure_ids[2:]), p_doctor_id,
           p_appointment_date, p_appointment_time;
  end if;

  if p_amount_to_pay > 0 then
    insert into public.wallet_transactions (patient_id, direction, amount, method,
                                            description, reference_no)
    values (p_patient_id, 'out', p_amount_to_pay, p_method,
            'Appointment Downpayment', v_reference);
  end if;

  return jsonb_build_object('appointment_id', v_appointment,
                            'wallet_balance', public.wallet_balance_of(p_patient_id),
                            'reference_no', v_reference,
                            'idempotent', false);
end;
$fn$;

revoke all on function public.book_appointment_with_wallet(uuid, uuid[], date, time, int,
  numeric, numeric, uuid, text, text, text) from public;
grant execute on function public.book_appointment_with_wallet(uuid, uuid[], date, time, int,
  numeric, numeric, uuid, text, text, text) to authenticated;

create or replace function public.pay_appointment_from_wallet(
  p_appointment_id uuid,
  p_amount         numeric,
  p_method         text default 'Wallet',
  p_reference_no   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_patient   uuid;
  v_balance   numeric(12,2);
  v_reference text := coalesce(nullif(btrim(p_reference_no), ''),
                               'REF-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'));
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero' using errcode = '22023';
  end if;

  select a.patient_id into v_patient
    from public.appointments a
    join public.patients p on p.id = a.patient_id
   where a.id = p_appointment_id
     and p.profile_id = auth.uid()
   for update of a, p;

  if not found then
    raise exception 'That appointment does not belong to this account' using errcode = 'P0004';
  end if;

  if exists (select 1 from public.wallet_transactions
              where reference_no = v_reference and patient_id = v_patient) then
    return jsonb_build_object('appointment_id', p_appointment_id,
                              'wallet_balance', public.wallet_balance_of(v_patient),
                              'reference_no', v_reference,
                              'idempotent', true);
  end if;

  v_balance := public.wallet_balance_of(v_patient);
  if v_balance < p_amount then
    raise exception 'Insufficient wallet balance: % available, % required',
      v_balance, p_amount using errcode = 'P0002';
  end if;

  update public.appointments
     set downpayment_amount = coalesce(downpayment_amount, 0) + p_amount,
         downpayment_paid_at = now(),
         payment_method = p_method
   where id = p_appointment_id;

  insert into public.wallet_transactions (patient_id, direction, amount, method,
                                          description, reference_no)
  values (v_patient, 'out', p_amount, p_method, 'Appointment Payment', v_reference);

  return jsonb_build_object('appointment_id', p_appointment_id,
                            'wallet_balance', public.wallet_balance_of(v_patient),
                            'reference_no', v_reference,
                            'idempotent', false);
end;
$fn$;

revoke all on function public.pay_appointment_from_wallet(uuid, numeric, text, text) from public;
grant execute on function public.pay_appointment_from_wallet(uuid, numeric, text, text) to authenticated;


-- 5. Realtime ---------------------------------------------------------------

-- Adds each table the app shows to `supabase_realtime`, skipping tables that
-- are already published (a plain `alter publication ... add table` errors on
-- a duplicate) and any that do not exist. RLS still applies: a subscriber only
-- receives rows their SELECT policy lets them read.
--
-- `replica identity full` puts the whole old row in UPDATE/DELETE payloads,
-- which the app's `patient_id` / `recipient_id` filters need.
do $realtime$
declare
  t text;
begin
  foreach t in array array[
    -- patient-owned
    'patients', 'profiles', 'notifications', 'notification_state', 'patient_messages',
    'appointments', 'appointment_services',
    'billing_records', 'billing', 'invoices', 'invoice_items', 'payment_receipts',
    'wallet_transactions',
    'tooth_records', 'treatment_notes', 'treatment_plans', 'treatment_plan_items',
    'patient_files',
    -- clinic reference data
    'procedures', 'specializations', 'members', 'member_services',
    'doctor_schedules', 'doctor_schedule_exceptions',
    'clinics', 'clinic_settings', 'clinic_closures',
    'booking_categories', 'booking_category_services'
  ]
  loop
    if to_regclass('public.' || t) is null then
      raise notice 'realtime: skipping missing table %', t;
      continue;
    end if;

    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime'
                      and schemaname = 'public'
                      and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;

    execute format('alter table public.%I replica identity full', t);
  end loop;
end
$realtime$;


-- 6. Verification -----------------------------------------------------------

-- Tables published for realtime. Every table in the list above should appear.
-- select tablename from pg_publication_tables
--  where pubname = 'supabase_realtime' order by tablename;

-- Charts the app cannot see yet (no linked account).
-- select p.id, p.email, u.id as auth_user_id, u.email_confirmed_at
--   from public.patients p
--   left join auth.users u on lower(u.email) = lower(p.email)
--  where p.profile_id is null and p.archived_at is null;

-- Roster as a patient session sees it (run with a patient's JWT, or
-- `set local role authenticated; set local request.jwt.claims = '{"sub":"<uid>"}';`).
-- select * from public.patient_doctor_roster();

-- Appointment status values in use. `appointment_status` is an enum whose
-- values are capitalised; the app writes 'Pending' and 'Cancelled'.
-- select status, count(*) from public.appointments group by status order by 2 desc;
-- select enum_range(null::appointment_status);

-- Wallet ledger direction values in use (the app writes 'in' / 'out').
-- select direction, count(*) from public.wallet_transactions group by direction;
