-- Confirm a booking as soon as its down payment is paid.
--
-- NOTE (2026-09-25): the mobile app now books through the website's own
-- book_appointment_v5 / book_appointment_v6, which already confirm a paid
-- booking. This trigger is an optional safety net for any other path that
-- records a paid deposit on a 'Pending' row (including the older
-- book_appointment_with_wallet), and its fix-up section can repair bookings
-- the app made before the switch.
--
-- Why: `book_appointment_with_wallet()` (docs/realtime_data_sync_migration.sql),
-- which the mobile app books through, inserts every appointment as 'Pending'
-- even when it has just taken the 20% down payment from the wallet. The
-- website's own path (book_appointment_v5 / v6) returns the visit as
-- 'Confirmed' once paid, so the same booking read differently in the two apps.
--
-- What: a trigger on `appointments` that moves a 'Pending' row to 'Confirmed'
-- (and stamps `confirmed_at`) at the moment `downpayment_paid_at` is first set
-- with a positive `downpayment_amount`. It fires on:
--   * INSERT — a booking created already paid (the app's wallet checkout);
--   * UPDATE — only when `downpayment_paid_at` goes from NULL to a value (a
--     down payment settled later, e.g. pay_appointment_from_wallet).
-- It does NOT fire on any other update, so a reschedule that deliberately puts
-- a paid visit back to 'Pending' for the clinic to re-confirm stays Pending,
-- and nothing ever un-confirms, cancels or completes a visit.
--
-- Safe to run more than once. Run in the Supabase SQL editor.

create or replace function public.confirm_paid_booking()
returns trigger
language plpgsql
set search_path = public
as $fn$
begin
  if new.status::text = 'Pending'
     and new.downpayment_paid_at is not null
     and coalesce(new.downpayment_amount, 0) > 0
     and (tg_op = 'INSERT' or old.downpayment_paid_at is null)
  then
    new.status := 'Confirmed';
    new.confirmed_at := coalesce(new.confirmed_at, new.downpayment_paid_at, now());
  end if;
  return new;
end;
$fn$;

drop trigger if exists trg_confirm_paid_booking on public.appointments;
create trigger trg_confirm_paid_booking
  before insert or update of downpayment_paid_at on public.appointments
  for each row
  execute function public.confirm_paid_booking();

-- ---------------------------------------------------------------------------
-- OPTIONAL one-time fix-up for bookings made before the trigger existed.
--
-- This CHANGES DATA: every live, not-yet-rescheduled 'Pending' appointment
-- whose down payment was paid becomes 'Confirmed'. Preview it first:
--
--   select id, confirmation_code, appointment_date, status, downpayment_paid_at
--     from public.appointments
--    where status::text = 'Pending'
--      and downpayment_paid_at is not null
--      and coalesce(downpayment_amount, 0) > 0
--      and archived_at is null
--      and appointment_date >= current_date;
--
-- Then, if that list is right, run:
--
--   update public.appointments
--      set status = 'Confirmed',
--          confirmed_at = coalesce(confirmed_at, downpayment_paid_at)
--    where status::text = 'Pending'
--      and downpayment_paid_at is not null
--      and coalesce(downpayment_amount, 0) > 0
--      and archived_at is null
--      and appointment_date >= current_date;
--
-- A visit the patient rescheduled after paying was put back to 'Pending' on
-- purpose, for the clinic to re-confirm; check the preview for any of those
-- before updating.
