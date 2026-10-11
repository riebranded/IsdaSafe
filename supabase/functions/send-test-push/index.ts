// "Send a test push" from Settings: pushes a test notification through
// Firebase Cloud Messaging to the signed-in user's phones, after a few
// seconds so they can leave the app and see it arrive like a real alert.
// Nothing is saved in the notifications list.
//
// Called by the app with the user's session (JWT verification on). Answers
// right away; the push goes out in the background (EdgeRuntime.waitUntil).
// Body: { delay_seconds?: 0-15 }.
// Statuses: scheduled | no_devices (this account has no registered phone) |
// not_configured (FCM_SERVICE_ACCOUNT secret missing).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { sendToTokens, serviceAccount } from "../_shared/fcm.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

  let delaySeconds = 5;
  try {
    const body = await req.json();
    if (typeof body?.delay_seconds === "number") {
      delaySeconds = Math.min(15, Math.max(0, Math.round(body.delay_seconds)));
    }
  } catch { /* no body: default delay */ }

  const account = serviceAccount();
  if (!account) return json({ status: "not_configured" });

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: tokens } = await admin
    .from("push_tokens")
    .select("token")
    .eq("user_id", userData.user.id);
  if (!tokens?.length) return json({ status: "no_devices" });

  const send = async () => {
    await new Promise((resolve) => setTimeout(resolve, delaySeconds * 1000));
    const tag = `test-${Date.now()}`;
    const { sent, gone, errors } = await sendToTokens(account, tokens.map((t) => t.token), {
      title: "IsdaSafe test notification",
      body: "Push notifications work on this phone.",
      data: { type: "test_push", tag },
      channelId: "water_alerts",
      tag,
      urgent: true,
    });
    if (gone.length) await admin.from("push_tokens").delete().in("token", gone);
    console.log(
      `send-test-push: user=${userData.user.id} sent=${sent} removed=${gone.length} errors=${errors.join(",")}`,
    );
  };
  // Answer now; push in the background.
  // @ts-ignore EdgeRuntime is provided by Supabase's runtime.
  EdgeRuntime.waitUntil(send());

  return json({ status: "scheduled", devices: tokens.length, delay_seconds: delaySeconds });
});
