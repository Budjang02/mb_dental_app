# SETUP.md — M&B Dental Patient App

This guide explains how to set up, run, and build this project on a new computer.
It is written for a developer who has never worked on this project before.

Everything below is based on the files in this repository. Where the repository
does not contain the information, the guide says **REQUIRES MANUAL
CONFIGURATION** and explains what you must get from the project owner.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [System Requirements](#2-system-requirements)
3. [Required Accounts and Services](#3-required-accounts-and-services)
4. [Clone or Transfer the Project](#4-clone-or-transfer-the-project)
5. [Environment Configuration](#5-environment-configuration)
6. [Supabase Setup](#6-supabase-setup)
7. [Website Setup](#7-website-setup)
8. [Flutter Mobile App Setup](#8-flutter-mobile-app-setup)
9. [Firebase](#9-firebase)
10. [Supabase Edge Functions](#10-supabase-edge-functions)
11. [Database Migration Order](#11-database-migration-order)
12. [How to Run the Complete System](#12-how-to-run-the-complete-system)
13. [Setup Verification](#13-setup-verification)
14. [Common Errors and Troubleshooting](#14-common-errors-and-troubleshooting)
15. [Project Folder Structure](#15-project-folder-structure)
16. [Moving the System to Another Computer](#16-moving-the-system-to-another-computer)
17. [Setting Up on Another Device](#17-setting-up-on-another-device)
18. [Security Notes](#18-security-notes)
19. [Quick Setup Checklist](#19-quick-setup-checklist)

---

## 1. Project Overview

### What the system is

**M&B Dental** (`mb_dental_app`) is the **patient mobile app** for Mariano and
Bolasoc Dental Center. Patients use it to:

- Register, verify their email with a 6-digit code (OTP), sign in, and reset their password.
- See their patient profile, dental records (tooth chart / odontogram), treatment notes, and clinic documents.
- Book, reschedule, and cancel appointments.
- Show a **check-in QR code** for a confirmed appointment.
- Use a **patient wallet**: cash in with GCash or GrabPay (through PayMongo), pay bills and clinic visit requests, and see receipts and transaction history.
- **Scan the clinic's Patient Wallet QR** with the phone camera to open a bill.
- Receive in-app notifications and messages from the clinic, updated in real time.

### The complete system has more parts than this repository

This repository contains **only the Flutter mobile app**. The app shares one
Supabase backend with the clinic's **website / admin web portal**, which lives
in a **separate repository**. The source code comments say so in several
places (for example `docs/realtime_data_sync_migration.sql` and
`lib/repositories/patient_api.dart`).

| Part | Where it lives | In this repository? |
|------|----------------|---------------------|
| Flutter patient app (Android, also iOS/web/desktop scaffolding) | `lib/`, `android/`, `ios/`, ... | **Yes** |
| Supabase database (tables, enums, RLS, most RPC functions) | Supabase cloud project | **Partly** — only add-on SQL scripts in `docs/` |
| Supabase Auth (email + password, email OTP, password reset) | Supabase cloud project | Configured in the Supabase dashboard |
| Supabase Storage (`patient-files`, `avatars` buckets) | Supabase cloud project | No — used by the app, created elsewhere |
| Supabase Realtime | Supabase cloud project | Yes — enabled by a script in `docs/` |
| Supabase Edge Functions (PayMongo payments) | Website / backend repository | **No** |
| Clinic website / admin web portal | Separate repository | **No** |
| Firebase | Firebase cloud project | Only the Android config file `android/app/google-services.json` |
| Firebase Hosting | — | **Not found** in this repository (no `firebase.json` or `.firebaserc`) |

### Technologies actually used

- **Flutter** (Dart SDK `^3.12.2`, see `pubspec.yaml`). The project was created with Flutter stable, revision `ad70ec4617` (see `.metadata`), which is **Flutter 3.44.4 / Dart 3.12.2**.
- **Supabase** through `supabase_flutter` — database, authentication, storage, realtime, Edge Function calls.
- **Firebase** through `firebase_core` (the app calls `Firebase.initializeApp()` at startup). `cloud_firestore` is listed as a dependency but is not used in `lib/`.
- **flutter_dotenv** — reads the Supabase URL and key from a bundled `.env` file.
- **PayMongo** (GCash, GrabPay) — only through Supabase Edge Functions. The app never talks to PayMongo directly.
- **Android build:** Gradle 9.1.0, Android Gradle Plugin 8.11.1, Kotlin 2.2.20, Google Services plugin 4.4.2, Java 17 bytecode target.
- Other packages: `mobile_scanner` (camera QR scanning), `qr` (QR drawing), `pdf` + `printing` (PDF receipts and records), `image_picker`, `url_launcher`, `share_plus`, `table_calendar`, `lottie`, `flutter_svg`, `shared_preferences`, `flutter_native_splash`, `flutter_launcher_icons`.

---

## 2. System Requirements

### Required software

| Software | Version | Why |
|----------|---------|-----|
| **Git** | Any recent version | Clone the repository. |
| **Flutter SDK** | **3.44.x stable** (Dart **3.12.2** or newer in the 3.x line) | `pubspec.yaml` requires `sdk: ^3.12.2`. Older Flutter versions will fail at `flutter pub get`. |
| **Android Studio** | Recent stable version | Provides the Android SDK, emulator, and a bundled Java (JBR). Recommended IDE for this project. |
| **Android SDK** | Installed through Android Studio | Includes Platform Tools (`adb`), Build Tools, and an Android platform. Flutter picks `compileSdk`/`targetSdk`/`minSdk` itself (`android/app/build.gradle.kts`). |
| **Android SDK Command-line Tools** | Latest | Needed by `flutter doctor --android-licenses`. |
| **Java JDK 17 or newer** | 17+ | The Android build targets Java 17. Android Studio's bundled JBR works. |

### Optional software

| Software | Optional because |
|----------|------------------|
| **VS Code** with the Flutter and Dart extensions | Alternative to Android Studio. You still need the Android SDK. |
| **Supabase CLI** | Only needed to deploy Edge Functions. The Edge Function code is **not** in this repository. |
| **Firebase CLI** | Not needed. This repository has no Firebase Hosting configuration. |
| **Node.js / npm** | Not needed for this repository. There is **no `package.json`** here. The website repository may need it. |
| **Xcode + macOS** | Only to build the iOS version. The main development target is Android on Windows. |
| A physical Android phone | Recommended to test the camera QR scanner and PayMongo checkout. |

### Hardware note

`android/gradle.properties` sets `org.gradle.jvmargs=-Xmx8G`. Gradle asks for up
to 8 GB of memory. A computer with 16 GB of RAM is recommended. See
[Troubleshooting](#14-common-errors-and-troubleshooting) if your computer has less.

---

## 3. Required Accounts and Services

Ask the project owner for the following **before you start**:

1. **Supabase project access** (required)
   - You need the **Project URL** and the **anon / publishable key** from *Supabase Dashboard → Project Settings → API*.
   - To run SQL scripts, configure Auth, or deploy Edge Functions, you need to be a **member of the Supabase organization/project** with developer or owner access.
2. **Firebase project access** (required to build Android)
   - The Android app needs `android/app/google-services.json`. A copy is already in this repository.
   - If you create a new Firebase project, you need access to the Firebase console to download a new file.
3. **GitHub access** (required)
   - The repository is `https://github.com/Budjang02/mb_dental_app`. You need read access to clone it.
4. **Website / admin portal repository access** (required for a full new backend)
   - The base database schema, most RPC functions, and the Edge Functions come from that repository.
   - **REQUIRES MANUAL CONFIGURATION:** ask the project owner for the repository URL and its own setup guide.
5. **PayMongo account** (required only for wallet cash-in and online payments)
   - The PayMongo secret key and webhook secret are stored as Supabase Edge Function secrets, never in this app.

**Never** ask for, share, or store the Supabase `service_role` key, database
password, PayMongo secret key, or SMTP password in this repository.

---

## 4. Clone or Transfer the Project

### Option A — Clone with Git (recommended)

Run these commands in **Windows PowerShell**. Choose any parent folder. The
example uses `D:\Development`.

1. Open PowerShell.
2. Go to the parent folder:
   ```powershell
   cd D:\Development
   ```
3. Clone the repository:
   ```powershell
   git clone https://github.com/Budjang02/mb_dental_app.git
   ```
4. Go into the project folder. **All later Flutter commands run from this folder** (the folder that contains `pubspec.yaml`):
   ```powershell
   cd D:\Development\mb_dental_app
   ```

### Option B — The project folder was copied manually (USB, ZIP, network share)

1. Copy the whole `mb_dental_app` folder to the new computer, for example to `D:\Development\mb_dental_app`.
2. **Delete these folders/files** from the copy. They are machine-specific and are rebuilt automatically:
   - `build\`
   - `.dart_tool\`
   - `.flutter-plugins-dependencies`
   - `android\local.properties` (contains the old computer's SDK paths)
   - `android\.gradle\` (if present)
   - `.idea\` and `*.iml` (Android Studio project settings; optional to delete)

   PowerShell, run from the project folder:
   ```powershell
   cd D:\Development\mb_dental_app
   Remove-Item -Recurse -Force build, .dart_tool, android\.gradle -ErrorAction SilentlyContinue
   Remove-Item -Force .flutter-plugins-dependencies, android\local.properties -ErrorAction SilentlyContinue
   ```
3. Check that the `.env` file was copied. It is **not** in Git, so a copied folder may or may not contain it. If it is missing, create it (see [section 5](#5-environment-configuration)).
4. Continue with [section 8](#8-flutter-mobile-app-setup). `flutter pub get` recreates the deleted files.

---

## 5. Environment Configuration

### Files

| File | In Git? | Purpose |
|------|---------|---------|
| `.env.example` | Yes | Template. Copy it to `.env`. |
| `.env` | **No** (ignored by `.gitignore`) | Supabase URL and anon key. **Bundled into the app** as an asset (`pubspec.yaml` lists `- .env`). The app does not build without it. |
| `android/app/google-services.json` | Yes | Firebase Android configuration. |
| `android/local.properties` | No | Created automatically by Flutter. Holds `flutter.sdk` and `sdk.dir` paths for this computer. |

### Variables in `.env`

The app reads exactly two variables (`lib/services/supabase_service.dart`):

| Variable | Example placeholder | Where to get it | Public or secret? |
|----------|---------------------|-----------------|-------------------|
| `VITE_SUPABASE_URL` | `YOUR_SUPABASE_URL` (format: `https://<project-ref>.supabase.co`) | Supabase Dashboard → Project Settings → API → Project URL | Public / client-safe |
| `VITE_SUPABASE_ANON_KEY` | `YOUR_SUPABASE_ANON_KEY` | Supabase Dashboard → Project Settings → API → `anon` / publishable key | Public / client-safe (protected by RLS) |

The `VITE_` prefix exists because the same variable names are used by the
website. The Flutter app reads them with these exact names, so do not rename them.

The URL **must** start with `https://`. The app refuses to start otherwise.

> Some developer copies of `.env` also contain `VITE_PAYMONGO_PUBLIC_KEY`. The
> Flutter app does **not** read it. You can leave it out.

### Create `.env`

Run from the project folder:

```powershell
cd D:\Development\mb_dental_app
Copy-Item .env.example .env
notepad .env
```

Edit it so it looks like this, with your own values:

```env
VITE_SUPABASE_URL=YOUR_SUPABASE_URL
VITE_SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

### Public keys vs. private secrets

| Safe to put in the app (`.env`) | **Never** put in the app or in Git |
|---------------------------------|-------------------------------------|
| Supabase Project URL | Supabase `service_role` key |
| Supabase `anon` / publishable key | Supabase database password |
| Firebase `google-services.json` (client config) | PayMongo **secret** key, PayMongo webhook secret |
| | SMTP username/password |
| | Android release keystore and its passwords |

Everything in `.env` is **bundled into the APK**. Anyone with the APK can read
it. That is why only the anon key may go there.

---

## 6. Supabase Setup

### 6.1 Important: what exists and what does not

- The **production Supabase project already exists**. In normal development you **connect to it** by filling in `.env`. You do **not** need to create tables.
- This repository does **not** contain the base database schema, a `supabase/` folder, `supabase/migrations`, or Edge Function source code. The base schema was created by the website / admin web portal.
- The `docs/` folder contains **add-on SQL scripts** for the mobile app only. They assume the base schema already exists.

**To create a brand-new Supabase project from nothing: REQUIRES MANUAL
CONFIGURATION.** You need the base schema (tables, enums, RLS policies,
triggers, RPC functions, storage buckets) and Edge Functions from the
website / admin portal repository, or a schema export from the existing
project made by the project owner. Apply that first, then the scripts in
[section 11](#11-database-migration-order).

### 6.2 Connect to the existing project

1. Ask the project owner to invite you to the Supabase project.
2. Open *Supabase Dashboard → Project Settings → API*.
3. Copy the **Project URL** and **anon / publishable key** into `.env` (see [section 5](#5-environment-configuration)).

### 6.3 Tables the app uses

The app reads or writes these tables (found in `lib/repositories/`). They must
exist in the database:

- **Patient data:** `patients`, `profiles`, `appointments`, `appointment_services`, `dental_records`, `tooth_records`, `treatment_notes`, `treatment_plans`, `patient_files`, `patient_messages`
- **Billing and wallet:** `billing_records`, `invoices`, `invoice_items`, `payment_receipts`, `receipt_items`, `wallet_transactions`, `wallet_topup_requests`, `visit_payment_requests`
- **Notifications:** `notifications`, `notification_state`, `notification_prefs`
- **Clinic reference data:** `clinics`, `clinic_settings`, `clinic_closures`, `procedures`, `specializations`, `members`, `doctor_schedules`, `doctor_schedule_exceptions`, `booking_categories`

The realtime script also refers to `billing`, `treatment_plan_items`,
`member_services`, and `booking_category_services`. It skips any table that
does not exist.

### 6.4 Enums

The SQL scripts in `docs/` rely on these existing enums (from the base schema):

- `appointment_status` — capitalised values, for example `'Pending'`, `'Confirmed'`, `'Cancelled'`.
- `weekday` — `'Mon'` … `'Sun'` (column `doctor_schedules.day_of_week`).
- `members.role` and `members.status` — enums; the scripts compare `role::text = 'doctor'` and `status::text = 'Active'`.
- `wallet_transactions.direction` — values `'in'` / `'out'`.

The scripts in this repository do **not** create these enums.

### 6.5 Functions / RPCs

**Created by scripts in this repository (`docs/`):**

| Function | Script | Used by the app for |
|----------|--------|---------------------|
| `claim_patient_chart()` | `realtime_data_sync_migration.sql` | Links a chart created by the clinic to the patient account with the same confirmed email. |
| `patient_doctor_roster()` | `realtime_data_sync_migration.sql` | Dentist list for booking. |
| `wallet_balance_of()` | `realtime_data_sync_migration.sql` | Internal helper. |
| `book_appointment_with_wallet()`, `pay_appointment_from_wallet()` | `realtime_data_sync_migration.sql` | Older wallet checkout path (kept for compatibility). |
| `notifications_sync_read_at()` (trigger) | `realtime_data_sync_migration.sql` | Keeps `notifications.read_at` and `is_read` in step. |
| `patient_doctor_hours()` | `doctor_hours_migration.sql` | Dentist working hours in the booking wizard. |
| `confirm_paid_booking()` (trigger `trg_confirm_paid_booking`) | `confirm_paid_bookings_migration.sql` | Optional safety net: confirms a paid booking. |

**Called by the app but NOT defined in this repository** (they come from the
website / admin portal backend — REQUIRES MANUAL CONFIGURATION if you build a
new project):

- `booking_catalogue`
- `available_slots_for_services`
- `book_appointment_v5` (wallet booking), `book_appointment_v6` (GCash/GrabPay booking)
- `cancel_my_appointment`, `reschedule_my_appointment`
- `wallet_balance`, `wallet_pay_bill`, `wallet_pay_visit_request`
- `notif_mark_read_ids`

Check they exist in *Supabase Dashboard → Database → Functions*.

### 6.6 Row Level Security (RLS)

- The app uses only the **anon key**. Every table it touches must have RLS enabled, with policies that let a signed-in patient read only their own rows (`lib/services/supabase_service.dart` and `lib/repositories/patient_api.dart` describe this design).
- The RLS policies come from the base schema. **The scripts in this repository do not change any RLS policy.**
- Do **not** run `docs/sync_migration.sql` or `docs/service_doctor_wallet_migration.sql`. They replace RLS policies that the admin portal depends on.

### 6.7 Authentication

Configure in *Supabase Dashboard → Authentication*:

1. **Providers → Email:** enabled. The app uses email + password (`signInWithPassword`, `signUp`).
2. **Confirm email:** enabled. After registering, the patient types a **6-digit code** from the email (`verifyOTP` with `OtpType.signup`; the screen expects 6 digits).
3. **Email Templates → Confirm signup:** the template must contain the code token `{{ .Token }}` so the email shows the 6-digit code. **REQUIRES MANUAL CONFIGURATION** — check the template in the dashboard.
4. **URL Configuration → Redirect URLs:** add exactly:
   ```
   mbdental://login-callback
   ```
   This is used for sign-up emails and password-reset links (`lib/services/auth_service.dart`). The scheme is registered in `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`. Without this entry, password-reset links fail.
5. **SMTP:** Supabase's built-in email sender has a low hourly limit. For real use, set a custom SMTP server in *Project Settings → Authentication → SMTP Settings*. **REQUIRES MANUAL CONFIGURATION** — SMTP host, port, user, and password come from the clinic's email provider. Never put them in this repository.
6. **Patient row on sign-up:** the app sends `full_name` and `phone` in user metadata. A database trigger in the base schema creates the matching patient row. **REQUIRES MANUAL CONFIGURATION** for a new project (trigger is not in this repository).

### 6.8 Storage buckets

Create in *Supabase Dashboard → Storage* if they do not exist:

| Bucket | Public? | Used for |
|--------|---------|----------|
| `patient-files` | **Private** | Patient documents. The app uploads files and opens them with signed URLs. |
| `avatars` | **Public** | Profile photos. The app uploads and reads them by public URL. |

Storage policies must let a signed-in patient upload/read only their own
objects. **REQUIRES MANUAL CONFIGURATION** — the policies are not in this
repository; copy them from the existing project.

### 6.9 Realtime

The app subscribes to table changes (`lib/services/realtime_sync_service.dart`).
A table only sends changes if it is in the `supabase_realtime` publication.

Run section 5 of `docs/realtime_data_sync_migration.sql` (the whole script is
safe to run). It adds every table the app shows to the publication and sets
`replica identity full`.

Check it worked (Supabase SQL Editor):

```sql
select tablename from pg_publication_tables
 where pubname = 'supabase_realtime' order by tablename;
```

If a table is missing, the app still works. It refreshes that data when the app
is reopened instead of instantly.

### 6.10 QR codes

- **Check-in QR:** drawn by the app from the appointment's confirmation code (`lib/widgets/check_in_qr.dart`). The code is created on the server by `book_appointment_v5` / `v6`. No extra setup.
- **Scan to pay:** the Wallet's camera scanner reads the clinic's Patient Wallet QR, which is a portal link with `vpr=<request id>` or `vpa=<appointment id>`. It needs the camera permission (already in `AndroidManifest.xml`) and data in `visit_payment_requests`.

### 6.11 Billing, wallet, and payments

- Wallet balance and bill payments use the RPCs in [6.5](#65-functions--rpcs).
- GCash / GrabPay cash-in and online payments use the Edge Functions in [section 10](#10-supabase-edge-functions) and the table `wallet_topup_requests`.
- The app never credits the wallet itself. Only the server (PayMongo webhook) does.

### 6.12 Notifications

- Notifications are **in-app only**, read from the `notifications` table and updated by Realtime. The app does **not** use Firebase Cloud Messaging push notifications.
- Optional: `docs/notifications_schema_notes.sql` adds a `type` column so muted notification categories are respected.

---

## 7. Website Setup

**The website is not in this repository.** There is no `package.json`,
`config.js`, `index.html` for a website, `firebase.json`, or `.firebaserc` here.
(`web/index.html` is only Flutter's own web build template.)

**REQUIRES MANUAL CONFIGURATION:**

1. Ask the project owner for the website / admin web portal repository.
2. Follow that repository's own setup instructions.
3. The website must point to the **same Supabase project** as this app (same Project URL and anon key), so both read the same data.

Do **not** run `npm install` in this folder. It will fail because there is no
`package.json`.

---

## 8. Flutter Mobile App Setup

### 8.1 Install Flutter

1. Download the Flutter SDK for Windows (stable channel) from https://docs.flutter.dev/get-started/install/windows.
2. Extract it to a path **without spaces**, for example `C:\src\flutter`. Do not put it in `C:\Program Files`.
3. Add `C:\src\flutter\bin` to your user `Path`:
   *Start → "Edit environment variables for your account" → Path → Edit → New → `C:\src\flutter\bin`*.
4. Close and reopen PowerShell, then check:
   ```powershell
   flutter --version
   ```
   You need **Dart 3.12.2 or newer**. If your version is older:
   ```powershell
   flutter channel stable
   flutter upgrade
   ```

### 8.2 Install Android Studio and the Android SDK

1. Install Android Studio from https://developer.android.com/studio.
2. Open Android Studio → *More Actions → SDK Manager*.
3. On **SDK Platforms**, install a recent Android platform.
4. On **SDK Tools**, install:
   - Android SDK Build-Tools
   - Android SDK Command-line Tools (latest)
   - Android SDK Platform-Tools
   - Android Emulator
5. In Android Studio → *Plugins*, install the **Flutter** plugin (it also installs **Dart**). Restart Android Studio.

### 8.3 Run `flutter doctor`

From any folder in PowerShell:

```powershell
flutter doctor
flutter doctor --android-licenses
```

Accept all licenses (type `y`). Run `flutter doctor` again. The
**Flutter** and **Android toolchain** lines must show a green check. Problems
with Visual Studio, Chrome, or Xcode do not block Android development.

If Flutter cannot find the Android SDK:

```powershell
flutter config --android-sdk "C:\Users\<YOUR_WINDOWS_USER>\AppData\Local\Android\Sdk"
```

### 8.4 Install project dependencies

Run from the project folder:

```powershell
cd D:\Development\mb_dental_app
flutter pub get
```

This downloads packages (exact versions are in `pubspec.lock`) and creates
`android\local.properties`.

### 8.5 Configure Supabase

Create `.env` in the project root as described in
[section 5](#5-environment-configuration). Without it, the build fails because
`pubspec.yaml` lists `.env` as an asset.

### 8.6 Check Firebase config

Make sure `android\app\google-services.json` exists. It is in Git, so a clone
already has it. See [section 9](#9-firebase).

### 8.7 Open the project in an IDE

**Android Studio (recommended):**
1. *File → Open* → select `D:\Development\mb_dental_app` (the folder with `pubspec.yaml`, **not** the `android` subfolder).
2. Wait for indexing to finish. If asked, click **Pub get**.

**VS Code (optional):**
1. Install the **Flutter** extension.
2. *File → Open Folder* → `D:\Development\mb_dental_app`.

### 8.8 Start an emulator

1. Android Studio → *Device Manager* → *Create Virtual Device* → pick a phone → pick a system image → *Finish*.
2. Click the **Play** button next to the device.

Or from PowerShell:

```powershell
flutter emulators
flutter emulators --launch <EMULATOR_ID>
```

Before starting a new emulator, check if one is already running with
`flutter devices`. Do not start two emulators or two `flutter run` sessions for
the same device.

### 8.9 Connect a physical Android phone

1. On the phone: *Settings → About phone* → tap **Build number** 7 times to enable Developer options.
2. *Settings → Developer options* → turn on **USB debugging**.
3. Connect the phone with a USB data cable. Accept the "Allow USB debugging?" prompt on the phone.
4. Check:
   ```powershell
   adb devices
   flutter devices
   ```
   The phone must be listed as `device` (not `unauthorized`).

### 8.10 Run the app

Run from the project folder:

```powershell
cd D:\Development\mb_dental_app
flutter devices
flutter run
```

If several devices are connected, choose one:

```powershell
flutter run -d <DEVICE_ID>
```

In Android Studio you can instead pick the device in the toolbar and press
**Run** (green triangle). While `flutter run` is active, press `r` for hot
reload, `R` for hot restart, `q` to quit.

### 8.11 Run the tests (optional)

```powershell
cd D:\Development\mb_dental_app
flutter test
```

### 8.12 Build an APK

Run from the project folder:

```powershell
cd D:\Development\mb_dental_app
flutter build apk --release
```

Output file:

```
D:\Development\mb_dental_app\build\app\outputs\flutter-apk\app-release.apk
```

> **Signing note:** `android/app/build.gradle.kts` signs the release build with
> the **debug key** (`signingConfig = signingConfigs.getByName("debug")`). This
> is fine for testing and sideloading. It is **not** acceptable for the Google
> Play Store. Publishing to Play Store **REQUIRES MANUAL CONFIGURATION**: create
> a release keystore, store it outside Git, and update the signing config.
> Each computer has its own debug key, so an APK built on a new computer cannot
> update an APK built on the old one without uninstalling first.

### 8.13 Install the APK on another Android phone

**Option A — with USB and adb** (from the project folder):

```powershell
adb devices
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

**Option B — without a computer:**
1. Copy `app-release.apk` to the phone (USB, Google Drive, messaging app).
2. Open it on the phone. Allow "Install unknown apps" for the app you opened it with.
3. Tap **Install**.

### 8.14 Regenerate icons and splash (only if you change them)

```powershell
cd D:\Development\mb_dental_app
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

---

## 9. Firebase

### What is used

- `lib/main.dart` calls `Firebase.initializeApp()` before Supabase starts. If Firebase cannot initialize, the app shows **"The app could not start"**.
- Android reads its Firebase settings from `android/app/google-services.json` through the Google Services Gradle plugin (`android/settings.gradle.kts`, `android/app/build.gradle.kts`).
- The file contains client entries for the package names `com.example.mb_dental_app` (the current `applicationId`) and `com.example.mbdental`.
- No Firebase feature (Firestore, Messaging, Hosting) is used by the app code beyond initialization.

### Firebase Hosting

**Firebase Hosting is not used in this repository.** There is no
`firebase.json` and no `.firebaserc`. No Firebase CLI or `firebase deploy` step
is needed for the mobile app.

If the **website** is hosted on Firebase, the hosting setup is in the website
repository — **REQUIRES MANUAL CONFIGURATION**. The usual commands there would
be `npm install -g firebase-tools`, `firebase login`, `firebase use <project>`,
and `firebase deploy`, but confirm them against that repository's
`firebase.json` and `.firebaserc`.

### Using a new Firebase project (only if needed)

1. Go to https://console.firebase.google.com → create or open a project.
2. *Add app → Android*. Package name: `com.example.mb_dental_app` (must match `applicationId` in `android/app/build.gradle.kts`).
3. Download `google-services.json`.
4. Replace `android\app\google-services.json` with it.
5. Run `flutter clean` then `flutter run`.

---

## 10. Supabase Edge Functions

**The Edge Function source code is not in this repository.** There is no
`supabase/functions` folder. The app only **calls** these functions:

| Function | Called from | What it does (from the app code) |
|----------|-------------|-----------------------------------|
| `create-topup-source` | `lib/repositories/wallet_topup_api.dart` | Creates a PayMongo checkout (GCash or GrabPay) and returns `checkout_url` and a request id. Used for wallet cash-in, paying a bill, paying a visit request, and paying a booking down payment. The amount for bills/visits is priced on the server. |
| `reconcile-topup` | `lib/repositories/wallet_topup_api.dart` | Asks the server to check PayMongo directly for a request id, in case the webhook is late. |
| `paymongo-webhook` | Not called by the app. Called by **PayMongo**. | Marks the payment as paid in `wallet_topup_requests` and credits the wallet for a cash-in. |

### JWT verification

- `create-topup-source`: the app sends the patient's access token in the `Authorization` header. It is a user-authenticated function. Deploy **with** JWT verification (default).
- `reconcile-topup`: called through the Supabase client, which sends the signed-in user's token. Deploy **with** JWT verification (default), unless the function's own code says otherwise.
- `paymongo-webhook`: PayMongo calls it and cannot send a Supabase JWT. It must be deployed with **`--no-verify-jwt`** and must verify the PayMongo webhook signature itself. Confirm this in the function's source code.

### Required secrets

**REQUIRES MANUAL CONFIGURATION.** The exact secret names are in the Edge
Function source code (website/backend repository). Based on what the functions
do, expect at least:

- A PayMongo **secret** key.
- A PayMongo **webhook signing secret**.
- Supabase's `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are provided to Edge Functions automatically by Supabase.

Set secrets with the Supabase CLI (from the repository that contains the
`supabase/functions` folder):

```powershell
supabase secrets set NAME_FROM_FUNCTION_CODE=YOUR_VALUE --project-ref YOUR_PROJECT_REF
```

### Deploy (from the repository that contains the functions)

```powershell
npm install -g supabase        # or: scoop install supabase
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy create-topup-source
supabase functions deploy reconcile-topup
supabase functions deploy paymongo-webhook --no-verify-jwt
```

Then in the PayMongo dashboard, set the webhook URL to:

```
https://YOUR_PROJECT_REF.supabase.co/functions/v1/paymongo-webhook
```

To check what is deployed now: *Supabase Dashboard → Edge Functions*.

---

## 11. Database Migration Order

All SQL files are in `docs/`. Run them in the **Supabase Dashboard → SQL
Editor** (paste the file contents and click **Run**). They are idempotent: you
can run them again safely, except where noted.

**Step 0 — Base schema (prerequisite, not in this repository).**
Tables, enums, RLS policies, storage buckets and policies, sign-up trigger, and
the RPCs listed in [6.5](#65-functions--rpcs) (`booking_catalogue`,
`book_appointment_v5`/`v6`, etc.). On the existing production project these
already exist. For a new project: **REQUIRES MANUAL CONFIGURATION** (website /
admin portal repository or a schema dump from the project owner).

Then, in this order:

1. **`docs/realtime_data_sync_migration.sql`** — **required.**
   Adds `notifications.read_at` + sync trigger, `claim_patient_chart()`,
   `patient_doctor_roster()`, wallet helper functions, and adds all app tables
   to Realtime.
2. **`docs/doctor_hours_migration.sql`** — **required.**
   Adds `patient_doctor_hours()` for the booking wizard.
3. **`docs/confirm_paid_bookings_migration.sql`** — *optional* safety net.
   Adds the `trg_confirm_paid_booking` trigger. The data fix-up at the bottom
   is commented out. Do **not** run that fix-up unless you have previewed it,
   because it changes data.
4. **`docs/notifications_schema_notes.sql`** — *optional.*
   Run **only** the `alter table public.notifications add column if not exists type text;`
   statement. Skip the last line (`alter publication supabase_realtime add table public.notification_state;`)
   if step 1 already ran: it errors when the table is already published.
5. **`docs/service_categories.sql`** — *optional.*
   Adds `procedures.patient_category`. The app does **not** read this column
   yet; it groups services in code (`lib/data/service_categories.dart`).

**Do NOT run:**

- `docs/sync_migration.sql` — superseded, replaces RLS policies the admin portal needs.
- `docs/service_doctor_wallet_migration.sql` — superseded, does not match the live schema.

---

## 12. How to Run the Complete System

After setup is finished once, this is the daily start procedure.

**Website**
```powershell
# Not in this repository. Start it from the website repository.
# REQUIRES MANUAL CONFIGURATION — see that repository's setup guide.
```

**Flutter App**
```powershell
cd D:\Development\mb_dental_app
git pull
flutter pub get
flutter devices
flutter run
```

**Supabase**
```powershell
# Nothing to start locally. The app uses the hosted Supabase project in .env.
# Only when the database changes: run new docs\*.sql files in the SQL Editor
# (see section 11).
```

**Firebase Deployment**
```powershell
# Not applicable to this repository (no firebase.json / .firebaserc).
# The Flutter app only needs android\app\google-services.json.
```

**Release APK (when needed)**
```powershell
cd D:\Development\mb_dental_app
flutter build apk --release
```

---

## 13. Setup Verification

Use a test patient account. Tick each item.

- [ ] `flutter doctor` shows green checks for Flutter and Android toolchain.
- [ ] `flutter pub get` finishes with no errors.
- [ ] `flutter test` passes.
- [ ] The app launches and shows the animated splash, then the Login screen (not "The app could not start").
- [ ] **Registration:** a new account receives an email with a 6-digit code, and the code is accepted.
- [ ] **Login:** the test patient can sign in, and the session survives closing and reopening the app.
- [ ] **Forgot password:** the reset email arrives, its link opens the app, and a new password can be set.
- [ ] **Patient information loads:** Profile, Dental Records (tooth chart), Treatment Notes, and documents appear with no error banner.
- [ ] **Profile photo** upload works (`avatars` bucket).
- [ ] **Documents** open (`patient-files` bucket, signed URLs).
- [ ] **Appointment booking:** dentists, services, and free time slots load; a booking with Wallet succeeds and shows a confirmation.
- [ ] **Reschedule and cancel** an appointment work.
- [ ] **Check-in QR** appears on a confirmed appointment.
- [ ] **Wallet:** balance and transaction history load; a receipt PDF can be opened or shared.
- [ ] **Cash In** (GCash/GrabPay) opens the PayMongo checkout, and after paying the wallet balance updates (needs Edge Functions + PayMongo).
- [ ] **Scan to Pay:** the camera opens and a clinic Patient Wallet QR opens the matching bill.
- [ ] **Realtime:** change a record from the admin portal (for example, an appointment status). The app updates without a manual refresh.
- [ ] **Notifications** appear in the app, and marking one as read stays read after reopening.
- [ ] **Messages** from the clinic appear in the chat screen.
- [ ] **Release APK** installs and launches on a second phone.

---

## 14. Common Errors and Troubleshooting

### `flutter` is not recognized
- **Problem:** `flutter : The term 'flutter' is not recognized ...`
- **Possible Cause:** `flutter\bin` is not in `Path`, or PowerShell was open before you changed `Path`.
- **Solution:** Add `C:\src\flutter\bin` (your path) to the user `Path`, then close and reopen PowerShell and Android Studio.

### Dart SDK version error during `flutter pub get`
- **Problem:** `The current Dart SDK version is X. Because mb_dental_app requires SDK version ^3.12.2, version solving failed.`
- **Possible Cause:** Flutter is older than 3.44.
- **Solution:** `flutter channel stable` then `flutter upgrade`.

### Other Flutter dependency problems
- **Problem:** `pub get` fails, or strange build errors after pulling changes.
- **Possible Cause:** Stale cache or build files.
- **Solution:** From the project folder:
  ```powershell
  flutter clean
  flutter pub get
  ```
  If it still fails: `flutter pub cache repair`.

### Build fails: unable to find asset `.env`
- **Problem:** `No file or variants found for asset: .env.`
- **Possible Cause:** `.env` is missing. It is not stored in Git.
- **Solution:** Create it from `.env.example` ([section 5](#5-environment-configuration)).

### App shows "The app could not start"
- **Problem:** Error screen right after the splash.
- **Possible Cause:** `.env` values are empty, wrong, or not `https://`; `google-services.json` is missing or wrong; or no internet during startup.
- **Solution:** Check both `.env` variables. Check `android\app\google-services.json` exists and contains the package name `com.example.mb_dental_app`. Check internet. Then fully stop the app and run `flutter run` again (hot reload does not reload `.env`).

### `File google-services.json is missing`
- **Problem:** Gradle error from the Google Services plugin.
- **Possible Cause:** The file was deleted or not copied.
- **Solution:** Restore it from Git (`git checkout -- android/app/google-services.json`) or download it from the Firebase console ([section 9](#9-firebase)).

### Android SDK not detected
- **Problem:** `flutter doctor` says `Unable to locate Android SDK`.
- **Possible Cause:** SDK not installed, or installed in a non-default folder.
- **Solution:** Install it via Android Studio SDK Manager, then `flutter config --android-sdk "<path to Sdk>"`.

### Android licenses not accepted
- **Problem:** `Android license status unknown` or `cmdline-tools component is missing`.
- **Solution:** Install *Android SDK Command-line Tools* in SDK Manager, then run `flutter doctor --android-licenses`.

### `adb` is not recognized
- **Problem:** `adb : The term 'adb' is not recognized ...`
- **Possible Cause:** Platform-Tools folder not in `Path`.
- **Solution:** Add `C:\Users\<YOUR_WINDOWS_USER>\AppData\Local\Android\Sdk\platform-tools` to `Path` and reopen PowerShell. `flutter devices` works without this.

### Phone shows as `unauthorized` or not listed
- **Solution:** Unplug and replug. Accept the USB debugging prompt on the phone. Use a data cable. Run `adb kill-server` then `adb devices` only if no other tool (Android Studio, a running app) is using adb.

### `flutter.sdk not set in local.properties`
- **Problem:** Gradle error from `android/settings.gradle.kts`.
- **Possible Cause:** `android\local.properties` is missing or points to the old computer.
- **Solution:** Delete `android\local.properties` and run `flutter pub get` from the project folder.

### Gradle out of memory or "Could not reserve enough space"
- **Problem:** Gradle daemon crashes on a computer with little RAM.
- **Possible Cause:** `android/gradle.properties` asks for `-Xmx8G`.
- **Solution:** Close other programs. If the computer has 8 GB RAM or less, lower the value locally (for example `-Xmx4G`), and do not commit that change unless the team agrees.

### Kotlin "different roots" error
- **Problem:** `this and base files have different roots` during `compileDebugKotlin`.
- **Possible Cause:** Project and Pub cache on different drives (for example `D:` and `C:`).
- **Solution:** Already handled: `android/gradle.properties` disables Kotlin incremental compilation. Keep those lines. If it still happens, run `flutter clean`.

### Java version error
- **Problem:** `Android Gradle plugin requires Java 17` or similar.
- **Solution:** Use Android Studio's bundled JDK, or install JDK 17+, then `flutter config --jdk-dir "<path to JDK>"`.

### Supabase connection or DNS errors
- **Problem:** `Failed host lookup`, `SocketException`, or "check your connection" messages.
- **Possible Cause:** No internet, emulator has no network, wrong URL in `.env`, or the Supabase project is **paused** (free-tier projects pause after inactivity).
- **Solution:** Open the URL in a browser. Restart the emulator (*Device Manager → Cold Boot Now*). Check the URL in `.env`. In the Supabase dashboard, **Restore** a paused project.

### Missing environment variables
- **Problem:** App fails at start; `Supabase configuration is missing`.
- **Possible Cause:** Variable names misspelled in `.env`.
- **Solution:** Use exactly `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. No quotes or spaces around `=`.

### Database / RLS permission errors
- **Problem:** Empty lists, or errors like `permission denied for table ...`, `new row violates row-level security policy`, or `42501`.
- **Possible Cause:** RLS policies are missing on a new project, the patient chart is not linked to the account, or the user is not signed in.
- **Solution:** Make sure the base schema policies exist (REQUIRES MANUAL CONFIGURATION for new projects). Run `docs/realtime_data_sync_migration.sql` so `claim_patient_chart()` exists. Use the verification queries in section 6 of that file.

### `function ... does not exist` (`42883` / `PGRST202`)
- **Problem:** Booking, wallet, or roster fails with a missing-function error.
- **Possible Cause:** A required RPC is not in the database.
- **Solution:** Run the scripts in [section 11](#11-database-migration-order). RPCs not in this repository (`book_appointment_v5`, `booking_catalogue`, ...) must come from the website backend.

### `column ... does not exist` (`42703`)
- **Problem:** A section of the app shows an error, other sections load.
- **Possible Cause:** The database is missing a column the app expects.
- **Solution:** Run `docs/realtime_data_sync_migration.sql` (adds `notifications.read_at`). The app already tolerates a missing `notifications.type`.

### Realtime not updating
- **Problem:** Changes appear only after reopening the app. Log says `Realtime (...) unavailable`.
- **Possible Cause:** The table is not in the `supabase_realtime` publication.
- **Solution:** Run section 5 of `docs/realtime_data_sync_migration.sql`.

### Email / OTP not delivered
- **Problem:** No verification or reset email.
- **Possible Cause:** Supabase's default email rate limit reached, email in spam, custom SMTP misconfigured, or **Confirm email** disabled.
- **Solution:** Check spam. In *Authentication → Logs*, look for send errors. Set up custom SMTP. Check the Confirm signup template contains `{{ .Token }}` for the 6-digit code.

### Password reset link does not open the app
- **Possible Cause:** `mbdental://login-callback` is not in Supabase Redirect URLs, or the email was opened on a device without the app.
- **Solution:** Add it under *Authentication → URL Configuration → Redirect URLs*. Open the email on the phone with the app installed.

### Cash In / online payment fails
- **Problem:** "The checkout could not be opened" or payment stays "confirming".
- **Possible Cause:** Edge Functions not deployed, PayMongo secrets missing, webhook URL not set, or `paymongo-webhook` deployed with JWT verification on.
- **Solution:** See [section 10](#10-supabase-edge-functions). Check *Supabase Dashboard → Edge Functions → Logs*.

### Supabase CLI not recognized
- **Problem:** `supabase : The term 'supabase' is not recognized`.
- **Solution:** Install it (`npm install -g supabase` or `scoop install supabase`), then reopen PowerShell. It is only needed for Edge Function work in the backend repository.

### Edge Function deployment errors
- **Problem:** `Cannot find project ref` or `Entrypoint path does not exist`.
- **Possible Cause:** Not linked, or running the command outside the repository that contains `supabase/functions`.
- **Solution:** `supabase login`, `supabase link --project-ref YOUR_PROJECT_REF`, and run from the backend repository root. This repository has no functions to deploy.

### `npm` errors / missing `package.json`
- **Problem:** `npm ERR! enoent Could not read package.json`.
- **Possible Cause:** Running npm in this repository.
- **Solution:** This repository has no Node.js project. Run npm only in the website repository.

### Firebase deployment errors
- **Problem:** `firebase deploy` fails with `Not in a Firebase app directory`.
- **Possible Cause:** No `firebase.json` in this repository.
- **Solution:** Firebase Hosting is not part of this repository. Deploy from the website repository if it uses Firebase Hosting.

### APK install fails: "App not installed" / signature conflict
- **Possible Cause:** An APK signed with a different debug key (another computer) is already installed.
- **Solution:** Uninstall the old app from the phone, then install again.

### Camera scanner shows black screen
- **Possible Cause:** Camera permission denied, or emulator without a camera.
- **Solution:** Allow camera in *Settings → Apps → M&B Dental → Permissions*. Test on a real phone.

---

## 15. Project Folder Structure

```
mb_dental_app/
├── .env                  # Your Supabase URL + anon key (NOT in Git, you create it)
├── .env.example          # Template for .env
├── .gitignore
├── AGENTS.md             # Rules for AI coding agents (Windows terminal usage)
├── SETUP.md              # This guide
├── pubspec.yaml          # Flutter dependencies, assets, icon/splash config
├── pubspec.lock          # Exact package versions
├── analysis_options.yaml # Lint rules
├── android/
│   ├── app/
│   │   ├── build.gradle.kts         # applicationId, signing, Firebase plugin
│   │   ├── google-services.json     # Firebase Android config
│   │   └── src/main/AndroidManifest.xml  # Permissions, mbdental:// deep link
│   ├── settings.gradle.kts          # Plugin versions (AGP, Kotlin, Google Services)
│   ├── gradle.properties            # Gradle memory + Kotlin settings
│   └── local.properties             # Generated per computer (NOT in Git)
├── ios/                  # iOS project (Info.plist has camera + mbdental scheme)
├── web/, windows/, linux/, macos/   # Flutter platform scaffolding
├── assets/
│   ├── images/           # Logo, app icons, tooth map SVG
│   ├── animations/       # Lottie splash animation
│   ├── wallet/           # GCash / GrabPay logos
│   ├── files/            # Terms and Privacy Policy text shown when booking
│   └── reference_ui/     # Design reference images (not bundled)
├── docs/                 # Supabase SQL add-on scripts (see section 11)
├── lib/
│   ├── main.dart         # Starts Firebase + Supabase, then the app
│   ├── app/              # App widget, routes, theme, auth gate, settings
│   ├── data/             # Static catalog data (service categories)
│   ├── models/           # Data classes (appointment, patient, payment, ...)
│   ├── repositories/     # All Supabase queries, RPCs, Edge Function calls
│   ├── screens/          # UI: auth, dashboard, appointments, records, wallet, chat, profile
│   ├── services/         # Supabase client, auth, realtime, network, PDF, notifications
│   └── widgets/          # Shared UI pieces (check-in QR, calendar, skeletons, ...)
├── test/                 # Flutter unit/widget tests (run with flutter test)
└── tool/
    └── generate_tooth_map_svg.dart  # Regenerates assets/images/tooth_map.svg
```

Most important files to know:

- `lib/services/supabase_service.dart` — reads `.env` and connects to Supabase.
- `lib/services/auth_service.dart` — sign up, OTP, sign in, password reset, redirect URL.
- `lib/repositories/patient_api.dart` — patient data, bookings, wallet, storage buckets.
- `lib/repositories/clinic_api.dart` — clinic catalog, dentists, schedules, time slots.
- `lib/repositories/wallet_topup_api.dart` — PayMongo checkout through Edge Functions.
- `lib/services/realtime_sync_service.dart` — realtime subscriptions.

---

## 16. Moving the System to Another Computer

### Files stored in Git (you get them by cloning)

- All source code: `lib/`, `test/`, `tool/`, `assets/`, `docs/`
- `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`
- Platform folders: `android/`, `ios/`, `web/`, `windows/`, `linux/`, `macos/`
- `android/app/google-services.json`
- `.env.example`, `.gitignore`, `README.md`, `AGENTS.md`, `SETUP.md`

### Files NOT in Git (you must create or copy them)

| File | What to do |
|------|------------|
| `.env` | Create from `.env.example`. Get values from Supabase dashboard or the project owner through a secure channel (not email/chat in plain text). |
| `android/local.properties` | Do not copy. `flutter pub get` creates it. |
| `build/`, `.dart_tool/`, `.flutter-plugins-dependencies` | Do not copy. Generated. |
| `.idea/`, `*.iml` | Do not copy. Android Studio recreates them. |
| Release keystore (`*.jks` / `*.keystore`) + `key.properties` | Only if one is created later. Copy securely, never via Git. Currently none exists (release uses the debug key). |

### Environment variables

Only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`, in `.env`. No Windows
system environment variables are needed except `Path` entries for Flutter (and
optionally `adb`).

### Supabase configuration

Lives in the cloud. Nothing to move. Moving to a new computer only requires
the `.env` values and your Supabase dashboard login.

### Firebase configuration

`google-services.json` is in Git. Nothing to move. Dashboard access is needed
only to change it.

### Local SDK / tool installations (install fresh on the new computer)

1. Git
2. Flutter SDK 3.44.x stable (add to `Path`)
3. Android Studio + Android SDK, Platform-Tools, Command-line Tools, Emulator
4. Flutter and Dart plugins in Android Studio
5. Accept Android licenses
6. Optional: VS Code, Supabase CLI

### Secrets

None of the secrets live in this repository. The PayMongo keys, webhook
secret, SMTP password, and service-role key stay in Supabase (dashboard / Edge
Function secrets) and in the project owner's password manager.

### Step-by-step move

1. Install the tools above.
2. `git clone https://github.com/Budjang02/mb_dental_app.git` (or copy the folder and clean it — [section 4](#4-clone-or-transfer-the-project)).
3. Create `.env`.
4. `flutter pub get`.
5. `flutter doctor` until Android is green.
6. `flutter run`.
7. Go through [section 13](#13-setup-verification).

---

## 17. Setting Up on Another Device

A new developer can run the app without anything from the original
developer's computer:

1. Get **GitHub access** to the repository.
2. Get the **Supabase Project URL and anon key** from the Supabase dashboard (requires a project invite) or from the project owner.
3. Install the software in [section 2](#2-system-requirements).
4. Clone ([section 4](#4-clone-or-transfer-the-project)).
5. Create `.env` ([section 5](#5-environment-configuration)).
6. Follow [section 8](#8-flutter-mobile-app-setup).
7. Use a **test patient account**. Create one through the app's Register screen, or ask the clinic admin to create a chart in the admin portal using the same email you register with (the app links them with `claim_patient_chart()`).

The new developer does **not** need:
- the original `local.properties`, `build` folder, or IDE settings;
- the service-role key (the app never uses it);
- Firebase CLI or Node.js (for this repository).

They **do** need the website / backend repository only if they will change
Edge Functions, base schema, or the website.

---

## 18. Security Notes

**Never commit these to Git:**

- `.env` (or any `.env.*` other than `.env.example`)
- Supabase **service-role** key
- Supabase database password / connection string
- Passwords of any kind
- **SMTP** credentials
- **PayMongo secret key** and webhook secret, or any API secret
- Firebase **private** credentials (service-account JSON / admin SDK keys). Note: `google-services.json` is a client config file, not a service account, and is normally safe to keep in Git.
- Android **signing keys**: `*.jks`, `*.keystore`, `key.properties`

### `.gitignore` review

Already ignored: `.env`, `.env.*` (except `.env.example`), `build/`,
`.dart_tool/`, `.idea/`, `*.iml`, Android build output folders.

**Recommended additions** (not yet in `.gitignore`):

```gitignore
# Android signing
*.jks
*.keystore
key.properties
/android/local.properties

# Visual Studio cache
.vs/

# Android Gradle output
/android/build/
/android/.gradle/

# Firebase / Google service-account keys
*service-account*.json
*-firebase-adminsdk-*.json

# Supabase CLI local files (if a supabase/ folder is added later)
supabase/.temp/
supabase/.branches/
```

**Files already committed that should not be:** `.vs/` (Visual Studio cache,
including `slnx.sqlite`) and `android/build/reports/problems/problems-report.html`.
They contain no secrets but are machine-specific. To stop tracking them
(after adding the lines above):

```powershell
cd D:\Development\mb_dental_app
git rm -r --cached .vs android/build
git commit -m "Stop tracking IDE cache and build output"
```

**Other notes:**

- The anon key in `.env` is bundled into the APK and can be read by anyone. Security depends fully on **RLS policies** in Supabase. Never disable RLS on a table the app reads.
- If a secret is ever committed, **rotate it** in its dashboard (Supabase, PayMongo, SMTP). Deleting the commit is not enough.
- Release builds are currently signed with the debug key. Create a real keystore before publishing, and keep it outside Git.

---

## 19. Quick Setup Checklist

- [ ] Install Git
- [ ] Install Flutter 3.44.x stable and add it to `Path`
- [ ] Install Android Studio, Android SDK, Platform-Tools, Command-line Tools, Emulator
- [ ] Install Flutter + Dart plugins in Android Studio
- [ ] Run `flutter doctor` and `flutter doctor --android-licenses`
- [ ] Clone the repository (or copy and clean the folder)
- [ ] Create `.env` with `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`
- [ ] Confirm `android/app/google-services.json` exists
- [ ] Run `flutter pub get`
- [ ] Get Supabase project access
- [ ] Confirm base schema, RLS, buckets (`patient-files`, `avatars`), and website RPCs exist
- [ ] Run `docs/realtime_data_sync_migration.sql`
- [ ] Run `docs/doctor_hours_migration.sql`
- [ ] (Optional) Run `docs/confirm_paid_bookings_migration.sql`
- [ ] Add `mbdental://login-callback` to Supabase Auth Redirect URLs
- [ ] Check email confirmation template and SMTP
- [ ] Confirm Edge Functions `create-topup-source`, `reconcile-topup`, `paymongo-webhook` are deployed (from the backend repository)
- [ ] Start an emulator or connect a phone
- [ ] Run `flutter run`
- [ ] Test registration, OTP, and login
- [ ] Test patient records loading
- [ ] Test appointment booking, reschedule, and cancel
- [ ] Test check-in QR and Scan to Pay
- [ ] Test wallet and Cash In
- [ ] Test realtime updates and notifications
- [ ] Build and install a release APK
