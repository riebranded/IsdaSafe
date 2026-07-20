# Auth Setup Guide

This app uses **Supabase Auth** as the single source of truth for identity —
email/password and Google sign-in both end in a Supabase session. Phone-number
OTP is the one exception: it goes through **Semaphore** (a Philippines SMS
API) instead of Supabase's own Phone provider (see Part 2 for why), with two
Supabase Edge Functions doing all the work — the Flutter app never talks to
Semaphore directly, and Semaphore never issues a session of its own.

Your Supabase project ref is `vemaphehzjnvspxmweeb` (from `.env`'s `SUPABASE_URL`).
Replace it below if you ever point the app at a different project.

---

## Part 1 — Google Sign-In (Google Cloud Console + Supabase)

**Note:** this app does not use Firebase. You do **not** need `google-services.json`
or `GoogleService-Info.plist` anywhere — Supabase validates a raw Google OAuth ID
token directly.

### 1. Create/select a Google Cloud project
Go to [console.cloud.google.com](https://console.cloud.google.com) → create a new
project (e.g. "IsdaSafe") or select an existing one.

### 2. Configure the OAuth consent screen
**APIs & Services → OAuth consent screen**
- User type: **External**
- App name: "IsdaSafe"
- Support email: your email
- Scopes: leave the default `email`, `profile`, `openid` scopes — nothing extra is needed.

### 3. Create a Web OAuth client (used to verify tokens server-side)
**APIs & Services → Credentials → Create Credentials → OAuth client ID → Web application**
- Name: "IsdaSafe Web (Supabase)"
- Authorized redirect URIs: add
  ```
  https://vemaphehzjnvspxmweeb.supabase.co/auth/v1/callback
  ```
- Save. Copy the **Client ID** and **Client Secret** — this is the "Web client."

### 4. Create an Android OAuth client
**Credentials → Create Credentials → OAuth client ID → Android**
- Package name: `com.isdasafe.app`
- SHA-1 certificate fingerprint — get it from the debug keystore:
  ```
  cd android
  ./gradlew signingReport
  ```
  or directly:
  ```
  keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android
  ```
- Save. (Before a Play Store release, register a **second** Android client using
  your release keystore's SHA-1.)

### 5. Create an iOS OAuth client
**Credentials → Create Credentials → OAuth client ID → iOS**
- Bundle ID: `com.isdasafe.app`
- Save. Note the **reversed client ID** shown on the client's details page —
  it looks like `com.googleusercontent.apps.XXXXXXXXXXXX`.

### 6. Enable Google in Supabase
**Supabase Dashboard → Authentication → Providers → Google**
- Enable the provider.
- Paste the **Web** client's Client ID + Client Secret from step 3.
- Save.

### 7. Fill in `.env`
Add the values from steps 3 and 5 to `.env` (already scaffolded with empty values):
```
GOOGLE_WEB_CLIENT_ID=<web client id>.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=<ios client id>.apps.googleusercontent.com
```

### 8. Wire the iOS URL scheme
`ios/Runner/Info.plist` already has a `CFBundleURLTypes` entry with a placeholder.
Replace `REPLACE_WITH_REVERSED_IOS_CLIENT_ID` with the reversed client ID from step 5:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.XXXXXXXXXXXX</string>
    </array>
  </dict>
</array>
```

Android needs no extra manifest changes — the package name + SHA-1 registered in
step 4 is what Google validates against.

---

## Part 2 — Phone OTP (Semaphore + two Supabase Edge Functions)

Supabase's built-in Phone provider only supports Twilio, Twilio Verify,
MessageBird, Vonage, and TextLocal — no PH-focused SMS API is available
there. This app uses [Semaphore](https://semaphore.co) (an SMS API built for
the Philippines) instead: the Flutter app never talks to Semaphore or holds
any SMS-provider SDK/session — it only ever calls two Supabase Edge
Functions. Semaphore itself has **no rate limiting and no code-verification
step** of its own (it just sends an SMS and hands the generated code back in
the response), so both are implemented in the Edge Functions:

- **`send-semaphore-otp`** — resolves the caller's Supabase session, checks
  per-user and per-phone rate limits (60s cooldown, max 3 sends/10min, max
  8 sends/24h — tracked in `public.otp_send_log`), calls Semaphore, hashes
  the returned code, and stores it in `public.phone_otps` with a 5-minute
  expiry.
- **`verify-semaphore-otp`** — checks the submitted code's hash against
  `public.phone_otps`, locking out after 5 wrong attempts, then marks the
  Supabase user's phone confirmed via the admin API.

Both tables and functions are already created against this project (ref
`vemaphehzjnvspxmweeb`) — what's left is the Semaphore account itself and its
two secrets.

### 1. Create a Semaphore account
Go to [semaphore.co](https://semaphore.co) → sign up. New accounts start with
some free/trial credits, but sending a real OTP always consumes credits —
top up before testing if the balance is 0.

### 2. Get your API key
**Semaphore Dashboard → Account → API Key** (exact label may vary) — copy it.

### 3. Check your Sender Name
**Semaphore Dashboard → Sender Names** — a default sender name is usable
immediately; registering a custom one (e.g. "ISDASAFE") requires Semaphore's
approval, so check the dashboard for the current turnaround time if you want
one. Either way, note the sender name you intend to use for step 4 — or skip
setting `SEMAPHORE_SENDER_NAME` entirely to fall back to the account's
default.

### 4. Set the Supabase secrets
```
supabase secrets set SEMAPHORE_API_KEY=<your api key> --project-ref vemaphehzjnvspxmweeb
supabase secrets set SEMAPHORE_SENDER_NAME=<your sender name> --project-ref vemaphehzjnvspxmweeb
```
(or via **Supabase Dashboard → Edge Functions → Manage secrets**).
`SEMAPHORE_SENDER_NAME` is optional; omit it to use Semaphore's account
default. The functions' other env vars (`SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`) are injected automatically by Supabase — nothing
to configure there.

### 5. Turn off email confirmation (required)
**Supabase Dashboard → Authentication → Providers → Email**
- Make sure **"Confirm email"** is **OFF**.

This matters because the app's flow is: `signUp()` → immediately request a
Semaphore OTP. Phone-OTP verification is the real verification gate in this
app, not an email link, and several other calls in this flow (e.g.
`functions.invoke`) expect an active Supabase session, which `signUp()` only
returns immediately when email confirmation isn't required. It's also why
`send-semaphore-otp` rate-limits by **phone number** as well as by account —
email confirmation being off means creating a throwaway account is trivial,
so a per-account-only limit wouldn't stop someone from targeting one phone
number with unlimited accounts.

### 6. What the app actually calls
`lib/services/auth_service.dart`'s `requestSemaphoreOtp`/`confirmSemaphoreOtp`
call `supabase.functions.invoke('send-semaphore-otp', ...)` and
`supabase.functions.invoke('verify-semaphore-otp', ...)` respectively — no
client-side SMS SDK is involved on any platform, so there's no Android/iOS/Web
native setup step for phone OTP at all (unlike Google Sign-In in Part 1).

---

## Part 3 — Database: `profiles` table

Run this once against your Supabase project (via the SQL editor in Supabase
Studio, or `mcp__supabase__apply_migration` from an assistant session connected
to the **correct** project — double check with `mcp__supabase__get_project_url`
that it returns `https://vemaphehzjnvspxmweeb.supabase.co` before running it):

```sql
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  email text,
  phone text,
  phone_verified boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Users can view their own profile" on public.profiles
  for select using (auth.uid() = id);
create policy "Users can insert their own profile" on public.profiles
  for insert with check (auth.uid() = id);
create policy "Users can update their own profile" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);
```

---

## Verification checklist

1. `SEMAPHORE_API_KEY` (and optionally `SEMAPHORE_SENDER_NAME`) secrets are set
   on the Supabase project (Part 2, step 4).
2. `send-semaphore-otp` and `verify-semaphore-otp` are `ACTIVE` Edge Functions,
   and `public.phone_otps` / `public.otp_send_log` exist (Part 2/3).
3. `flutter pub get`
4. `flutter analyze`
5. Confirm the `profiles` table exists (Part 3).
6. `flutter run` on Android or iOS (URL scheme in `Info.plist` for Google
   Sign-In — no phone-OTP-specific native setup needed, see Part 2 step 6).
7. Walk through:
   - **Register** → watch the password checklist go green → submit → receive the
     Semaphore SMS → enter the code → confirm a row appears in `public.profiles`
     with `phone_verified = true`, and that `auth.users.phone_confirmed_at` is
     set for that user → land in the app.
   - **Force-quit mid-signup** (after Register, before entering the code), then
     relaunch → confirm you're routed back into OTP verification with a fresh
     code, not stuck on a blank/expired one.
   - **Wrong code** → clear "Incorrect code" error; after 5 wrong tries, a
     distinct "too many attempts" error and the code is locked (a fresh
     Resend is required).
   - **Resend** before 60s → clear cooldown error, no SMS sent.
   - **Sign out** (logout icon in the app bar / sidebar).
   - **Login** with the email/password just created.
   - **Login with Google** (full sign-in).
   - **Register with Google prefill** — confirm only name/email populate, password
     fields stay required and empty.
   - **Forgot password** → confirm the reset email arrives.
