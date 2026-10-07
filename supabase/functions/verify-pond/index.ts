// Verifies in the background that a pond really exists.
//
// The app saves a pond as `pending` (see the ponds_protect_verification
// trigger) and calls this function with { pond_id }. The function replies 202
// straight away and finishes the work after the response:
//   - "satellite" ponds: Google Maps satellite imagery at the pinned spot is
//     analysed by Gemini. If it can't confirm a pond but sees BUILDINGS there
//     (a pond could be covered or indoors), the pond becomes `needs_photos`
//     instead of being rejected.
//   - `needs_photos` ponds: the owner uploads at least 3 photos of the pond to
//     the private pond-photos bucket and calls again with { pond_id,
//     photo_paths }. Gemini then compares those photos with the satellite image
//     to decide that they're real pond photos taken at that same location.
//     The owner may also send the photos up front, in the first call: the
//     satellite check still runs first, and only if buildings hide the pond are
//     the photos compared right away instead of being asked for later.
//   - "photo" ponds (in-house, not visible from above): there is no satellite
//     check. The owner sends at least 3 photos with the first call and Gemini
//     checks that every one is a genuine pond/tank photo; none may already be
//     used for another pond. (Older in-house ponds with a single photo_path are
//     still checked the old way.)
// Then it records the result on the pond and creates an in-app notification.
// (It can also text the owner's verified phone number via Semaphore whatever
// happened, but that is off unless SMS_ENABLED=true.)
//
// Secrets: GEMINI_API_KEY, GOOGLE_MAPS_STATIC_API_KEY, SEMAPHORE_API_KEY (and
// optional SEMAPHORE_SENDER_NAME / GEMINI_MODEL / GEMINI_FALLBACK_MODEL). Calls
// are authenticated as the Supabase user, must target that user's own pond,
// and are rate limited via public.pond_verification_log.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GOOGLE_MAPS_STATIC_API_KEY = Deno.env.get("GOOGLE_MAPS_STATIC_API_KEY");
const SEMAPHORE_API_KEY = Deno.env.get("SEMAPHORE_API_KEY");
const SEMAPHORE_SENDER_NAME = Deno.env.get("SEMAPHORE_SENDER_NAME");
// Texts are switched off for now. Set the SMS_ENABLED secret to "true" to turn
// them back on (the SMS code below is intact); results still arrive in the app.
const SMS_ENABLED = Deno.env.get("SMS_ENABLED") === "true";

// Override with the GEMINI_MODEL secret. (gemini-2.5-flash is access-restricted.)
const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.8-flash";
// Tried if MODEL stays unavailable (Gemini returns 503 "high demand" in spikes).
const FALLBACK_MODEL = Deno.env.get("GEMINI_FALLBACK_MODEL") ?? "gemini-3.7-flash";
const ATTEMPTS_PER_MODEL = 3;
// Statuses that mean "try again shortly" rather than "this request is wrong".
const RETRYABLE_STATUSES = new Set([429, 500, 502, 503, 504]);
const HOURLY_MAX = 20;
// A check that started within this window is assumed to still be running.
const RUN_WINDOW_MS = 5 * 60_000;
const CONFIRM_THRESHOLD = 0.7;
const MAX_PHOTO_BYTES = 3 * 1024 * 1024;
// Photos asked for when buildings hide the pond (kept in sync with the app).
const MIN_EVIDENCE_PHOTOS = 3;
const MAX_EVIDENCE_PHOTOS = 6;
// Everything goes to Gemini inline in one request, which has a size limit.
const MAX_EVIDENCE_TOTAL_BYTES = 12 * 1024 * 1024;
const ALLOWED_MEDIA_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const PH_MOBILE_REGEX = /^\+639\d{9}$/;

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

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const SATELLITE_PROMPT = `You are verifying a fish-farm pond registration in the Philippines.
This is a satellite image. The location the user pinned is the exact CENTER of the image.
Decide whether a pond is at or immediately around the center: an aquaculture/fish pond, a
fishpond with dikes or embankments, a rectangular or irregular water-filled basin, or a
farm pond. Open sea, rivers, lakes far larger than a pond, rice paddies without standing
open water, rooftops, forest, bare ground and buildings are NOT ponds.
Also report buildings_present: true if buildings, roofs or other built structures cover the
center of the image, so that a pond could be inside, under or hidden by them even though you
cannot see it.
Reply with ONLY a JSON object: {"pond_present": boolean, "buildings_present": boolean, "confidence": number between 0 and 1, "reason": "one short sentence for the user"}`;

