-- Notifications schema notes — OPTIONAL
--
-- Nothing here is required. The app reads `notifications` adaptively: it asks
-- for `type`, `is_read` and `read_at`, and drops whichever the server reports
-- as `42703 undefined_column`, so it works against this project as it stands.
--
-- Background. The live project has:
--
--     notifications(id, title, body, read_at, created_at, recipient_id)
--
-- but the app's query also named `type` and `is_read`. Asking for a column
-- that is not there fails the whole request, and that one failure used to take
-- the entire patient record down with it — every screen showed
-- "We could not load your records. Check your connection and try again."
-- even though the connection was fine. The app no longer works that way: a
-- section that cannot be read costs the patient that section alone.
--
-- What is still lost without `type`
-- ---------------------------------
-- `PatientApi.channelFor` reads `notifications.type` to decide whether an
-- alert is a reminder, a payment notice or a status update. Without the
-- column every row from this table falls to `statusUpdate`, so a patient who
-- has muted reminders or payment alerts in Settings still receives them as
-- status updates. Notices the app derives from the record itself (bookings,
-- charges, wallet movements) are unaffected — they carry their own channel.
--
-- Run the statement below to restore that, if the clinic's web platform is
-- also updated to write the column. It is additive and changes no policy.

alter table public.notifications
    add column if not exists type text;

-- `is_read` is deliberately not added. `read_at` already records a read, the
-- app derives read state from it, and a second column for the same fact needs
-- a trigger to keep the two in step (see realtime_data_sync_migration.sql).

-- Realtime
-- --------
-- The app logs, at startup:
--
--     Realtime (notification_state) unavailable: ... Please check Realtime is
--     enabled for the given connect parameters: [... table: notification_state ...]
--
-- That table is not in the `supabase_realtime` publication on this project.
-- Read state then reaches the device on the next load or resume rather than
-- immediately; nothing fails. `realtime_data_sync_migration.sql` adds it, and
-- the statement below is the part that matters on its own.

alter publication supabase_realtime add table public.notification_state;
