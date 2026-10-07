// Feeding plan + water quality advice + risks for one species under a pond's
// current readings. Replaces the Render-hosted POST /feeding-recommendation.
//
// Request:  { species, temperature, ph, dissolved_oxygen, ammonia, language? }
//           language "tl" = write all text in Tagalog (default English).
// Response: { feeding_time, feeding_frequency, feeding_amount,
//             water_quality_recommendations: string[], possible_risks: string[] }
//
// Models are tried in order; a rate-limited (429) or unavailable model moves on
// to the next one, and a 429 model is skipped for a minute. Responses are cached
// for 15 minutes per species + rounded readings (per function instance).
//
// Secrets: GEMINI_API_KEY (shared). Optional GEMINI_MODELS (comma-separated chain)
// or GEMINI_MODEL / GEMINI_FALLBACK_MODEL. Calls need a valid Supabase session.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const MODELS: string[] = (
  Deno.env.get("GEMINI_MODELS")?.split(",").map((m) => m.trim()).filter(Boolean) ?? [
    Deno.env.get("GEMINI_MODEL") ?? "gemini-3.8-flash",
    Deno.env.get("GEMINI_FALLBACK_MODEL") ?? "gemini-3.7-flash",
  ]
).filter((m, i, all) => all.indexOf(m) === i);
const ATTEMPTS_PER_MODEL = 2;
const SERVER_ERROR_STATUSES = new Set([500, 502, 503, 504]);
const RATE_LIMIT_COOLDOWN_MS = 60_000;
const coolingDownUntil = new Map<string, number>();

const CACHE_TTL_MS = 15 * 60_000;
const CACHE_MAX_ENTRIES = 200;
const cache = new Map<string, { expires: number; value: Recommendation }>();

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Recommendation = {
  feeding_time: string;
  feeding_frequency: string;
  feeding_amount: string;
  water_quality_recommendations: string[];
  possible_risks: string[];
};

type Input = {
  species: string;
  temperature: number;
  ph: number;
  dissolved_oxygen: number;
  ammonia: number;
  language: "en" | "tl";
};

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    feeding_time: { type: "STRING", description: "Recommended time(s) of day to feed" },
    feeding_frequency: { type: "STRING", description: "How often to feed (times per day/week)" },
    feeding_amount: { type: "STRING", description: "Recommended feed amount/portion guidance" },
    water_quality_recommendations: {
      type: "ARRAY",
      items: { type: "STRING" },
      description: "Actionable water quality recommendations",
    },
    possible_risks: {
      type: "ARRAY",
      items: { type: "STRING" },
      description: "Possible risks given the current readings/species",
    },
  },
  required: [
    "feeding_time",
    "feeding_frequency",
    "feeding_amount",
    "water_quality_recommendations",
    "possible_risks",
  ],
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const isStringList = (v: unknown): v is string[] => Array.isArray(v) && v.every((s) => typeof s === "string");

function isRecommendation(v: unknown): v is Recommendation {
  const r = v as Recommendation;
  return !!r && typeof r.feeding_time === "string" && typeof r.feeding_frequency === "string" &&
    typeof r.feeding_amount === "string" && isStringList(r.water_quality_recommendations) &&
    isStringList(r.possible_risks);
}

function parseInput(body: Record<string, unknown>): Input | null {
  const species = typeof body.species === "string" ? body.species.trim().slice(0, 80) : "";
  const nums = ["temperature", "ph", "dissolved_oxygen", "ammonia"].map((k) => body[k]);
  if (!species || !nums.every((n) => typeof n === "number" && Number.isFinite(n))) return null;
  const [temperature, ph, dissolved_oxygen, ammonia] = nums as number[];
  const language = body.language === "tl" ? "tl" : "en";
  return { species, temperature, ph, dissolved_oxygen, ammonia, language };
}

const round = (n: number, digits: number) => n.toFixed(digits);
const cacheKey = (d: Input) =>
  [d.species, round(d.temperature, 1), round(d.ph, 2), round(d.dissolved_oxygen, 2), round(d.ammonia, 3), d.language].join("|");

function buildPrompt(d: Input): string {
  return (
    "You are an aquaculture expert advising a small-scale fish farmer. " +
    "Given the species and current water sensor readings below, provide practical, " +
    "specific feeding and water-quality guidance.\n\n" +
    `Species: ${d.species}\n` +
    `Water temperature: ${d.temperature} C\n` +
    `pH: ${d.ph}\n` +
    `Dissolved oxygen: ${d.dissolved_oxygen} mg/L\n` +
    `Ammonia: ${d.ammonia} mg/L\n` +
    (d.language === "tl"
      ? "\nWrite ALL text values in natural Tagalog (Filipino). Keep technical terms (pH, ammonia, dissolved oxygen), numbers and units as they are.\n"
      : "")
  );
}

async function askGemini(d: Input): Promise<Recommendation> {
  const body = JSON.stringify({
    contents: [{ role: "user", parts: [{ text: buildPrompt(d) }] }],
    generationConfig: { responseMimeType: "application/json", responseSchema: RESPONSE_SCHEMA },
  });

  const now = Date.now();
  const available = MODELS.filter((m) => (coolingDownUntil.get(m) ?? 0) <= now);
  const models = available.length ? available : MODELS;
  let lastError = "no models configured";

  for (const model of models) {
    for (let attempt = 0; attempt < ATTEMPTS_PER_MODEL; attempt++) {
      if (attempt > 0) await sleep(1200 * attempt);
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
        lastError = `${model} unreachable: ${err}`;
        console.warn(`feeding-recommendation: ${lastError}`);
        continue;
      }
      const raw = await response.text();
      if (response.ok) {
        try {
          const text = JSON.parse(raw).candidates?.[0]?.content?.parts?.[0]?.text ?? "";
          const parsed = JSON.parse(text);
          if (isRecommendation(parsed)) return parsed;
          lastError = `${model} returned an unexpected shape`;
        } catch {
          lastError = `${model} returned unparseable output`;
        }
        console.warn(`feeding-recommendation: ${lastError}`);
        break;
      }
      lastError = `${model} HTTP ${response.status}: ${raw.slice(0, 200)}`;
      console.warn(`feeding-recommendation: ${lastError}`);
      if (response.status === 429) coolingDownUntil.set(model, Date.now() + RATE_LIMIT_COOLDOWN_MS);
      if (!SERVER_ERROR_STATUSES.has(response.status)) break;
    }
  }
  throw new Error(lastError);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);
  if (!GEMINI_API_KEY) {
    console.error("feeding-recommendation: missing GEMINI_API_KEY");
    return jsonResponse({ error: "Feeding advice isn't set up yet." }, 500);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "Missing Authorization header." }, 401);
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return jsonResponse({ error: "Invalid Supabase session." }, 401);

  let input: Input | null;
  try {
    input = parseInput(await req.json());
  } catch {
    return jsonResponse({ error: "Invalid JSON body." }, 400);
  }
  if (!input) {
    return jsonResponse({ error: "species, temperature, ph, dissolved_oxygen and ammonia are required." }, 400);
  }

  const key = cacheKey(input);
  const cached = cache.get(key);
  if (cached && cached.expires > Date.now()) return jsonResponse(cached.value);

  try {
    const value = await askGemini(input);
    if (cache.size >= CACHE_MAX_ENTRIES) cache.delete(cache.keys().next().value!);
    cache.set(key, { expires: Date.now() + CACHE_TTL_MS, value });
    return jsonResponse(value);
  } catch (err) {
    console.error("feeding-recommendation:", err);
    return jsonResponse({ error: "The advisor is busy right now. Please try again." }, 503);
  }
});