const PHOTO_PROMPT = `You are verifying a photo submitted to prove an "in-house" fish pond or
tank exists (covered, indoor or backyard, not visible from satellite).
Accept only a genuine, original photo taken of a real pond, fish tank, tarpaulin pond,
concrete tank or similar aquaculture container with water in it.
Reject (pond_present=false) if it is: a photo of a screen or printed picture, a stock/
internet/AI-generated or illustration image, a screenshot, a map, an empty container with no
water, an aquarium clearly meant for pets, or unrelated to ponds or tanks.
Reply with ONLY a JSON object: {"pond_present": boolean, "confidence": number between 0 and 1, "reason": "one short sentence for the user"}`;

const PHOTOS_PROMPT = `You are verifying photos submitted to prove an "in-house" fish pond or
tank exists (covered, indoor or backyard, not visible from satellite).
Accept only if EVERY photo is a genuine, original photo of a real pond, fish tank, tarpaulin
pond, concrete tank or similar aquaculture container with water in it, and the photos look
like the same site from different angles.
Reject (pond_present=false) if any photo is: a photo of a screen or printed picture, a stock/
internet/AI-generated or illustration image, a screenshot, a map, an empty container with no
water, an aquarium clearly meant for pets, or unrelated to ponds or tanks.
Reply with ONLY a JSON object: {"pond_present": boolean, "confidence": number between 0 and 1, "reason": "one short sentence for the user"}`;

const EVIDENCE_PROMPT = `You are verifying a fish-farm pond registration in the Philippines.
The FIRST image is a satellite view; the location the user pinned is its exact CENTER, and
buildings cover that spot so the pond itself is not visible from above. The remaining images
are photos the user says they took of their pond at that location.
Judge two things:
1. photos_show_pond: every photo is a genuine, original photo of a real pond, tank or similar
   aquaculture container with water in it (not a screenshot, a photo of a screen or print, a
   stock/internet/AI-generated image, an empty container, or unrelated to ponds).
2. same_location: the photos plausibly show the place in the satellite image. Look for
   matching surroundings seen from the ground: roof and wall colours and shapes, building
   layout and size, fences, trees, open areas, neighbouring structures. Different photos
   should look like the same site, and nothing should clearly contradict the satellite view.
Be strict: if the surroundings don't fit or you can't tell, same_location is false.
Reply with ONLY a JSON object: {"photos_show_pond": boolean, "same_location": boolean, "confidence": number between 0 and 1, "reason": "one short sentence for the user"}`;

/** Gemini was too busy (or unreachable) on every attempt and model. */
class ModelBusyError extends Error {}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

type Image = { mediaType: string; base64: string };

