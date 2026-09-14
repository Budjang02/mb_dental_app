-- SUPERSEDED - DO NOT RUN. Use docs/realtime_data_sync_migration.sql instead.
-- This file was never applied to production and does not match its schema:
-- `members.role` / `members.status` and `appointments.status` are enums with
-- different literals, the ledger records `direction` as in/out, the clinic maps
-- doctors to procedures in `member_services`, and there is no
-- `patients.wallet_balance`. It also revokes writes and replaces RLS policies
-- the admin web portal relies on. Kept for history only.
--
-- Service/doctor mapping and wallet payments, shared by the admin web portal,
-- the patient web build and the patient mobile app.
--
-- Run in the Supabase SQL editor (service role). Idempotent: a re-run is safe.
-- Section 6 is verification only.
--
-- What this fixes:
--   1. Services edited in the admin portal reach the patient app, and each one
--      resolves to the doctors holding the matching specialization.
--   2. Checkout deducts from the patient's wallet in one atomic transaction,
--      instead of two client-side writes that can half-succeed or race.
--
-- Existing shape this builds on (unchanged unless stated):
--   procedures(id, name, category, specialization, duration_min, base_price,
--              min_rate, max_rate, price_unit, is_active)
--   specializations(code, label, description, is_active)
--   members(id, full_name, role, specialization, specializations, status,
--           profile_id, created_at)          -- clinic staff, incl. dentists
--   doctor_schedules(id, doctor_id, day_of_week, start_time, end_time)
--   appointments(id, patient_id, doctor_id, procedure_id, appointment_date,
--                appointment_time, status, notes, payment_method, created_by,
--                confirmed_at, cancelled_at, cancellation_reason)
--   appointment_services(appointment_id, procedure_id)
--   wallet_transactions(id, patient_id, amount, direction, method,
--                       reference_no, description, created_at)


-- 1. Specializations as the single source of truth ---------------------------

-- `procedures.specialization` already holds these codes; the table is what
-- gives them a patient-facing label the app does not have to hardcode.
insert into public.specializations (code, label, description, is_active) values
  ('general',     'General Dentistry',  'Check-ups, cleaning, fillings and routine care.', true),
  ('ortho',       'Orthodontics',       'Braces, aligners and retainers.',                 true),
  ('endo',        'Endodontics',        'Root canal treatment and infection removal.',     true),
  ('restorative', 'Prosthodontics',     'Crowns, bridges and dentures.',                   true),
  ('surgery',     'Oral Surgery',       'Surgical and wisdom tooth extractions.',          true),
  ('esthetics',   'Cosmetic Dentistry', 'Whitening, veneers and smile design.',            true),
  ('pedo',        'Pediatric Dentistry','Dental care for children.',                       true),
  ('tmj',         'TMJ and Occlusion',  'Jaw pain, bite adjustment and night guards.',     true)
on conflict (code) do update
   set label = excluded.label,
       description = excluded.description,
       is_active = true;

-- Every procedure must name a specialization the table knows, so the app can
-- always resolve a service to a credential. Unset rows fall to general care.
update public.procedures
   set specialization = 'general'
 where specialization is null
    or specialization = ''
    or specialization not in (select code from public.specializations);

alter table public.procedures
  alter column specialization set default 'general';

alter table public.procedures
  alter column specialization set not null;

alter table public.procedures
  drop constraint if exists procedures_specialization_fkey;

alter table public.procedures
  add constraint procedures_specialization_fkey
  foreign key (specialization) references public.specializations (code)
  on update cascade;

create index if not exists procedures_specialization_idx
    on public.procedures (specialization) where is_active;


-- 2. Doctor to specialization mapping ---------------------------------------

-- `members.specialization` is one code and `members.specializations` is a list;
-- a dentist normally covers several, so the relation belongs in its own table.
-- procedures.specialization -> member_specializations -> members.
create table if not exists public.member_specializations (
  member_id           uuid not null references public.members (id) on delete cascade,
  specialization_code text not null references public.specializations (code) on update cascade,
  primary key (member_id, specialization_code)
);

