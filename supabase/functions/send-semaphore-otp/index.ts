// Sends a phone-verification code via Semaphore (semaphore.co) to the
// *calling* Supabase user's claimed phone number. Semaphore is a plain SMS
// API — it has no rate limiting of its own and no code-verification step,
// so both are implemented here: send attempts are logged to
// public.otp_send_log and checked against per-user and per-phone limits
// before Semaphore is ever called, and the code Semaphore returns is
// hashed and stored in public.phone_otps for verify-semaphore-otp to check
// against later. This function never issues its own session — Supabase
// remains the source of truth for the app's session.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SEMAPHORE_API_KEY = Deno.env.get("SEMAPHORE_API_KEY");
const SEMAPHORE_SENDER_NAME = Deno.env.get("SEMAPHORE_SENDER_NAME");

// This app only serves Philippine mobile numbers (see register_screen.dart)
// — the client always sends E.164 form, e.g. "+639171234567".
const PH_MOBILE_REGEX = /^\+639\d{9}$/;

const COOLDOWN_SECONDS = 60;
const BURST_WINDOW_MINUTES = 10;
const BURST_MAX = 3;
const DAILY_WINDOW_HOURS = 24;
const DAILY_MAX = 8;
const CODE_TTL_MINUTES = 5;

// Edge Functions run on a different path than the main Supabase API gateway
// and don't get CORS headers for free — the browser's preflight OPTIONS
// request needs an explicit 2xx + these headers, or it blocks the real POST
// before it's ever sent (surfaces client-side as a bare "Failed to fetch").
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const RATE_LIMITED_MESSAGE = "Too many attempts, please try again later.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }
  if (!SEMAPHORE_API_KEY) {
    return jsonResponse({ error: "SEMAPHORE_API_KEY secret is not configured on this project." }, 500);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header." }, 401);
  }

  // Resolve the calling user from their own Supabase session, so this
  // function can only ever send a code for whoever invoked it.
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "Invalid Supabase session." }, 401);
  }

  let phone: unknown;
  try {
    ({ phone } = await req.json());
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  // Validated server-side regardless of what the Flutter form already
  // enforces, since this is a public HTTP endpoint.
  if (typeof phone !== "string" || !PH_MOBILE_REGEX.test(phone)) {
    return jsonResponse({ error: "Enter a valid Philippine mobile number." }, 400);
  }

  const userId = userData.user.id;
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  try {
    const now = Date.now();
    const dailySince = new Date(now - DAILY_WINDOW_HOURS * 3600_000).toISOString();
    const burstSince = new Date(now - BURST_WINDOW_MINUTES * 60_000).toISOString();

    // Both limits are checked against the last 24h of history — the daily
    // cap subsumes the burst window, so one query per key covers both.
    const [{ data: recentByUser, error: byUserError }, { data: recentByPhone, error: byPhoneError }] =
      await Promise.all([
        admin
          .from("otp_send_log")
          .select("created_at")
          .eq("user_id", userId)
          .gte("created_at", dailySince)
          .order("created_at", { ascending: false }),
        admin
          .from("otp_send_log")
          .select("created_at")
          .eq("phone", phone)
          .gte("created_at", dailySince)
          .order("created_at", { ascending: false }),
      ]);
    if (byUserError) throw byUserError;
    if (byPhoneError) throw byPhoneError;

    const mostRecent = recentByUser?.[0]?.created_at;
    if (mostRecent && now - new Date(mostRecent).getTime() < COOLDOWN_SECONDS * 1000) {
      return jsonResponse({ error: "Please wait before requesting another code." }, 429);
    }

    const burstCountUser = (recentByUser ?? []).filter((r) => r.created_at >= burstSince).length;
    const burstCountPhone = (recentByPhone ?? []).filter((r) => r.created_at >= burstSince).length;
    if (burstCountUser >= BURST_MAX || burstCountPhone >= BURST_MAX) {
      return jsonResponse({ error: RATE_LIMITED_MESSAGE }, 429);
    }

    if ((recentByUser?.length ?? 0) >= DAILY_MAX || (recentByPhone?.length ?? 0) >= DAILY_MAX) {
      return jsonResponse({ error: RATE_LIMITED_MESSAGE }, 429);
    }

    // Recorded before calling Semaphore — a burst of concurrent requests
    // can't all pass the checks above by racing ahead of this insert.
    const { error: logError } = await admin.from("otp_send_log").insert({ user_id: userId, phone });
    if (logError) throw logError;

    const semaphoreNumber = phone.replace(/^\+/, "");
    const form = new URLSearchParams({
      apikey: SEMAPHORE_API_KEY,
      number: semaphoreNumber,
      message: `Your IsdaSafe verification code is {otp}. It expires in ${CODE_TTL_MINUTES} minutes.`,
    });
    if (SEMAPHORE_SENDER_NAME) form.set("sendername", SEMAPHORE_SENDER_NAME);

    const semaphoreResponse = await fetch("https://api.semaphore.co/api/v4/otp", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
    });
    const rawBody = await semaphoreResponse.text();

    let parsed: unknown;
    try {
      parsed = JSON.parse(rawBody);
    } catch {
      console.error("send-semaphore-otp: non-JSON response from Semaphore:", rawBody);
      return jsonResponse({ error: "Could not send verification code, please try again." }, 502);
    }

    // Semaphore's /otp endpoint returns an array with one entry per
    // recipient on success. It can also return 200 OK on a rejected send
    // (bad number, insufficient credits, unapproved sender name) with an
    // error message in the body instead — so the HTTP status alone can't
    // be trusted, and Semaphore's raw error text is never forwarded to the
    // client (it can include account/billing details).
    const entry = Array.isArray(parsed) ? parsed[0] : undefined;
    const code = entry && typeof entry === "object" ? (entry as Record<string, unknown>).code : undefined;
    if (!semaphoreResponse.ok || typeof code !== "number") {
      console.error("send-semaphore-otp: Semaphore rejected the send:", semaphoreResponse.status, rawBody);
      return jsonResponse({ error: "Could not send verification code, please try again." }, 502);
    }

    const codeHash = await sha256Hex(String(code));
    const expiresAt = new Date(now + CODE_TTL_MINUTES * 60_000).toISOString();
    const { error: upsertError } = await admin.from("phone_otps").upsert({
      user_id: userId,
      phone,
      code_hash: codeHash,
      expires_at: expiresAt,
      attempts: 0,
      locked: false,
    });
    if (upsertError) {
      // Semaphore already sent a real code at this point — the user has
      // it, but there's nothing left to check it against. Their next
      // verify attempt fails cleanly with "expired" rather than silently
      // accepting garbage.
      console.error("send-semaphore-otp: phone_otps upsert failed after a real send:", upsertError);
      return jsonResponse({ error: "Could not send verification code, please try again." }, 500);
    }

    return jsonResponse({ success: true });
  } catch (err) {
    console.error("send-semaphore-otp: unexpected error:", err);
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: `Unexpected error: ${message}` }, 500);
  }
});