// One Gemini call that takes images + a prompt and returns the JSON object the
// prompt asks for, retrying busy responses and falling back to a second model.
async function askModel(
  prompt: string,
  images: Image[],
  properties: Record<string, unknown>,
  required: string[],
): Promise<Record<string, unknown>> {
  const body = JSON.stringify({
    contents: [{
      role: "user",
      parts: [
        ...images.map((i) => ({ inline_data: { mime_type: i.mediaType, data: i.base64 } })),
        { text: prompt },
      ],
    }],
    generationConfig: {
      responseMimeType: "application/json",
      responseSchema: { type: "OBJECT", properties, required },
    },
  });

  const models = FALLBACK_MODEL && FALLBACK_MODEL !== MODEL ? [MODEL, FALLBACK_MODEL] : [MODEL];
  let lastStatus = 0;
  let lastDetail = "";

  for (const model of models) {
    for (let attempt = 0; attempt < ATTEMPTS_PER_MODEL; attempt++) {
      if (attempt > 0) await sleep(1500 * attempt);
      let response: Response;
      try {
        response = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
          {
            method: "POST",
            headers: { "x-goog-api-key": GEMINI_API_KEY!, "content-type": "application/json" },
            body,
          },
        );
      } catch (err) {
        lastStatus = 0;
        lastDetail = String(err);
        console.warn(`verify-pond: ${model} unreachable (attempt ${attempt + 1}):`, err);
        continue;
      }
      const raw = await response.text();
      if (response.ok) {
        const text = JSON.parse(raw).candidates?.[0]?.content?.parts?.[0]?.text ?? "";
        return JSON.parse(text);
      }
      lastStatus = response.status;
      lastDetail = raw.slice(0, 300);
      console.warn(`verify-pond: ${model} HTTP ${response.status} (attempt ${attempt + 1}): ${lastDetail}`);
      // Not a "busy" error (bad key, model not available to us, ...): retrying
      // this model won't help, so move on to the fallback straight away.
      if (!RETRYABLE_STATUSES.has(response.status)) break;
    }
  }
  throw new ModelBusyError(`gemini unavailable, last HTTP ${lastStatus}: ${lastDetail}`);
}

const clamp01 = (n: unknown) => Math.min(1, Math.max(0, Number(n) || 0));
const shortReason = (r: unknown) => (typeof r === "string" ? r.slice(0, 240) : "");

type Pond = {
  id: string;
  user_id: string;
  name: string;
  latitude: number;
  longitude: number;
  verification_method: "satellite" | "photo" | null;
  verification_status: string;
  verification_started_at: string | null;
  photo_path: string | null;
  evidence_photo_paths: string[] | null;
};

type Outcome = {
  status: "verified" | "rejected" | "error" | "needs_photos";
  message: string;
  confidence?: number;
  photoHash?: string;
  evidenceHashes?: string[];
};

async function fetchSatellite(pond: Pond): Promise<Image> {
  const url = new URL("https://maps.googleapis.com/maps/api/staticmap");
  url.search = new URLSearchParams({
    center: `${pond.latitude},${pond.longitude}`,
    zoom: "19",
    size: "640x640",
    scale: "2",
    maptype: "satellite",
    key: GOOGLE_MAPS_STATIC_API_KEY!,
  }).toString();
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`google static map ${response.status}: ${(await response.text()).slice(0, 300)}`);
  }
  return {
    mediaType: response.headers.get("content-type")?.split(";")[0] ?? "image/png",
    base64: toBase64(new Uint8Array(await response.arrayBuffer())),
  };
}

async function verifySatellite(pond: Pond, mark: (s: string) => void): Promise<Outcome> {
  mark("static-map");
  const satellite = await fetchSatellite(pond);
  mark("gemini-satellite");
  const result = await askModel(
    SATELLITE_PROMPT,
    [satellite],
    {
      pond_present: { type: "BOOLEAN" },
      buildings_present: { type: "BOOLEAN" },
      confidence: { type: "NUMBER" },
      reason: { type: "STRING" },
    },
    ["pond_present", "buildings_present", "confidence", "reason"],
  );
  const confidence = clamp01(result.confidence);

  if (result.pond_present === true && confidence >= CONFIRM_THRESHOLD) {
    return { status: "verified", message: "It was confirmed on satellite imagery.", confidence };
  }
  if (result.buildings_present === true) {
    // A pond can sit inside or under buildings, so don't reject: ask for photos
    // and compare them with this satellite view instead.
    return {
      status: "needs_photos",
      message:
        `Buildings cover this spot, so the pond may be covered or indoors. Add at least ${MIN_EVIDENCE_PHOTOS} clear photos of the pond so we can match them to the satellite view.`,
      confidence,
    };
  }
  return {
    status: "rejected",
    message: shortReason(result.reason) || "No pond is visible at that spot on satellite imagery.",
    confidence,
  };
}