create index if not exists member_specializations_code_idx
    on public.member_specializations (specialization_code);

-- Backfill from both existing columns. `specializations` may be a text[] or a
-- jsonb array depending on how the admin portal wrote it, so both are read.
insert into public.member_specializations (member_id, specialization_code)
select m.id, lower(btrim(code))
  from public.members m
  cross join lateral (
    select m.specialization as code
    where m.specialization is not null and btrim(m.specialization) <> ''
    union
    select jsonb_array_elements_text(to_jsonb(m.specializations))
    where m.specializations is not null
  ) src
 where lower(btrim(code)) in (select code from public.specializations)
on conflict do nothing;

-- Every dentist takes general care, which is what makes a check-up bookable
-- with whoever is in that day.
insert into public.member_specializations (member_id, specialization_code)
select id, 'general' from public.members
 where lower(coalesce(role, '')) in ('doctor', 'dentist')
on conflict do nothing;

-- What the patient app is allowed to see about clinic staff: no email, phone,
-- licence or employment data. `clinic_days` is the availability the booking
-- calendar greys days out by.
create or replace view public.doctor_directory
with (security_invoker = true) as
select m.id,
       m.full_name,
       coalesce(nullif(btrim(m.specialization), ''), 'general') as primary_specialization,
       coalesce(
         (select array_agg(ms.specialization_code order by ms.specialization_code)
            from public.member_specializations ms
           where ms.member_id = m.id),
         array['general']
       ) as specialization_codes,
       coalesce(
         (select array_agg(distinct ds.day_of_week order by ds.day_of_week)
            from public.doctor_schedules ds
           where ds.doctor_id = m.id),
         '{}'::int[]
       ) as clinic_days
  from public.members m
 where lower(coalesce(m.role, '')) in ('doctor', 'dentist')
   and lower(coalesce(m.status, 'active')) = 'active';

grant select on public.doctor_directory to authenticated;


-- 3. Read access for the patient role ---------------------------------------

alter table public.procedures            enable row level security;
alter table public.specializations       enable row level security;
alter table public.members               enable row level security;
alter table public.member_specializations enable row level security;
alter table public.doctor_schedules      enable row level security;

-- The bookable menu. Retired rows stay invisible: a patient must not be able
-- to book a procedure the clinic has disabled.
drop policy if exists procedures_select_active on public.procedures;
create policy procedures_select_active
  on public.procedures for select
  to authenticated
  using (is_active);

drop policy if exists specializations_select_active on public.specializations;
create policy specializations_select_active
  on public.specializations for select
  to authenticated
  using (is_active);

-- Only the dentist roster, and only through what the view exposes. The view is
-- `security_invoker`, so this policy is what it reads under.
drop policy if exists members_select_doctors on public.members;
create policy members_select_doctors
  on public.members for select
  to authenticated
  using (lower(coalesce(role, '')) in ('doctor', 'dentist')
         and lower(coalesce(status, 'active')) = 'active');

drop policy if exists member_specializations_select on public.member_specializations;
create policy member_specializations_select
  on public.member_specializations for select
  to authenticated
  using (exists (select 1 from public.members m
                  where m.id = member_id
                    and lower(coalesce(m.role, '')) in ('doctor', 'dentist')));

drop policy if exists doctor_schedules_select on public.doctor_schedules;
create policy doctor_schedules_select
  on public.doctor_schedules for select
  to authenticated
  using (exists (select 1 from public.members m
                  where m.id = doctor_id
                    and lower(coalesce(m.role, '')) in ('doctor', 'dentist')));

-- Live updates, so an admin edit reaches an open app without a reload.
alter publication supabase_realtime add table public.procedures;
alter publication supabase_realtime add table public.specializations;
alter publication supabase_realtime add table public.members;
alter publication supabase_realtime add table public.member_specializations;
alter publication supabase_realtime add table public.doctor_schedules;


-- 4. Wallet balance and transaction state -----------------------------------

-- The balance was summed from the ledger on the client, which cannot be locked
-- and so cannot be checked safely. It becomes a column the debit updates under
-- a row lock, with the ledger kept as the audit trail.
alter table public.patients
  add column if not exists wallet_balance numeric(12,2) not null default 0;

