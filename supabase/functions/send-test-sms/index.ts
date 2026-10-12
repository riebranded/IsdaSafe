// "Send a test SMS alert" from Settings: texts a made-up water alert to the
// signed-in user's verified phone through Semaphore, worded like a real one
// (see evaluate_water_alerts()), to check that alert texts really arrive.
// Nothing is saved in the notifications list.
//
// Uses the same secrets as send-alert-sms: SMS_ENABLED must be "true" and
// SEMAPHORE_API_KEY set (SEMAPHORE_SENDER_NAME optional). Capped at
// HOURLY_MAX tests per account per hour (public.test_sms_log).
//
// Called by the app with the user's session (JWT verification on).
// Statuses: sent | failed (Semaphore rejected it) | disabled (SMS_ENABLED
// isn't "true") | not_configured (no SEMAPHORE_API_KEY) | no_phone (no
// verified phone) | rate_limited.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SEMAPHORE_API_KEY = Deno.env.get("SEMAPHORE_API_KEY");
const SEMAPHORE_SENDER_NAME = Deno.env.get("SEMAPHORE_SENDER_NAME");
const SMS_ENABLED = Deno.env.get("SMS_ENABLED") === "true";

const PH_MOBILE_REGEX = /^\+639\d{9}$/;
const HOURLY_MAX = 3;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

// Same as send-alert-sms's sendSms, but says why it failed.
async function sendSms(phone: string, message: string): Promise<{ ok: boolean; detail?: string }> {
  try {
    const form = new URLSearchParams({
      apikey: SEMAPHORE_API_KEY!,
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
      console.error("send-test-sms: Semaphore rejected the SMS:", response.status, raw);
      return { ok: false, detail: raw.slice(0, 300) };
    }
    return { ok: true };
  } catch (err) {
    console.error("send-test-sms: SMS error:", err);
    return { ok: false, detail: String(err) };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header." }, 401);
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json({ error: "Invalid session." }, 401);
  const userId = userData.user.id;

  if (!SMS_ENABLED) return json({ status: "disabled" });
  if (!SEMAPHORE_API_KEY) return json({ status: "not_configured" });

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: profile } = await admin
    .from("profiles")
    .select("phone, phone_verified")
    .eq("id", userId)
    .maybeSingle();
  const phone = profile?.phone_verified ? profile.phone as string | null : null;
  if (!phone || !PH_MOBILE_REGEX.test(phone)) return json({ status: "no_phone" });

  const since = new Date(Date.now() - 3600_000).toISOString();
  const { count } = await admin
    .from("test_sms_log")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .gte("created_at", since);
  if ((count ?? 0) >= HOURLY_MAX) return json({ status: "rate_limited", phone });

  // Worded like a real alert text, with one of the account's pond names.
  const { data: pond } = await admin
    .from("ponds")
    .select("name")
    .eq("user_id", userId)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  const pondName = String(pond?.name ?? "").replace(/[^\x20-\x7E]/g, "").slice(0, 30) || "Test pond";
  const message =
    `IsdaSafe TEST WARNING: Pond "${pondName}" Dissolved oxygen is 3.5 mg/L. ` +
    "Turn on the aerators now and stop feeding. (Test only)";

  const result = await sendSms(phone, message.slice(0, 160));
  const status = result.ok ? "sent" : "failed";
  await admin.from("test_sms_log").insert({ user_id: userId, status });
  console.log(`send-test-sms: user=${userId} sms=${status}`);
  return json({ status, phone, detail: result.detail });
});