type Loaded = { photos: Image[]; hashes: string[] } | { rejected: Outcome };

// Downloads the owner's photos and applies the checks both photo flows share:
// supported type/size, no photo repeated, none already used for another pond.
async function loadEvidence(
  pond: Pond,
  paths: string[],
  admin: SupabaseClient,
  mark: (s: string) => void,
): Promise<Loaded> {
  mark("evidence-download");
  const photos: Image[] = [];
  const hashes: string[] = [];
  let total = 0;
  for (const path of paths) {
    const { data: blob, error } = await admin.storage.from("pond-photos").download(path);
    if (error || !blob) throw new Error(`photo download failed: ${error?.message ?? "no data"}`);
    const mediaType = blob.type || "image/jpeg";
    total += blob.size;
    if (!ALLOWED_MEDIA_TYPES.has(mediaType) || blob.size > MAX_PHOTO_BYTES || total > MAX_EVIDENCE_TOTAL_BYTES) {
      return { rejected: { status: "rejected", message: "The photos must be JPG, PNG or WebP files, under 3 MB each." } };
    }
    const bytes = new Uint8Array(await blob.arrayBuffer());
    hashes.push(await sha256Hex(bytes));
    photos.push({ mediaType, base64: toBase64(bytes) });
  }

  mark("evidence-duplicate-check");
  if (new Set(hashes).size < hashes.length) {
    return {
      rejected: { status: "rejected", message: "The same photo was used more than once. Each photo must be different." },
    };
  }
  const { data: reusedA, error: errA } = await admin
    .from("ponds").select("id").neq("id", pond.id).overlaps("evidence_photo_hashes", hashes).limit(1);
  if (errA) throw errA;
  const { data: reusedB, error: errB } = await admin
    .from("ponds").select("id").neq("id", pond.id).in("photo_hash", hashes).limit(1);
  if (errB) throw errB;
  if ((reusedA && reusedA.length > 0) || (reusedB && reusedB.length > 0)) {
    return { rejected: { status: "rejected", message: "One of these photos was already used to verify another pond." } };
  }
  return { photos, hashes };
}

// In-house ponds: every photo must be a genuine pond/tank photo. No satellite.
async function verifyPhotos(
  pond: Pond,
  paths: string[],
  admin: SupabaseClient,
  mark: (s: string) => void,
): Promise<Outcome> {
  const loaded = await loadEvidence(pond, paths, admin, mark);
  if ("rejected" in loaded) return loaded.rejected;

  mark("gemini-photos");
  const result = await askModel(
    PHOTOS_PROMPT,
    loaded.photos,
    {
      pond_present: { type: "BOOLEAN" },
      confidence: { type: "NUMBER" },
      reason: { type: "STRING" },
    },
    ["pond_present", "confidence", "reason"],
  );
  const confidence = clamp01(result.confidence);
  if (result.pond_present === true && confidence >= CONFIRM_THRESHOLD) {
    return {
      status: "verified",
      message: "It was confirmed from your photos.",
      confidence,
      evidenceHashes: loaded.hashes,
    };
  }
  return {
    status: "rejected",
    message: shortReason(result.reason) || "No pond or tank with water is clearly visible in the photos.",
    confidence,
  };
}

// Ponds hidden by buildings: the photos must be real pond photos taken at the
// same place as the satellite image.
async function verifyEvidence(
  pond: Pond,
  paths: string[],
  admin: SupabaseClient,
  mark: (s: string) => void,
): Promise<Outcome> {
  const loaded = await loadEvidence(pond, paths, admin, mark);
  if ("rejected" in loaded) return loaded.rejected;
  const { photos, hashes } = loaded;

  mark("static-map");
  const satellite = await fetchSatellite(pond);
  mark("gemini-evidence");
  const result = await askModel(
    EVIDENCE_PROMPT,
    [satellite, ...photos],
    {
      photos_show_pond: { type: "BOOLEAN" },
      same_location: { type: "BOOLEAN" },
      confidence: { type: "NUMBER" },
      reason: { type: "STRING" },
    },
    ["photos_show_pond", "same_location", "confidence", "reason"],
  );
  const confidence = clamp01(result.confidence);

  if (result.photos_show_pond === true && result.same_location === true && confidence >= CONFIRM_THRESHOLD) {
    return {
      status: "verified",
      message: "Your photos match the satellite view of this location.",
      confidence,
      evidenceHashes: hashes,
    };
  }
  return {
    status: "rejected",
    message: shortReason(result.reason) ||
      (result.photos_show_pond === true
        ? "The photos don't appear to show the same place as the pinned location."
        : "The photos don't clearly show a pond."),
    confidence,
  };
}