alter table public.wallet_transactions
  add column if not exists status text not null default 'completed';

alter table public.wallet_transactions
  add column if not exists balance_after numeric(12,2);

alter table public.wallet_transactions
  add column if not exists appointment_id uuid;

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_status_check;

alter table public.wallet_transactions
  add constraint wallet_transactions_status_check
  check (status in ('pending', 'completed', 'failed', 'reversed'));

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_amount_check;

alter table public.wallet_transactions
  add constraint wallet_transactions_amount_check check (amount > 0);

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_appointment_id_fkey;

alter table public.wallet_transactions
  add constraint wallet_transactions_appointment_id_fkey
  foreign key (appointment_id) references public.appointments (id) on delete set null;

-- A retried checkout must not debit twice.
create unique index if not exists wallet_transactions_reference_no_key
    on public.wallet_transactions (reference_no) where reference_no is not null;

create index if not exists wallet_transactions_patient_created_idx
    on public.wallet_transactions (patient_id, created_at desc);

-- Seed the new column from the ledger that was being summed until now. Only
-- completed movements count.
update public.patients p
   set wallet_balance = coalesce((
         select sum(case when t.direction = 'credit' then t.amount else -t.amount end)
           from public.wallet_transactions t
          where t.patient_id = p.id
            and coalesce(t.status, 'completed') = 'completed'
       ), 0)
 where p.wallet_balance = 0;

-- A wallet can never go negative, whichever code path writes it.
alter table public.patients
  drop constraint if exists patients_wallet_balance_check;

alter table public.patients
  add constraint patients_wallet_balance_check check (wallet_balance >= 0);

-- What the booking owes and what it has been paid.
alter table public.appointments
  add column if not exists total_amount numeric(12,2) not null default 0;

alter table public.appointments
  add column if not exists paid_amount numeric(12,2) not null default 0;

alter table public.appointments
  add column if not exists payment_status text not null default 'unpaid';

alter table public.appointments
  drop constraint if exists appointments_payment_status_check;

alter table public.appointments
  add constraint appointments_payment_status_check
  check (payment_status in ('unpaid', 'partially_paid', 'paid', 'refunded'));


-- 5. Atomic checkout --------------------------------------------------------

-- One call does the whole checkout: lock the wallet, check the funds, insert
-- the booking, write the ledger entry, move the balance, set the payment state.
-- Either all of it happens or none of it does — a plpgsql function runs inside
-- the caller's transaction, and every raise rolls the lot back.
--
-- `security definer` so the patient can be held to read-only access on
-- `patients` and `wallet_transactions` while this, and only this, moves money.
--
-- Errors the app handles by SQLSTATE:
--   P0002  insufficient funds (message carries balance and amount required)
--   P0003  the slot was taken while the patient was checking out
--   P0004  the chart does not belong to the caller
create or replace function public.book_appointment_with_wallet(
  p_patient_id      uuid,
  p_procedure_ids   uuid[],
  p_appointment_date date,
  p_appointment_time time,
  p_duration_minutes int,
  p_total_amount    numeric,
  p_amount_to_pay   numeric,
  p_doctor_id       uuid   default null,
  p_notes           text   default null,
  p_method          text   default 'Wallet',
  p_reference_no    text   default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_balance       numeric(12,2);
  v_appointment   uuid;
  v_reference     text := coalesce(nullif(btrim(p_reference_no), ''),
                                   'REF-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'));
  v_existing      uuid;
  v_end_time      time;
  v_payment_state text;
