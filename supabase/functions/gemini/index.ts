// Authenticated proxy to the Gemini API.
//
// Bring your own key: each caller sends their own Gemini key in the `x-gemini-key` header
// (Settings → Gemini API key in the iOS app, kept in the Keychain). The key is used for that request only and is never
// stored or logged. Requests without the header fall back to the server's GEMINI_API_KEY only
// for signed-in users whose email is listed in SERVER_KEY_EMAILS; anyone else gets 400
// `missing_gemini_key`, so nobody can use the owner's quota by accident.
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
//   { "action": "read_product", page: { url, title, structured, meta, text }, image_base64? }
//     → { product: { is_product, name, brand, price, currency, ...attribute fields } }
//   { "action": "pair_pieces", locked: [piece], candidates: { slot: [piece] }, profile: StyleContext }
//     → { picks: [{ slot, item_ids: [string] }], note }
//   { "action": "pick_product_photo", name, category, images: ["<base64 jpeg>", …] }
//     → { index, shows, box_2d: [ymin, xmin, ymax, xmax] (0–1000) }
//
// Secrets (all optional): GEMINI_API_KEY + SERVER_KEY_EMAILS (comma-separated) for the owner fallback,
// GEMINI_FLASH_MODEL, GEMINI_EMBED_MODEL (model overrides).

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

/** A product page, read: the attribute fields plus what only the listing knows. */
const PRODUCT_SCHEMA = {
  type: "object",
  properties: {
    is_product: {
      type: "boolean",
      description: "true only if this is one clothing, shoe or accessory product. false for blocked pages, captchas, search or category pages, carts, non-fashion products.",
    },
    not_product_reason: { type: "string", description: "If is_product is false: blocked, captcha, category, search, not_fashion, or other." },
    name: { type: "string", description: "The product's own name, short, without the store name or SEO filler, e.g. 'Relaxed linen shirt'." },
    brand: { type: "string" },
    price: { type: "number", description: "Current selling price as a number (sale price if on sale). 0 if unknown." },
    currency: { type: "string", description: "ISO currency code, e.g. USD." },
    ...ATTRIBUTE_SCHEMA.properties,
  },
  required: [...new Set(["is_product", "name", "price", "currency", ...ATTRIBUTE_SCHEMA.required])],
};

const PRODUCT_PROMPT = `You are reading an online store's product page for a shopper who wants to know how the item
fits their existing wardrobe. Below is what their phone read from the page: structured data (schema.org JSON-LD),
meta tags, and the visible text. If a photo is attached it is the product's main image.
Extract the single product being sold. Use the structured data for name, brand and price when present;
otherwise read them from the text. Take colour and material from the selected variant or description.
Judge fit and silhouette from the description and photo (words like oversized, relaxed, slim, boxy, cropped, wide-leg)
rather than from size labels. If the page is an access-denied/robot check, a search or category listing,
or not a fashion item, set is_product to false. Use common, lowercase fashion terms.`;

/** Which listing photo to keep for the closet, and where the item is in it. */
const PHOTO_SCHEMA = {
  type: "object",
  properties: {
    index: { type: "integer", description: "0-based index of the chosen photo." },
    shows: {
      type: "string",
      enum: ["item_only", "on_model", "detail", "other"],
      description: "item_only: flat lay, on a hanger, ghost mannequin or packshot. on_model: worn by a person.",
    },
    box_2d: {
      type: "array",
      items: { type: "integer" },
      minItems: 4,
      maxItems: 4,
      description: "[ymin, xmin, ymax, xmax] on a 0–1000 scale around just this item (not the whole person or other garments).",
    },
  },
  required: ["index", "shows", "box_2d"],
};

const PHOTO_PROMPT = `These photos come from an online store's listing. The shopper bought the item described below
and wants one clean picture of it for their digital closet.
Pick the photo that shows this item by itself — a flat lay, on a hanger, on a ghost mannequin or a packshot —
from the front, whole and in focus. Skip close-ups of fabric or labels, and photos of other products.
If every photo is on a model, pick the one where this item is most fully visible and least covered.
Then give box_2d around just this item in that photo (for a shirt on a model: the shirt, not the trousers or the face).`;

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

const PAIR_PROMPT = `You are a personal stylist working only with clothes this person already owns.
They locked one or more pieces and want the best pieces to wear with them.
For each slot in "candidates", pick up to 2 item ids (best first) that make the strongest outfit with the locked pieces,
judged on colour, proportion and silhouette, how dressed-up the pieces are, and this person's style profile.
Only use ids from the candidates. Skip a slot if nothing there works. Then write one short sentence (max 18 words)
on why the top picks work, in second person, naming the pieces in plain words.`;

const PAIR_SCHEMA = {
  type: "object",
  properties: {
    picks: {
      type: "array",
      items: {
        type: "object",
        properties: {
          slot: { type: "string", enum: ["layer", "top", "dress", "bottom", "shoes", "accessory"] },
          item_ids: { type: "array", items: { type: "string" } },
        },
        required: ["slot", "item_ids"],
      },
    },
    note: { type: "string" },
  },
  required: ["picks", "note"],
};

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
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-gemini-key",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