async function verifyPhoto(pond: Pond, admin: SupabaseClient, mark: (s: string) => void): Promise<Outcome> {
  if (!pond.photo_path) return { status: "rejected", message: "No photo was uploaded for this pond." };
  mark("photo-download");
  const { data: blob, error } = await admin.storage.from("pond-photos").download(pond.photo_path);
  if (error || !blob) throw new Error(`photo download failed: ${error?.message ?? "no data"}`);
  const mediaType = blob.type || "image/jpeg";
  if (!ALLOWED_MEDIA_TYPES.has(mediaType) || blob.size > MAX_PHOTO_BYTES) {
    return { status: "rejected", message: "The photo must be a JPG, PNG or WebP under 3 MB." };
  }
  const bytes = new Uint8Array(await blob.arrayBuffer());
  const photoHash = await sha256Hex(bytes);

  mark("photo-duplicate-check");
  const { data: duplicate, error: dupError } = await admin
    .from("ponds").select("id").eq("photo_hash", photoHash).neq("id", pond.id).limit(1);
  if (dupError) throw dupError;
  if (duplicate && duplicate.length > 0) {
    return { status: "rejected", message: "This photo was already used to verify another pond." };
  }

  mark("gemini-photo");
  const result = await askModel(
    PHOTO_PROMPT,
    [{ mediaType, base64: toBase64(bytes) }],
    {
      pond_present: { type: "BOOLEAN" },
      confidence: { type: "NUMBER" },
      reason: { type: "STRING" },
    },
    ["pond_present", "confidence", "reason"],
  );
  const confidence = clamp01(result.confidence);
  if (result.pond_present === true && confidence >= CONFIRM_THRESHOLD) {
    return { status: "verified", message: "It was confirmed from your photo.", confidence, photoHash };
  }
  return {
    status: "rejected",
    message: shortReason(result.reason) || "No pond or tank with water is visible in the photo.",
    confidence,
  };
}

// Semaphore's plain SMS endpoint. Never throws: a failed text must not undo a
// finished verification.
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
      console.error("verify-pond: Semaphore rejected the SMS:", response.status, raw);
      return "failed";
    }
    return "sent";
  } catch (err) {
    console.error("verify-pond: SMS error:", err);
    return "failed";
  }
}

