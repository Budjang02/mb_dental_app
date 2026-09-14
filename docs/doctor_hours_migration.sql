-- Doctor working hours for patient sessions.
--
-- Run in the Supabase SQL editor (service role). Additive and idempotent: it
-- creates one new function and changes no table, policy or existing function.
--
-- Why: the booking wizard must only offer a start time when a dentist
-- credentialed for the visit is actually working then, so the booking summary
-- can always name the dentist, their specialization and the time. A patient
-- session cannot read `doctor_schedules` directly, and
-- `patient_doctor_roster()` returns working days but not hours.
--
-- Live column types (probed 2026-09-14): `day_of_week` is the enum `weekday`
-- ('Mon' .. 'Sun'); `start_time`, `end_time`, `break_start`, `break_end` are
-- `time`.

create or replace function public.patient_doctor_hours()
returns table (
  doctor_id   uuid,
  day_of_week int,     -- Postgres numbering: 0 = Sunday .. 6 = Saturday
  start_time  time,
  end_time    time,
  break_start time,
  break_end   time
)
language sql
stable
security definer
set search_path = public
as $fn$
  select ds.doctor_id,
         case ds.day_of_week::text
           when 'Sun' then 0 when 'Mon' then 1 when 'Tue' then 2
           when 'Wed' then 3 when 'Thu' then 4 when 'Fri' then 5
           when 'Sat' then 6
         end,
         ds.start_time,
         ds.end_time,
         ds.break_start,
         ds.break_end
    from public.doctor_schedules ds
    join public.members m on m.id = ds.doctor_id
   where auth.uid() is not null
     and m.role::text = 'doctor'
     and coalesce(m.status::text, 'Active') = 'Active';
$fn$;

revoke all on function public.patient_doctor_hours() from public;
grant execute on function public.patient_doctor_hours() to authenticated;

-- Verification (as a signed-in patient, or with a patient JWT):
-- select * from public.patient_doctor_hours() order by doctor_id, day_of_week;
