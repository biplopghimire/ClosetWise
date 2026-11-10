// Authenticated proxy to the Gemini API. The API key never ships in the iOS app.
//
// POST /functions/v1/gemini
//   { "action": "attributes", "image_base64": "...", "mime_type": "image/jpeg" }
//     → { attributes: { name, category, subcategory, color, pattern, material, fit, silhouette, style, formality, seasons } }
//   { "action": "embed", "image_base64": "...", "mime_type": "image/jpeg" }
//     → { embedding: number[768] }
//   { "action": "style_summary", "profile": StyleContext, "inspiration_images": ["<base64 jpeg>", …] }
//     → { summary, tags, fit_notes }   (also upserted into style_profiles for this user)
//   { "action": "judge_purchase", product, price, similar[], compatible[], outfit_count, new_outfit_count,
//     style_fit, style_reasons[], local_verdict, profile: StyleContext, image_base64? }
//     → { verdict, explanation, style_notes }
//   { "action": "detect_outfit", image_base64, closet: [{ id, name, category, color, fit, silhouette }] }
//     → { matches: [{ item_id, confidence }], not_in_closet: [string] }
//
// Secrets: GEMINI_API_KEY (required), GEMINI_FLASH_MODEL, GEMINI_EMBED_MODEL (optional overrides).

import { createClient } from "jsr:@supabase/supabase-js@2";

const API = "https://generativelanguage.googleapis.com/v1beta/models";
const FLASH = Deno.env.get("GEMINI_FLASH_MODEL") ?? "gemini-3.8-flash";
const EMBED = Deno.env.get("GEMINI_EMBED_MODEL") ?? "gemini-embedding-2";
const EMBED_DIMS = 768; // must match vector(768) in the migration

/** Must match the `fit_type` enum in the database and `FitType` in the iOS app. */
const FITS = ["tight", "fitted", "regular", "relaxed", "loose", "oversized"];

const ATTRIBUTE_SCHEMA = {
  type: "object",
  properties: {
    name: { type: "string", description: "Short name, e.g. 'Black ribbed top'" },
    category: { type: "string", enum: ["top", "bottom", "outerwear", "dress", "shoes", "accessory"] },
    subcategory: { type: "string" },
    color: { type: "string" },
    pattern: { type: "string" },
    material: { type: "string" },
    fit: {
      type: "string",
      enum: FITS,
      description: "How the piece sits on the body: tight (hugs), fitted (follows shape), regular (true to size), relaxed (a little room), loose (roomy, drapes away), oversized (intentionally big).",
    },
    silhouette: { type: "string", description: "Cut or shape, e.g. wide-leg, straight, skinny, cropped, A-line, boxy, longline." },
    style: { type: "string" },
    formality: { type: "integer", minimum: 1, maximum: 5 },
    seasons: { type: "array", items: { type: "string", enum: ["spring", "summer", "fall", "winter"] } },
  },
  required: ["name", "category", "color", "material", "fit", "silhouette", "style", "formality", "seasons"],
};

const STYLE_SCHEMA = {
  type: "object",
  properties: {
    summary: { type: "string", description: "2–3 sentences, second person, specific and warm. No shopping advice." },
    tags: { type: "array", items: { type: "string" }, maxItems: 6, description: "Short style tags, 1–3 words each, Title Case." },
    fit_notes: { type: "string", description: "One sentence on the fits and silhouettes they gravitate to." },
  },
  required: ["summary", "tags", "fit_notes"],
};

const STYLE_PROMPT = `You are a personal stylist reading a client's style profile.
"stated" is what they told us about their style. "learned" is computed from outfits they actually logged
(shares are recency-weighted, loved outfits count more). Inspiration photos, if any, are looks they're drawn to.
Describe their real style in plain language. Where stated and learned disagree, say so gently
(e.g. they want to dress more polished than they currently do). Mention fit and silhouette specifically.`;

const JUDGE_SCHEMA = {
  type: "object",
  properties: {
    verdict: { type: "string", enum: ["Adds value", "Consider", "Limited gain", "Probably skip"] },
    explanation: { type: "string", description: "2–3 sentences, second person, cites specific owned pieces by name. Never pushy." },
    style_notes: { type: "string", description: "One sentence on how this piece fits their style (fit, silhouette, colour, vibe)." },
  },
  required: ["verdict", "explanation", "style_notes"],
};

const JUDGE_PROMPT = `You help someone decide whether a clothing item is worth buying, given what they already own and their style.
You get the candidate item (and a photo if available), the closest pieces they already own with an attribute similarity score
(0-1; 0.85+ is nearly identical), the owned pieces that pair with it, how many outfits it makes (and how many are new
versus what the closest duplicate already makes), a style-fit score with reasons, and their style profile
("stated" = what they told us, "learned" = from logged outfits). Check the evidence: if the photo or attributes show a
similar item isn't really interchangeable (different neckline, length, occasion), say so. Weigh their fit preferences
(tight/fitted/regular/relaxed/loose/oversized) and silhouettes seriously. They make the final call: inform, don't decide.`;

