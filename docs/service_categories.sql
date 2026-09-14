-- Optional: hold the patient-facing service grouping in Supabase instead of in
-- the app (lib/data/service_categories.dart).
--
-- The app does NOT need this. It groups procedures by name at read time, which
-- is why the booking wizard already works without any schema change. Run this
-- only if you would rather the clinic control the grouping from the database.
--
-- Why a new column rather than reusing `procedures.category`: that column
-- already holds the clinic's own internal values (Cleaning, Restorative,
-- Surgery, Diagnostic, Orthodontic, Cosmetic) and is null on most rows.
-- Overwriting it would change what the clinic's own tools read.

-- 1. The column the app would read.
alter table public.procedures
  add column if not exists patient_category text;

comment on column public.procedures.patient_category is
  'Patient-facing booking group. One of: improve-smile, braces-alignment, '
  'child-dental-care, tooth-extraction, root-canal, jaw-problem, other. '
  'Null is treated as ''other'' by the app.';

-- 2. Backfill from the current procedure names.
update public.procedures set patient_category = 'improve-smile'
 where name in ('Teeth Whitening',
                'Veneers (Ceramic / Direct)',
                'Crowns / Smile Restoration',
                'Cosmetic Contouring');

update public.procedures set patient_category = 'braces-alignment'
 where name in ('Metal Braces',
                'Ceramic Braces',
                'Clear Aligners',
                'Retainers');

update public.procedures set patient_category = 'child-dental-care'
 where name in ('Preventive Care',
                'Fluoride Treatment',
                'Sealants',
                'Tooth Alignment Guidance');

update public.procedures set patient_category = 'tooth-extraction'
 where name in ('Simple Tooth Extraction',
                'Tooth Extraction',
                'Surgical Extraction',
                'Wisdom Tooth Removal',
                'Pre- and Post-Operative Care');

update public.procedures set patient_category = 'root-canal'
 where name in ('Root Canal Treatment',
                'Infection Removal',
                'Sealing and Restoration',
                'Follow-up Check-up');

update public.procedures set patient_category = 'jaw-problem'
 where name in ('TMJ Evaluation',
                'Bite Adjustment',
                'Jaw Pain Management',
                'Custom Night Guard');

-- Everything the lists above did not claim. As of writing that is
-- 'Dental Checkup' among the active rows: the 'other' group books it outright
-- rather than opening a submenu, so anything else landing here is unbookable
-- from the wizard until it is claimed by a group above.
update public.procedures set patient_category = 'other'
 where patient_category is null;

-- 3. Keep the values honest.
alter table public.procedures
  drop constraint if exists procedures_patient_category_check;

alter table public.procedures
  add constraint procedures_patient_category_check
  check (patient_category in ('improve-smile',
                              'braces-alignment',
                              'child-dental-care',
                              'tooth-extraction',
                              'root-canal',
                              'jaw-problem',
                              'other'));

-- 4. Check the result before wiring the app to it.
-- select patient_category, count(*), array_agg(name order by name)
--   from public.procedures where is_active group by 1 order by 1;

-- To switch the app over afterwards: add `patient_category` to the select in
-- ClinicApi.loadMenu, and in ClinicApi._serviceFrom prefer the column over
-- categoryIdForProcedure(name), keeping the name lookup as the fallback for
-- rows the clinic has not categorised yet.