// ASCII only, so the text stays a single GSM-7 segment.
function smsName(name: string): string {
  const cleaned = name.replace(/[^\x20-\x7E]/g, "").replace(/"/g, "'").trim().slice(0, 30);
  return cleaned || "your pond";
}

async function runVerification(pond: Pond, admin: SupabaseClient, evidenceOnly: boolean) {
  let stage = "start";
  const mark = (s: string) => {
    stage = s;
    console.log(`verify-pond: pond=${pond.id} stage=${s}`);
  };

  const evidence = pond.evidence_photo_paths ?? [];
  const hasEvidence = evidence.length >= MIN_EVIDENCE_PHOTOS;
  let outcome: Outcome;
  try {
    if (pond.verification_method === "photo" && hasEvidence) {
      // In-house pond: its photos are the whole proof (no satellite check).
      outcome = await verifyPhotos(pond, evidence, admin, mark);
    } else if (hasEvidence && evidenceOnly) {
      // The pond was already waiting for photos and they just arrived.
      outcome = await verifyEvidence(pond, evidence, admin, mark);
    } else {
      outcome = pond.verification_method === "photo"
        ? await verifyPhoto(pond, admin, mark)
        : await verifySatellite(pond, mark);
      // Photos were sent up front and buildings hide the pond: compare them now
      // instead of asking the owner for photos they've already given.
      if (outcome.status === "needs_photos" && hasEvidence) {
        outcome = await verifyEvidence(pond, evidence, admin, mark);
      }
    }
  } catch (err) {
    // Full detail goes to the function logs only; the user gets a plain-language
    // reason (the raw upstream error is never shown or sent by SMS).
    console.error(`verify-pond: failed at stage=${stage}:`, err);
    outcome = {
      status: "error",
      message: err instanceof ModelBusyError
        ? "Our checking service is very busy right now."
        : "A technical problem stopped the check.",
    };
  }

  mark("save-result");
  const { error: updateError } = await admin.from("ponds").update({
    verification_status: outcome.status,
    verification_message: outcome.message,
    verification_confidence: outcome.confidence ?? null,
    ...(outcome.photoHash ? { photo_hash: outcome.photoHash } : {}),
    ...(outcome.evidenceHashes ? { evidence_photo_hashes: outcome.evidenceHashes } : {}),
  }).eq("id", pond.id);
  if (updateError) console.error("verify-pond: could not save result:", updateError);

  const name = pond.name;
  const copy = {
    verified: {
      title: "Pond verified",
      body: `"${name}" was verified. ${outcome.message} You can now monitor it.`,
      sms: `IsdaSafe: Your pond "${smsName(name)}" has been verified. You can now monitor it in the app.`,
    },
    rejected: {
      title: "Pond not verified",
      body: `We couldn't verify "${name}". ${outcome.message} You can add it again with a different pin or photos.`,
      sms: `IsdaSafe: We could not verify your pond "${smsName(name)}". Open the app for details.`,
    },
    error: {
      title: "Verification didn't finish",
      body: `We couldn't finish verifying "${name}". ${outcome.message} Open your dashboard and tap Retry.`,
      sms: `IsdaSafe: We could not finish verifying pond "${smsName(name)}". Please retry in the app.`,
    },
    needs_photos: {
      title: "Photos needed",
      body: `We need a little more to verify "${name}". ${outcome.message} Open your dashboard and tap Add photos.`,
      sms:
        `IsdaSafe: We need at least ${MIN_EVIDENCE_PHOTOS} photos of your pond "${smsName(name)}" to finish verifying it. Open the app to add them.`,
    },
  }[outcome.status];

  mark("notify");
  const { data: notification, error: notifyError } = await admin.from("notifications").insert({
    user_id: pond.user_id,
    pond_id: pond.id,
    type: `pond_${outcome.status}`,
    title: copy.title,
    body: copy.body,
  }).select("id").single();
  if (notifyError) console.error("verify-pond: could not create notification:", notifyError);

  mark("sms");
  const { data: profile } = await admin
    .from("profiles").select("phone, phone_verified").eq("id", pond.user_id).maybeSingle();
  const smsStatus = SMS_ENABLED && profile?.phone && profile.phone_verified
    ? await sendSms(profile.phone, copy.sms)
    : "skipped";
  if (notification) await admin.from("notifications").update({ sms_status: smsStatus }).eq("id", notification.id);
  console.log(`verify-pond: pond=${pond.id} done status=${outcome.status} sms=${smsStatus}`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);
  if (!GEMINI_API_KEY || !GOOGLE_MAPS_STATIC_API_KEY) {
    const missing = [!GEMINI_API_KEY && "GEMINI_API_KEY", !GOOGLE_MAPS_STATIC_API_KEY && "GOOGLE_MAPS_STATIC_API_KEY"]
      .filter(Boolean).join(", ");
    console.error(`verify-pond: missing secrets: ${missing}`);
    return jsonResponse({ error: `Pond verification isn't set up yet (missing secret: ${missing}).` }, 500);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "Missing Authorization header." }, 401);
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return jsonResponse({ error: "Invalid Supabase session." }, 401);
  const userId = userData.user.id;

  let pondId: unknown;
  let photoPaths: unknown;
  try {
    ({ pond_id: pondId, photo_paths: photoPaths } = await req.json());
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  if (typeof pondId !== "string") return jsonResponse({ error: "pond_id is required." }, 400);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  try {
    const { data: pond, error: pondError } = await admin
      .from("ponds")
      .select(
        "id, user_id, name, latitude, longitude, verification_method, verification_status, verification_started_at, photo_path, evidence_photo_paths",
      )
      .eq("id", pondId)
      .maybeSingle();
    if (pondError) throw pondError;
    // Same response for "missing" and "someone else's" so ids can't be probed.
    if (!pond || pond.user_id !== userId) return jsonResponse({ error: "Pond not found." }, 404);
    if (typeof pond.latitude !== "number" || typeof pond.longitude !== "number") {
      return jsonResponse({ error: "This pond has no location to verify." }, 400);
    }

    let evidencePaths: string[] | null = null;
    if (photoPaths !== undefined) {
      // Either the photos we asked for (needs_photos), or photos sent along
      // with the first request (pending) for use if buildings hide the pond.
      if (pond.verification_status !== "needs_photos" && pond.verification_status !== "pending") {
        return jsonResponse({ error: "This pond isn't waiting for photos." }, 409);
      }
      const folder = `${userId}/${pond.id}/`;
      if (
        !Array.isArray(photoPaths) ||
        photoPaths.length < MIN_EVIDENCE_PHOTOS || photoPaths.length > MAX_EVIDENCE_PHOTOS ||
        new Set(photoPaths).size !== photoPaths.length ||
        !photoPaths.every((p) => typeof p === "string" && p.startsWith(folder) && !p.includes(".."))
      ) {
        return jsonResponse(
          { error: `Send between ${MIN_EVIDENCE_PHOTOS} and ${MAX_EVIDENCE_PHOTOS} different photos of the pond.` },
          400,
        );
      }
      evidencePaths = photoPaths as string[];
    } else if (pond.verification_status !== "pending" && pond.verification_status !== "error") {
      return jsonResponse({ status: pond.verification_status });
    }
    // Retries (e.g. from a "taking long?" button) mustn't start a second run
    // on top of one that's still going.
    if (
      pond.verification_status === "pending" && pond.verification_started_at &&
      Date.now() - new Date(pond.verification_started_at).getTime() < RUN_WINDOW_MS
    ) {
      return jsonResponse({ status: "pending" });
    }
    // Only a pond already waiting for photos skips the satellite check.
    const evidenceOnly = pond.verification_status === "needs_photos";

    const since = new Date(Date.now() - 3600_000).toISOString();
    const { count, error: countError } = await admin
      .from("pond_verification_log")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .gte("created_at", since);
    if (countError) throw countError;
    if ((count ?? 0) >= HOURLY_MAX) {
      return jsonResponse({ error: "Too many verification attempts. Please try again in an hour." }, 429);
    }
    const { error: logError } = await admin
      .from("pond_verification_log")
      .insert({ user_id: userId, mode: pond.verification_method === "photo" ? "photo" : "satellite" });
    if (logError) throw logError;

    await admin.from("ponds").update({
      verification_status: "pending",
      verification_message: null,
      verification_started_at: new Date().toISOString(),
      ...(evidencePaths ? { evidence_photo_paths: evidencePaths } : {}),
    }).eq("id", pond.id);

    const toVerify: Pond = {
      ...(pond as Pond),
      evidence_photo_paths: evidencePaths ?? (pond.evidence_photo_paths as string[] | null),
    };
    // Reply now; the check itself continues after the response is sent.
    EdgeRuntime.waitUntil(runVerification(toVerify, admin, evidenceOnly));
    return jsonResponse({ status: "pending" }, 202);
  } catch (err) {
    console.error("verify-pond: could not start verification:", err);
    const detail = err instanceof Error ? err.message : JSON.stringify(err);
    return jsonResponse({ error: `Could not start verification: ${detail.slice(0, 200)}` }, 500);
  }
});