begin
  if p_amount_to_pay is null or p_amount_to_pay < 0 then
    raise exception 'Amount to pay must not be negative' using errcode = '22023';
  end if;

  if array_length(p_procedure_ids, 1) is null then
    raise exception 'A booking needs at least one procedure' using errcode = '22023';
  end if;

  -- The caller may only spend their own wallet. Locked here, so two devices
  -- checking out at once queue instead of both passing the balance check.
  select p.wallet_balance into v_balance
    from public.patients p
   where p.id = p_patient_id
     and p.profile_id = auth.uid()
   for update;

  if not found then
    raise exception 'That patient record does not belong to this account'
      using errcode = 'P0004';
  end if;

  if v_balance < p_amount_to_pay then
    raise exception 'Insufficient wallet balance: % available, % required',
      v_balance, p_amount_to_pay using errcode = 'P0002';
  end if;

  -- An idempotent retry returns the first result rather than debiting again.
  select t.appointment_id into v_existing
    from public.wallet_transactions t
   where t.reference_no = v_reference;

  if v_existing is not null then
    select wallet_balance into v_balance from public.patients where id = p_patient_id;
    return jsonb_build_object('appointment_id', v_existing,
                              'wallet_balance', v_balance,
                              'reference_no', v_reference,
                              'idempotent', true);
  end if;

  -- The slot may have been taken while the patient was on the summary step.
  v_end_time := p_appointment_time + make_interval(mins => greatest(p_duration_minutes, 15));

  select a.id into v_existing
    from public.appointments a
   where a.appointment_date = p_appointment_date
     and a.status <> 'cancelled'
     and (p_doctor_id is null or a.doctor_id is null or a.doctor_id = p_doctor_id)
     and a.appointment_time < v_end_time
     and (a.appointment_time + make_interval(mins => 15)) > p_appointment_time
   limit 1;

  if v_existing is not null then
    raise exception 'That time slot is no longer available' using errcode = 'P0003';
  end if;

  v_payment_state := case
    when p_amount_to_pay >= p_total_amount and p_total_amount > 0 then 'paid'
    when p_amount_to_pay > 0 then 'partially_paid'
    else 'unpaid'
  end;

  insert into public.appointments (patient_id, doctor_id, procedure_id, appointment_date,
                                   appointment_time, status, notes, payment_method,
                                   created_by, total_amount, paid_amount, payment_status)
  values (p_patient_id, p_doctor_id, p_procedure_ids[1], p_appointment_date,
          p_appointment_time, 'pending', nullif(btrim(coalesce(p_notes, '')), ''), p_method,
          auth.uid(), p_total_amount, p_amount_to_pay, v_payment_state)
  returning id into v_appointment;

  if array_length(p_procedure_ids, 1) > 1 then
    insert into public.appointment_services (appointment_id, procedure_id)
    select v_appointment, unnest(p_procedure_ids[2:]);
  end if;

  if p_amount_to_pay > 0 then
    update public.patients
       set wallet_balance = wallet_balance - p_amount_to_pay
     where id = p_patient_id
    returning wallet_balance into v_balance;

    insert into public.wallet_transactions (patient_id, amount, direction, method,
                                            reference_no, description, status,
                                            balance_after, appointment_id)
    values (p_patient_id, p_amount_to_pay, 'debit', p_method, v_reference,
            'Appointment Downpayment', 'completed', v_balance, v_appointment);
  end if;

  return jsonb_build_object('appointment_id', v_appointment,
                            'wallet_balance', v_balance,
                            'reference_no', v_reference,
                            'payment_status', v_payment_state,
                            'idempotent', false);
end;
$fn$;

revoke all on function public.book_appointment_with_wallet(uuid, uuid[], date, time, int,
  numeric, numeric, uuid, text, text, text) from public;
grant execute on function public.book_appointment_with_wallet(uuid, uuid[], date, time, int,
  numeric, numeric, uuid, text, text, text) to authenticated;

