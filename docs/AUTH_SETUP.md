# Auth Setup Guide

This app uses **Supabase Auth** as the single source of truth for identity —
email/password and Google sign-in both end in a Supabase session. Phone-number
OTP is the one exception: it goes through **Firebase Phone Auth** instead of
Supabase's own Phone provider (see Part 2 for why), with a Supabase Edge
Function bridging the two — Firebase never issues a session of its own that
the app uses.

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

## Part 2 — Phone OTP (Firebase Phone Auth + Supabase Edge Function)

Supabase's built-in Phone provider only supports Twilio, Twilio Verify,
MessageBird, Vonage, and TextLocal — there's no Firebase option there. So
instead of Supabase's Phone provider, this app uses Firebase's own Phone Auth
SDK client-side to send/verify the OTP, then calls a Supabase Edge Function
(`verify-firebase-phone`) that verifies the resulting Firebase ID token
server-side and marks the **Supabase** user's phone confirmed. Firebase is
never used as an identity provider the app signs in with — the user is
already signed into Supabase (via email/password) before phone verification
starts; Firebase just proves they own the number.

### 1. Create a Firebase project
Go to [console.firebase.google.com](https://console.firebase.google.com) →
**Add project** (e.g. "IsdaSafe") → you can decline Google Analytics, it's not
needed.

### 2. Enable Phone sign-in
**Firebase Console → Build → Authentication → Sign-in method → Phone** → Enable → Save.

### 2b. Allow the Philippines in the SMS region policy (required)
**Firebase Console → Authentication → Settings tab → SMS region policy** —
this defaults to blocking regions until explicitly allowed, so phone auth
will fail with `operation-not-allowed: SMS unable to be sent until this
region enabled by the app developer` until you either select **Allow by
default** or add the **Philippines** to an allowlist.

### 3. Register your apps + generate `lib/firebase_options.dart`
Run from the repo root (requires Node + the Firebase CLI: `npm install -g firebase-tools`,
then `firebase login`):
```
dart pub global activate flutterfire_cli
flutterfire configure
```
Pick the Firebase project from step 1, then select the platforms you build for
(Android, iOS, Web at minimum). This generates `lib/firebase_options.dart` and
any native config files (`google-services.json` etc.) automatically — nothing
to hand-edit. `main.dart` already imports this file; the app won't compile
until you've run this.

### 4. Android: no extra config
Firebase's Android SDK matches by package name (`com.isdasafe.app`) + the
`google-services.json` from step 3 — the SHA-1 used for Google Sign-In isn't
needed here.

### 5. iOS: upload an APNs key (required for silent-push verification)
**Firebase Console → Project settings → Cloud Messaging → Apple app configuration
→ APNs Authentication Key → Upload** — needs a `.p8` key from
**Apple Developer → Certificates, Identifiers & Profiles → Keys** (enable "Apple
Push Notifications service"). Without this, iOS phone verification falls back
to a visible reCAPTCHA instead of silent verification.

### 6. Web: nothing extra
`firebase_auth`'s web implementation handles the required reCAPTCHA
automatically once `flutterfire configure` has wired the web config in.

### 7. Deploy the Edge Function + set its secret
The function itself (`supabase/functions/verify-firebase-phone/index.ts`) is
already deployed. It needs one secret it can't get automatically — your
Firebase **Project ID** (Firebase Console → Project settings → General →
"Project ID", *not* the project name):
```
supabase secrets set FIREBASE_PROJECT_ID=<your-firebase-project-id> --project-ref vemaphehzjnvspxmweeb
```
(or set it via **Supabase Dashboard → Edge Functions → Manage secrets**). The
function's other three env vars (`SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`) are injected automatically by Supabase — nothing
to configure there.

### 8. Turn off email confirmation (required)
**Supabase Dashboard → Authentication → Providers → Email**
- Make sure **"Confirm email"** is **OFF**.

This matters because the app's flow is: `signUp()` → immediately request a
Firebase OTP. Phone-OTP verification is the real verification gate in this
app, not an email link, and several other calls in this flow (e.g.
`functions.invoke`) expect an active Supabase session, which `signUp()` only
returns immediately when email confirmation isn't required.

### 9. What the app actually calls
`lib/services/auth_service.dart` wraps `firebase_auth`'s `verifyPhoneNumber`/
`signInWithCredential` to get a Firebase ID token, then calls
`supabase.functions.invoke('verify-firebase-phone', ...)` — the Flutter app
never talks to Twilio, and never holds a long-lived Firebase session (it signs
out of Firebase immediately after the Edge Function call, success or not).

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

1. `flutterfire configure` has been run (Part 2, step 3) — `lib/firebase_options.dart` exists.
2. SMS region policy allows the Philippines (Part 2, step 2b).
3. `FIREBASE_PROJECT_ID` secret is set on the Supabase project (Part 2, step 7).
4. `flutter pub get`
5. `flutter analyze`
6. Confirm the `profiles` table exists (Part 3).
7. `flutter run` on Android (debug SHA-1 registered for Google Sign-In) or iOS
   (URL scheme in `Info.plist` + APNs key uploaded for Firebase).
8. Walk through:
   - **Register** → watch the password checklist go green → submit → receive the
     Firebase SMS → enter the code → confirm a row appears in `public.profiles`
     with `phone_verified = true`, and that `auth.users.phone_confirmed_at` is
     set for that user → land in the app.
   - **Force-quit mid-signup** (after Register, before entering the code), then
     relaunch → confirm you're routed back into OTP verification with a fresh
     code, not stuck on a blank/expired one.
   - **Sign out** (logout icon in the app bar / sidebar).
   - **Login** with the email/password just created.
   - **Login with Google** (full sign-in).
   - **Register with Google prefill** — confirm only name/email populate, password
     fields stay required and empty.
   - **Forgot password** → confirm the reset email arrives.
