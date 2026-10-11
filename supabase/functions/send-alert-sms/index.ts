// Texts a pond water alert to the pond owner's verified phone via Semaphore.
//
// Called only by the database: the evaluate_water_alerts() trigger
// (supabase/migrations/20261011150000_water_alerts.sql) queues it through
// pg_net right after creating the alert notification. It is NOT for apps or
// browsers, so it's deployed without JWT verification
// (`supabase functions deploy send-alert-sms --no-verify-jwt`) and checks a
// shared secret instead: the migration generates it in Vault, the trigger
// sends it, and this function reads it back with the service role through
// alert_sms_secret(). Nothing to copy by hand.
//
// Uses the same SEMAPHORE_API_KEY / SEMAPHORE_SENDER_NAME / SMS_ENABLED
// secrets as verify-pond: with SMS_ENABLED not "true", nothing is sent.
// Body: { notification_id, message }. Writes the outcome to
// notifications.sms_status.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SEMAPHORE_API_KEY = Deno.env.get("SEMAPHORE_API_KEY");
const SEMAPHORE_SENDER_NAME = Deno.env.get("SEMAPHORE_SENDER_NAME");
const SMS_ENABLED = Deno.env.get("SMS_ENABLED") === "true";

const PH_MOBILE_REGEX = /^\+639\d{9}$/;

// Cost guard: alert texts per account per day, whatever the alerts say.
const DAILY_MAX = 20;

type SmsStatus = "sent" | "failed" | "skipped" | "rate_limited";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Constant-time comparison, so the secret can't be guessed byte by byte.
function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a);
  const y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

// Same as verify-pond's sendSms. Never throws.
async function sendSms(phone: string, message: string): Promise<"sent" | "failed" | "skipped"> {
  if (!SEMAPHORE_API_KEY || !PH_MOBILE_REGEX.test(phone)) return "skipped";
  try {
    const form = new URLSearchParams({
      apikey: SEMAPHORE_API_KEY,
      number: phone.replace(/^\+/, ""),
      message,
    });
    if (SEMAPHORE_SENDER_NAME) form.set("sendername", SEMAPHORE_SENDER_NAME);
    const response = await fetch("https://api.semaphore.co/api/v4/messages", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form,
    });
    const raw = await response.text();
    // Semaphore can answer 200 with an error body, so check for a message id.
    let ok = false;
    try {
      const parsed = JSON.parse(raw);
      ok = Array.isArray(parsed) && !!parsed[0] && typeof parsed[0] === "object" && "message_id" in parsed[0];
    } catch { /* non-JSON */ }
    if (!response.ok || !ok) {
      console.error("send-alert-sms: Semaphore rejected the SMS:", response.status, raw);
      return "failed";
    }
    return "sent";
  } catch (err) {
    console.error("send-alert-sms: SMS error:", err);
    return "failed";
  }
}

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

// The shared secret, read once per instance.
let alertSecret: Promise<string | null> | null = null;
function loadAlertSecret(): Promise<string | null> {
  alertSecret ??= Promise.resolve(admin.rpc("alert_sms_secret")).then(({ data, error }) => {
    if (error) {
      console.error("send-alert-sms: alert_sms_secret() failed:", error.message);
      alertSecret = null; // try again next time
      return null;
    }
    return typeof data === "string" && data ? data : null;
  });
  return alertSecret;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);
  const secret = await loadAlertSecret();
  if (!secret) return json({ error: "alert_sms_secret is not configured." }, 500);
  const auth = req.headers.get("Authorization") ?? "";
  if (!sameSecret(auth, `Bearer ${secret}`)) {
    return json({ error: "Unauthorized." }, 401);
  }

  let notificationId: unknown, message: unknown;
  try {
    ({ notification_id: notificationId, message } = await req.json());
  } catch {
    return json({ error: "Invalid JSON body." }, 400);
  }
  if (typeof notificationId !== "string" || typeof message !== "string" || !message) {
    return json({ error: "notification_id and message are required." }, 400);
  }

  const { data: notification, error } = await admin
    .from("notifications")
    .select("id, user_id, sms_status")
    .eq("id", notificationId)
    .maybeSingle();
  if (error) return json({ error: error.message }, 500);
  // Already handled (e.g. pg_net retried): don't text twice.
  if (!notification || notification.sms_status !== "pending") return json({ status: "ignored" });

  let status: SmsStatus;
  const { data: profile } = await admin
    .from("profiles")
    .select("phone, phone_verified")
    .eq("id", notification.user_id)
    .maybeSingle();
  if (!SMS_ENABLED || !profile?.phone || !profile.phone_verified) {
    status = "skipped";
  } else {
    const since = new Date(Date.now() - 24 * 3600_000).toISOString();
    const { count } = await admin
      .from("notifications")
      .select("id", { count: "exact", head: true })
      .eq("user_id", notification.user_id)
      .like("type", "water_alert_%")
      .eq("sms_status", "sent")
      .gte("created_at", since);
    status = (count ?? 0) >= DAILY_MAX
      ? "rate_limited"
      // ASCII, one segment (160 characters).
      : await sendSms(profile.phone, message.replace(/[^\x20-\x7E]/g, "").slice(0, 160));
  }

  await admin.from("notifications").update({ sms_status: status }).eq("id", notification.id);
  console.log(`send-alert-sms: notification=${notification.id} sms=${status}`);
  return json({ status });
});