const OUTFIT_SCHEMA = {
  type: "object",
  properties: {
    matches: {
      type: "array",
      description: "Closet items visibly worn in the photo. Only ids from the closet list.",
      items: {
        type: "object",
        properties: { item_id: { type: "string" }, confidence: { type: "number", minimum: 0, maximum: 1 } },
        required: ["item_id", "confidence"],
      },
    },
    not_in_closet: {
      type: "array",
      description: "Garments worn in the photo that match nothing in the closet, e.g. 'grey crew socks'.",
      items: { type: "string" },
    },
  },
  required: ["matches", "not_in_closet"],
};

const OUTFIT_PROMPT = `This is a photo of someone's outfit (mirror selfie, flat lay, or clothes laid out).
Identify each garment and match it to the user's closet list below by id. Match on category, colour, fit and cut;
only match when you are reasonably sure it is that exact piece, at most one item per garment.
List worn garments that are not in the closet separately. Ignore accessories unless they are in the closet.`;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

/** Thrown when Gemini stays overloaded or slow after retries; mapped to HTTP 503 for the app. */
class GeminiBusy extends Error {}

const ATTEMPT_TIMEOUT_MS = 25_000;
const MAX_ATTEMPTS = 2;  // 2 × 25 s + backoff stays under the app's 60 s request timeout

/** Calls Gemini, retrying overloads (429/500/503) and timeouts with backoff. */
async function gemini(model: string, method: string, body: unknown) {
  let last = "";
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, 1500 * 2 ** (attempt - 1) + Math.random() * 500));
    try {
      const res = await fetch(`${API}/${model}:${method}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": Deno.env.get("GEMINI_API_KEY")! },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(ATTEMPT_TIMEOUT_MS),
      });
      if (res.ok) return res.json();
      last = `${res.status}: ${(await res.text()).slice(0, 300)}`;
      if (![429, 500, 503].includes(res.status)) throw new Error(`Gemini ${last}`);
    } catch (e) {
      if (e instanceof DOMException && (e.name === "TimeoutError" || e.name === "AbortError")) { last = "timeout"; continue; }
      throw e;
    }
  }
  throw new GeminiBusy(`Gemini busy after ${MAX_ATTEMPTS} attempts (${last})`);
}

async function generateJSON(parts: unknown[], schema: unknown) {
  const out = await gemini(FLASH, "generateContent", {
    contents: [{ role: "user", parts }],
    generationConfig: { responseMimeType: "application/json", responseJsonSchema: schema },
  });
  return JSON.parse(out.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  // Require a signed-in Supabase user; queries below run as that user (RLS applies).
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);

  try {
    const body = await req.json();
    const { action } = body;

    if (action === "style_summary") {
      const images: string[] = (body.inspiration_images ?? []).slice(0, 6);
      const parts = [
        { text: STYLE_PROMPT },
        { text: `Profile JSON:\n${JSON.stringify(body.profile ?? {})}` },
        ...images.map((data) => ({ inline_data: { mime_type: "image/jpeg", data } })),
      ];
      const result = await generateJSON(parts, STYLE_SCHEMA);
      await supabase.from("style_profiles").upsert({
        user_id: user.id,
        preferences: body.profile?.stated ?? {},
        learned: body.profile?.learned ?? {},
        summary: result.summary,
        tags: result.tags,
        fit_notes: result.fit_notes,
        updated_at: new Date().toISOString(),
      });
      return json(result);
    }

    if (action === "detect_outfit") {
      const closet = (body.closet ?? []).slice(0, 200);
      if (!body.image_base64) return json({ error: "image_base64 required" }, 400);
      const result = await generateJSON([
        { text: OUTFIT_PROMPT },
        { text: `Closet JSON:\n${JSON.stringify(closet)}` },
        { inline_data: { mime_type: body.mime_type ?? "image/jpeg", data: body.image_base64 } },
      ], OUTFIT_SCHEMA);
      const known = new Set(closet.map((c: { id: string }) => c.id));
      result.matches = (result.matches ?? []).filter((m: { item_id: string }) => known.has(m.item_id));
      return json(result);
    }

    if (action === "judge_purchase") {
      const { image_base64: photo, action: _a, ...evidence } = body;
      const parts: unknown[] = [{ text: JUDGE_PROMPT }, { text: `Evidence JSON:\n${JSON.stringify(evidence)}` }];
      if (photo) parts.push({ inline_data: { mime_type: "image/jpeg", data: photo } });
      return json(await generateJSON(parts, JUDGE_SCHEMA));
    }

    const { image_base64, mime_type = "image/jpeg" } = body;
    if (!image_base64) return json({ error: "image_base64 required" }, 400);
    const image = { inline_data: { mime_type, data: image_base64 } };

    if (action === "attributes") {
      const attributes = await generateJSON(
        [image, { text: "Identify this single clothing item. Fill every field; use common, lowercase fashion terms. Judge fit from how the fabric sits, not the size label." }],
        ATTRIBUTE_SCHEMA,
      );
      return json({ attributes });
    }

    if (action === "embed") {
      const out = await gemini(EMBED, "embedContent", {
        content: { parts: [image] },
        output_dimensionality: EMBED_DIMS,
      });
      const values = out.embedding?.values ?? out.embeddings?.[0]?.values;
      return json({ embedding: values });
    }

    return json({ error: `unknown action: ${action}` }, 400);
  } catch (e) {
    console.error(String(e));
    if (e instanceof GeminiBusy) return json({ error: "gemini_busy", detail: e.message }, 503);
    return json({ error: String(e) }, 502);
  }
});
