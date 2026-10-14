// "Delete account" from Settings: permanently removes the signed-in user's
// account and everything tied to it (Privacy Policy: right to erasure).
//
// 1. Storage: every file under "<uid>/" in the avatars and pond-photos
//    buckets (pond photos sit one folder deeper, "<uid>/<pondId>/...").
// 2. otp_send_log rows (the only user table without an auth.users FK).
// 3. The auth user itself. profiles, ponds, sensor_readings, notifications,
//    devices, push_tokens and the other user tables all reference
//    auth.users with ON DELETE CASCADE, so they go with it. Paired devices
//    keep their device_credentials, so the hardware can be claimed again.
//
// Called by the app with the user's session (JWT verification on).
// Statuses: deleted | failed.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const BUCKETS = ["avatars", "pond-photos"];

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

// Storage's list() isn't recursive: entries with a null id are folders.
async function listFiles(admin: SupabaseClient, bucket: string, prefix: string): Promise<string[]> {
  const files: string[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await admin.storage.from(bucket).list(prefix, { limit: 1000, offset });
    if (error) throw error;
    for (const entry of data) {
      const path = `${prefix}/${entry.name}`;
      if (entry.id === null) files.push(...(await listFiles(admin, bucket, path)));
      else files.push(path);
    }
    if (data.length < 1000) return files;
  }
}

async function deleteUserFiles(admin: SupabaseClient, userId: string): Promise<void> {
  for (const bucket of BUCKETS) {
    const files = await listFiles(admin, bucket, userId);
    for (let i = 0; i < files.length; i += 100) {
      const { error } = await admin.storage.from(bucket).remove(files.slice(i, i + 100));
      if (error) throw error;
    }
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

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  try {
    await deleteUserFiles(admin, userId);
    const { error: logError } = await admin.from("otp_send_log").delete().eq("user_id", userId);
    if (logError) throw logError;
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) throw deleteError;
  } catch (err) {
    console.error("delete-account: failed for", userId, err);
    return json({ status: "failed" }, 500);
  }
  return json({ status: "deleted" });
});
