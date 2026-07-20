// Verifies a code sent via send-semaphore-otp and marks the *calling*
// Supabase user's phone as confirmed. Semaphore only sends SMS — it has no
// verification step of its own — so the code is checked here against a
// SHA-256 hash stored in public.phone_otps by send-semaphore-otp, with a
// hard lockout after too many wrong guesses. This function never issues
// its own session; it just updates auth.users for whoever's Supabase JWT
// called it.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const MAX_ATTEMPTS = 5;

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header." }, 401);
  }

  // Resolve the calling user from their own Supabase session, so this
  // function can only ever verify/confirm the account of whoever invoked it.
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "Invalid Supabase session." }, 401);
  }

  let code: unknown;
  try {
    ({ code } = await req.json());
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  if (typeof code !== "string" || !/^\d{4,8}$/.test(code)) {
    return jsonResponse({ error: "Enter the verification code." }, 400);
  }

  const userId = userData.user.id;
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  try {
    const { data: row, error: fetchError } = await admin
      .from("phone_otps")
      .select("phone, code_hash, expires_at, attempts, locked")
      .eq("user_id", userId)
      .maybeSingle();
    if (fetchError) throw fetchError;

    if (!row) {
      return jsonResponse({ error: "Request a new code." }, 400);
    }
    if (row.locked) {
      return jsonResponse({ error: "Too many attempts, request a new code." }, 400);
    }
    if (new Date(row.expires_at).getTime() < Date.now()) {
      return jsonResponse({ error: "Code expired, request a new one." }, 400);
    }

    const submittedHash = await sha256Hex(code);
    if (submittedHash !== row.code_hash) {
      const attempts = row.attempts + 1;
      const locked = attempts >= MAX_ATTEMPTS;
      const { error: updateError } = await admin
        .from("phone_otps")
        .update({ attempts, locked })
        .eq("user_id", userId);
      if (updateError) {
        console.error("verify-semaphore-otp: failed to record attempt:", updateError);
      }
      return jsonResponse(
        { error: locked ? "Too many attempts, request a new code." : "Incorrect code." },
        400,
      );
    }

    const { error: adminUpdateError } = await admin.auth.admin.updateUserById(userId, {
      phone: row.phone,
      phone_confirm: true,
    });
    if (adminUpdateError) {
      console.error("verify-semaphore-otp: updateUserById failed:", adminUpdateError);
      return jsonResponse({ error: adminUpdateError.message }, 500);
    }

    const { error: deleteError } = await admin.from("phone_otps").delete().eq("user_id", userId);
    if (deleteError) {
      // Non-fatal — the row is single-use and will just be overwritten by
      // the next send, or left as an already-consumed stale row.
      console.error("verify-semaphore-otp: cleanup delete failed (non-fatal):", deleteError);
    }

    return jsonResponse({ success: true, phone: row.phone });
  } catch (err) {
    console.error("verify-semaphore-otp: unexpected error:", err);
    const message = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: `Unexpected error: ${message}` }, 500);
  }
});
