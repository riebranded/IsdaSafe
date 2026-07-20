# Auth Setup Guide

This app uses **Supabase Auth** for everything — email/password, Google sign-in, and
phone-number OTP verification. The Flutter app never talks to Google or Twilio
directly; it only calls `supabase_flutter`'s `auth` client, and Supabase relays
to Google/Twilio on the backend using credentials you configure in the Supabase
dashboard. This keeps all secrets (Twilio Auth Token, Google Client Secret) out
of the app.

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

## Part 2 — Phone OTP (Twilio + Supabase)

### 1. Create a Twilio account
Sign up at [twilio.com](https://www.twilio.com) and verify your email + phone.

### 2. Create a Verify Service
**Twilio Console → Verify → Services → Create new Verify Service**
- Friendly name: "IsdaSafe OTP"
- Save. Copy the **Verify Service SID** (starts with `VA...`).

Twilio *Verify* (not raw Messaging) is used because it manages OTP generation,
expiry, and rate-limiting for you — no template/expiry logic to build yourself.

### 3. Get your Account SID and Auth Token
**Twilio Console → Account dashboard** — copy the **Account SID** and **Auth
Token** (click "show" to reveal it).

### 4. Trial account limitation
On a Twilio trial account, you can only send SMS to phone numbers you've
pre-verified under **Console → Phone Numbers → Verified Caller IDs**. Upgrade to
a paid account to send to arbitrary numbers.

### 5. Enable Phone auth in Supabase
**Supabase Dashboard → Authentication → Providers → Phone**
- Enable the provider.
- SMS provider: **Twilio Verify**.
- Enter your Account SID, Auth Token, and Verify Service SID from steps 2–3.
- Save.

### 6. Turn off email confirmation (required)
**Supabase Dashboard → Authentication → Providers → Email**
- Make sure **"Confirm email"** is **OFF**.

This matters because the app's flow is: `signUp()` → immediately
`updateUser(phone: ...)` to trigger the OTP SMS. `updateUser` requires an
active session, and `signUp()` only returns one immediately if email
confirmation isn't required. Phone-OTP verification is the real verification
gate in this app, not an email link.

### 7. (Optional) Raise SMS rate limits for testing
**Supabase Dashboard → Authentication → Rate Limits** — the default SMS-send
limit can be hit quickly during development/testing; raise it if needed to
avoid `over_sms_send_rate_limit` errors.

### 8. What the app actually calls
Everything phone-related in `lib/services/auth_service.dart` goes through
`supabase.auth.updateUser(...)` and `supabase.auth.verifyOTP(...)` — no HTTP
client, no Twilio SDK, no Twilio secret anywhere in the Flutter app.

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

1. `flutter pub get`
2. `flutter analyze`
3. Confirm the `profiles` table exists (Part 3).
4. `flutter run` on Android (debug SHA-1 registered) or iOS (URL scheme in `Info.plist`).
5. Walk through:
   - **Register** → watch the password checklist go green → submit → receive the
     Twilio SMS → enter the code → confirm a row appears in `public.profiles`
     with `phone_verified = true` → land in the app.
   - **Sign out** (logout icon in the app bar / sidebar).
   - **Login** with the email/password just created.
   - **Login with Google** (full sign-in).
   - **Register with Google prefill** — confirm only name/email populate, password
     fields stay required and empty.
   - **Forgot password** → confirm the reset email arrives.