/** The caller's own key from `x-gemini-key`, else the server key for allow-listed emails, else null. */
function geminiKey(req: Request, email: string | undefined): string | null {
  const own = req.headers.get("x-gemini-key")?.trim();
  if (own) return own;
  const allowed = (Deno.env.get("SERVER_KEY_EMAILS") ?? "").split(",").map((e) => e.trim().toLowerCase()).filter(Boolean);
  const serverKey = Deno.env.get("GEMINI_API_KEY");
  return serverKey && email && allowed.includes(email.toLowerCase()) ? serverKey : null;
}

/** Thrown when Gemini stays overloaded or slow after retries; mapped to HTTP 503 for the app. */
class GeminiBusy extends Error {}

const ATTEMPT_TIMEOUT_MS = 25_000;
const MAX_ATTEMPTS = 2;  // 2 × 25 s + backoff stays under the app's 60 s request timeout

/** Calls Gemini, retrying overloads (429/500/503) and timeouts with backoff. */
async function gemini(key: string, model: string, method: string, body: unknown) {
  let last = "";
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, 1500 * 2 ** (attempt - 1) + Math.random() * 500));
    try {
      const res = await fetch(`${API}/${model}:${method}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": key },
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

async function generateJSON(key: string, parts: unknown[], schema: unknown) {
  const out = await gemini(key, FLASH, "generateContent", {
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

  const key = geminiKey(req, user.email);
  if (!key) {
    return json({
      error: "missing_gemini_key",
      detail: "Add your Gemini API key in the app: Settings → Gemini API key.",
    }, 400);
  }

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
      const result = await generateJSON(key, parts, STYLE_SCHEMA);
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
      const result = await generateJSON(key, [
        { text: OUTFIT_PROMPT },
        { text: `Closet JSON:\n${JSON.stringify(closet)}` },
        { inline_data: { mime_type: body.mime_type ?? "image/jpeg", data: body.image_base64 } },
      ], OUTFIT_SCHEMA);
      const known = new Set(closet.map((c: { id: string }) => c.id));
      result.matches = (result.matches ?? []).filter((m: { item_id: string }) => known.has(m.item_id));
      return json(result);
    }

    if (action === "read_product") {
      const page = body.page ?? {};
      const trimmed = {
        url: String(page.url ?? "").slice(0, 500),
        title: String(page.title ?? "").slice(0, 300),
        structured: (page.structured ?? []).slice(0, 4).map((s: string) => String(s).slice(0, 6000)),
        meta: page.meta ?? {},
        text: String(page.text ?? "").slice(0, 8000),
      };
      const parts: unknown[] = [{ text: PRODUCT_PROMPT }, { text: `Page JSON:\n${JSON.stringify(trimmed)}` }];
      if (body.image_base64) parts.push({ inline_data: { mime_type: body.mime_type ?? "image/jpeg", data: body.image_base64 } });
      return json({ product: await generateJSON(key, parts, PRODUCT_SCHEMA) });
    }

    if (action === "pick_product_photo") {
      const images: string[] = (body.images ?? []).slice(0, 8);
      if (images.length === 0) return json({ error: "images required" }, 400);
      const parts: unknown[] = [
        { text: PHOTO_PROMPT },
        { text: `Item: ${String(body.name ?? "").slice(0, 200)} (${String(body.category ?? "")})` },
      ];
      images.forEach((data, i) => {
        parts.push({ text: `Photo ${i}:` });
        parts.push({ inline_data: { mime_type: "image/jpeg", data } });
      });
      const result = await generateJSON(key, parts, PHOTO_SCHEMA);
      result.index = Math.min(Math.max(0, Number(result.index) || 0), images.length - 1);
      return json(result);
    }

    if (action === "pair_pieces") {
      const parts = [
        { text: PAIR_PROMPT },
        { text: `Locked JSON:\n${JSON.stringify(body.locked ?? [])}` },
        { text: `Candidates JSON:\n${JSON.stringify(body.candidates ?? {})}` },
        { text: `Profile JSON:\n${JSON.stringify(body.profile ?? {})}` },
      ];
      return json(await generateJSON(key, parts, PAIR_SCHEMA));
    }

    if (action === "judge_purchase") {
      const { image_base64: photo, action: _a, ...evidence } = body;
      const parts: unknown[] = [{ text: JUDGE_PROMPT }, { text: `Evidence JSON:\n${JSON.stringify(evidence)}` }];
      if (photo) parts.push({ inline_data: { mime_type: "image/jpeg", data: photo } });
      return json(await generateJSON(key, parts, JUDGE_SCHEMA));
    }

    const { image_base64, mime_type = "image/jpeg" } = body;
    if (!image_base64) return json({ error: "image_base64 required" }, 400);
    const image = { inline_data: { mime_type, data: image_base64 } };

    if (action === "attributes") {
      const attributes = await generateJSON(key,
        [image, { text: "Identify this single clothing item. Fill every field; use common, lowercase fashion terms. Judge fit from how the fabric sits, not the size label." }],
        ATTRIBUTE_SCHEMA,
      );
      return json({ attributes });
    }

    if (action === "embed") {
      const out = await gemini(key, EMBED, "embedContent", {
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
