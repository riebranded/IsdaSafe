// Verifies a Firebase Phone Auth ID token and marks the *calling* Supabase
// user's phone as confirmed. Firebase is used only to send/verify the SMS
// OTP (see docs/AUTH_SETUP.md Part 2) — Supabase remains the source of
// truth for the app's session, so this function never issues its own
// session; it just updates auth.users for whoever's Supabase JWT called it.
//
// There is no Firebase Admin SDK for Deno, so the ID token is verified
// directly against Firebase's public JWKS instead of trusting the client.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { createRemoteJWKSet, jwtVerify } from "npm:jose@5";

const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com",
  ),
);

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }
  if (!FIREBASE_PROJECT_ID) {
    return jsonResponse(
      { error: "FIREBASE_PROJECT_ID secret is not configured on this project." },
      500,
    );
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing Authorization header." }, 401);
  }

  // Resolve the calling user from their own Supabase session, so this
  // function can only ever update the account of whoever invoked it.
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return jsonResponse({ error: "Invalid Supabase session." }, 401);
  }

  let idToken: unknown;
  try {
    ({ idToken } = await req.json());
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  if (typeof idToken !== "string" || idToken.length === 0) {
    return jsonResponse({ error: "Missing idToken in request body." }, 400);
  }

  let phoneNumber: string | undefined;
  try {
    const { payload } = await jwtVerify(idToken, FIREBASE_JWKS, {
      issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
      audience: FIREBASE_PROJECT_ID,
    });
    phoneNumber = payload.phone_number as string | undefined;
  } catch (err) {
    return jsonResponse({ error: `Firebase token verification failed: ${err}` }, 401);
  }

  if (!phoneNumber) {
    return jsonResponse({ error: "Firebase token has no verified phone number." }, 400);
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { error: updateError } = await admin.auth.admin.updateUserById(userData.user.id, {
    phone: phoneNumber,
    phone_confirm: true,
  });
  if (updateError) {
    return jsonResponse({ error: updateError.message }, 500);
  }

  return jsonResponse({ success: true, phone: phoneNumber });
});
