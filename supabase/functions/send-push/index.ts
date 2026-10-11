// Pushes a notification (row of public.notifications) to every phone of its
// owner through Firebase Cloud Messaging, so it shows on Android even when
// IsdaSafe isn't running.
//
// Called only by the database: the push_new_notification() trigger
// (supabase/migrations/20261011160000_push_notifications.sql) queues it
// through pg_net for each new notification. Deployed without JWT
// verification (`supabase functions deploy send-push --no-verify-jwt`); it
// checks the same Vault-generated shared secret as send-alert-sms instead.
//
// Needs the FCM_SERVICE_ACCOUNT secret (see ../_shared/fcm.ts); without it
// nothing is pushed. Tokens FCM reports as gone are deleted.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { sendToTokens, serviceAccount } from "../_shared/fcm.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

// The shared secret, read once per instance.
let callerSecret: Promise<string | null> | null = null;
function loadCallerSecret(): Promise<string | null> {
  callerSecret ??= Promise.resolve(admin.rpc("alert_sms_secret")).then(({ data, error }) => {
    if (error) {
      console.error("send-push: alert_sms_secret() failed:", error.message);
      callerSecret = null; // try again next time
      return null;
    }
    return typeof data === "string" && data ? data : null;
  });
  return callerSecret;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);
  const secret = await loadCallerSecret();
  if (!secret) return json({ error: "alert_sms_secret is not configured." }, 500);
  if (!sameSecret(req.headers.get("Authorization") ?? "", `Bearer ${secret}`)) {
    return json({ error: "Unauthorized." }, 401);
  }

  let notificationId: unknown;
  try {
    ({ notification_id: notificationId } = await req.json());
  } catch {
    return json({ error: "Invalid JSON body." }, 400);
  }
  if (typeof notificationId !== "string") return json({ error: "notification_id is required." }, 400);

  const account = serviceAccount();
  if (!account) return json({ status: "not_configured" });

  const { data: notification, error } = await admin
    .from("notifications")
    .select("id, user_id, pond_id, type, title, body")
    .eq("id", notificationId)
    .maybeSingle();
  if (error) return json({ error: error.message }, 500);
  if (!notification) return json({ status: "ignored" });

  const { data: tokens } = await admin
    .from("push_tokens")
    .select("token")
    .eq("user_id", notification.user_id);
  if (!tokens?.length) return json({ status: "no_devices" });

  const alert = notification.type.startsWith("water_alert_");
  const { sent, gone } = await sendToTokens(account, tokens.map((t) => t.token), {
    title: notification.title,
    body: notification.body,
    data: {
      notification_id: notification.id,
      type: notification.type,
      pond_id: notification.pond_id ?? "",
    },
    channelId: alert ? "water_alerts" : "pond_verification",
    tag: notification.id,
    urgent: alert && notification.type !== "water_alert_cleared",
  });
  if (gone.length) await admin.from("push_tokens").delete().in("token", gone);

  console.log(`send-push: notification=${notification.id} sent=${sent} removed=${gone.length}`);
  return json({ status: "ok", sent, removed: gone.length });
});