-- Settling the balance on a booking that already exists, same guarantees.
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
  v_patient  uuid;
  v_total    numeric(12,2);
  v_paid     numeric(12,2);
  v_balance  numeric(12,2);
  v_reference text := coalesce(nullif(btrim(p_reference_no), ''),
                               'REF-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS'));
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'Amount must be greater than zero' using errcode = '22023';
  end if;

  select a.patient_id, a.total_amount, a.paid_amount
    into v_patient, v_total, v_paid
    from public.appointments a
    join public.patients p on p.id = a.patient_id
   where a.id = p_appointment_id
     and p.profile_id = auth.uid()
   for update of a;

  if not found then
    raise exception 'That appointment does not belong to this account' using errcode = 'P0004';
  end if;

  select wallet_balance into v_balance
    from public.patients where id = v_patient for update;

  if v_balance < p_amount then
    raise exception 'Insufficient wallet balance: % available, % required',
      v_balance, p_amount using errcode = 'P0002';
  end if;

  if exists (select 1 from public.wallet_transactions where reference_no = v_reference) then
    return jsonb_build_object('appointment_id', p_appointment_id,
                              'wallet_balance', v_balance,
                              'reference_no', v_reference,
                              'idempotent', true);
  end if;

  update public.patients
     set wallet_balance = wallet_balance - p_amount
   where id = v_patient
  returning wallet_balance into v_balance;

  update public.appointments
     set paid_amount = paid_amount + p_amount,
         payment_status = case
           when paid_amount + p_amount >= total_amount and total_amount > 0 then 'paid'
           else 'partially_paid'
         end,
         payment_method = p_method
   where id = p_appointment_id;

  insert into public.wallet_transactions (patient_id, amount, direction, method,
                                          reference_no, description, status,
                                          balance_after, appointment_id)
  values (v_patient, p_amount, 'debit', p_method, v_reference,
          'Appointment Payment', 'completed', v_balance, p_appointment_id);

  return jsonb_build_object('appointment_id', p_appointment_id,
                            'wallet_balance', v_balance,
                            'reference_no', v_reference,
                            'idempotent', false);
end;
$fn$;

revoke all on function public.pay_appointment_from_wallet(uuid, numeric, text, text) from public;
grant execute on function public.pay_appointment_from_wallet(uuid, numeric, text, text) to authenticated;

-- Top-ups come from the payment provider's webhook, never from the app, so
-- `credit` stays off the patient's hands: no insert policy is granted below.
drop policy if exists wallet_transactions_select_own on public.wallet_transactions;
create policy wallet_transactions_select_own
  on public.wallet_transactions for select
  to authenticated
  using (exists (select 1 from public.patients p
                  where p.id = patient_id and p.profile_id = auth.uid()));

alter table public.wallet_transactions enable row level security;

-- Money only moves through the functions above.
revoke insert, update, delete on public.wallet_transactions from authenticated;
revoke update on public.patients from authenticated;

alter publication supabase_realtime add table public.wallet_transactions;
alter table public.wallet_transactions replica identity full;


-- 6. Verification -----------------------------------------------------------

-- Services and the doctors each one resolves to. A service with 0 doctors is
-- bookable in the admin portal but unstaffable in the app.
-- select pr.name, pr.specialization, count(d.id) as doctors,
--        array_agg(d.full_name order by d.full_name) filter (where d.id is not null) as roster
--   from public.procedures pr
--   left join public.doctor_directory d on pr.specialization = any (d.specialization_codes)
--  where pr.is_active
--  group by pr.name, pr.specialization
--  order by doctors, pr.name;

-- Doctors with no schedule: nothing they alone cover can be booked at all.
-- select full_name, specialization_codes, clinic_days
--   from public.doctor_directory where clinic_days = '{}'::int[];

-- Specialization codes used by procedures but held by nobody.
-- select distinct pr.specialization
--   from public.procedures pr
--  where pr.is_active
--    and not exists (select 1 from public.member_specializations ms
--                     where ms.specialization_code = pr.specialization);

-- Wallet column against the ledger it was seeded from. Should return nothing.
-- select p.id, p.wallet_balance, l.ledger
--   from public.patients p
--   join lateral (
--     select coalesce(sum(case when t.direction = 'credit' then t.amount else -t.amount end), 0)
--       from public.wallet_transactions t
--      where t.patient_id = p.id and t.status = 'completed'
--   ) l(ledger) on true
--  where p.wallet_balance <> l.ledger;

-- Bookings whose paid amount disagrees with their payment state.
-- select id, total_amount, paid_amount, payment_status
--   from public.appointments
--  where (payment_status = 'paid' and paid_amount < total_amount)
--     or (payment_status = 'unpaid' and paid_amount > 0);
