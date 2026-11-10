# ClosetWise — Implementation Plan

A native iOS app (SwiftUI) that checks a potential purchase against the user's existing wardrobe:
duplicates, compatibility, and estimated cost per wear. The user always makes the final call.

Sources: `project_context/Project Write Up A4.md`, `project_context/Wardrobe Shopping App Presentation (1).pdf`,
and the Figma wireframes (screens 0–7).

## Architecture

```
SwiftUI app (iOS 17+)  ── supabase-swift ──►  Supabase (new project, dedicated to ClosetWise)
  • Vision: background removal          │       • Postgres + pgvector (items, outfits, wear_events, purchase_checks)
  • Vision: receipt OCR fallback        │       • Storage buckets: items, outfits, receipts, checks
  • URLSession: product link fetch      │       • Auth (email magic link / Sign in with Apple)
  • Share Extension                     └──►    • Edge Function `gemini` → Gemini API (key stays server-side)
```

Models (configurable via Edge Function secrets):
- `gemini-3.8-flash` — attribute extraction, receipt parsing, compatibility judgment, explanations
- `gemini-embedding-2` at 768 dims — multimodal image embeddings stored in pgvector

## Screens (from wireframes)

| # | Screen | SwiftUI view |
|---|--------|--------------|
| 0 | Home | `HomeView` |
| 1 | Add item | `AddItemView` |
| 2 | Review details | `ReviewDetailsView` |
| 3 | Wardrobe | `WardrobeView` |
| 4 | Check a purchase | `CheckPurchaseView` |
| 5 | Purchase check results | `PurchaseResultView` |
| 6 | Works with N items | `CompatibleItemsView` |
| 7 | Today's outfit | `LogOutfitView` |

Tabs: Home · Wardrobe · Add · Check.

## Phases

### Phase 0 — Foundations ✅ scaffolded
- Xcode project via XcodeGen (`ios/project.yml`), theme tokens, tab shell, static versions of screens with sample data.
- `supabase/migrations/…_init.sql`: tables, RLS, pgvector + HNSW index, storage buckets, `match_items` RPC.
- `supabase/functions/gemini`: authenticated proxy with `attributes` and `embed` actions.

### Phase 1 — Build your closet (screens 1–3)
- PhotosPicker / camera → resize to ~1024 px → Vision `VNGenerateForegroundInstanceMaskRequest` cut-out (fallback: original).
- Upload to Storage → `gemini` `attributes` → editable Review screen → save → `embed` → insert `items` row.
- Wardrobe grid with category filters, backed by Supabase.

### Phase 2 — Purchase check (screens 4–6)
- On-device link fetch: schema.org `Product` JSON-LD, then Open Graph tags. Screenshot fallback.
- Edge Function `check`:
  - Duplicates: `match_items` RPC (same category, top-k cosine) + score `0.6·cos + 0.2·color + 0.1·fit + 0.1·style`.
  - Compatibility: role table (top → bottoms/outerwear/shoes), season + formality (±1) filter, one batched Gemini judgment; outfit count = valid top+bottom+shoes combos with the new item.
  - Cost per wear: `price ÷ (category wear rate × assumed lifetime)`, default rate on cold start, labeled "estimated".
  - Verdict label + Gemini explanation.
- Results cards, compatible-items screen, Skip / Buy anyway → saves `decision`.

### Phase 3 — Wear tracking & Home (screens 0, 7)
- Outfit photo → Gemini garment detection → per-garment vector match → user confirms → `wear_events`.
- Week strip, OOTD calendar; Home stats (items, avg cost per wear, checks this month, $ saved by skipping, most worn, unworn 60+ days).

### Style profile ✅ built (local) — Gemini summary needs Supabase + sign-in
- Every item has a `fit` (tight · fitted · regular · relaxed · loose · oversized) plus a free-text `silhouette`
  (wide-leg, cropped, A-line…). Gemini fills both; the user confirms on the Review screen.
- **Learned style** (`StyleLearner`): from logged outfits, recency-weighted (30-day half-life), loved ×1.6 —
  colour mix, fit share per category, silhouettes, typical dressiness, signature pieces, loved top+bottom pairs, tags.
- **Stated style** (`StylePreferences`, Style screen): vibes, "in your words", preferred fit per category,
  colours loved/avoided, dressiness, occasions, up to 6 inspiration photos.
- Logging an outfit (with Love it / It's fine / Not me) bumps wear counts and re-learns the profile;
  suggested outfits can be worn, loved, or dismissed ("Not for me" stops suggesting that combination).
- Outfit suggestions score fit/colour/dressiness against both stated and learned style.
- `StyleContext` (stated + learned JSON) is what Gemini sees: `gemini` `style_summary` action writes a summary,
  tags and fit notes and saves them to `style_profiles`; purchase checks and outfit judgment will send it too.
- DB: migration `20261109010000_style_profile.sql` (fit enum, silhouette, outfit reactions, style_profiles,
  style_inspirations, inspiration bucket).

### Purchase check ✅ built (on-device engine + tests) — Gemini second opinion needs Supabase + sign-in
- **Inputs:** product link (JSON-LD → Open Graph, on device), photo (camera or library; Vision cut-out,
  colour read from the photo ignoring the background, Gemini attributes when connected), or manual entry.
  Every path lands on a *Confirm the item* screen (type, colour, fit, cut, fabric, dressiness, price, store).
- **Duplicates** (`PurchaseCheckEngine.similarity`): type 25% · colour (CIE Lab ΔE) 30% · fit 15% · cut 12% ·
  fabric 8% · dressiness 10%; clearly different colours ×0.85. ≥0.85 nearly identical, ≥0.70 very similar, ≥0.58 similar.
  Shows reasons ("same colour, same fit") and how often each similar piece is worn.
- **Compatibility:** partner categories → pairwise rules (dressiness gap, clashing colours, volume balance) →
  complete outfits (top+bottom+shoes) and *new* outfits vs. what the closest duplicate already makes.
- **Style fit (0–100):** stated fit preference, learned fit share, usual cut, loved/avoided colours,
  colours worn, dressiness, vibes, and phrases from "in your words" — each shown as a ✓/✗ reason.
- **Cost per wear:** price ÷ (median category wears × style factor × duplicate split × compatibility) over 2 years.
- Verdict label + explanation; Gemini `judge_purchase` rewrites it with the photo and full style profile when connected.
- Skip / Buy anyway saved to history (Home stats: checks this month, $ saved by skipping); buying adds the item to the closet.
- `ClosetWiseTests` (19 tests): duplicate detection, false positives, symmetry, clashing colours, style-fit
  from learned and stated style, link parsing, colour maths, colour-from-photo.
- Next: server-side embedding similarity (`match_items`) blended into the duplicate score once items sync to Supabase;
  run the eval set (15 links) to see which retailers block on-device fetching.

### Phase 4 — Extras
- Receipt scanning (Gemini JSON, Vision OCR fallback), product image lookup.
- Share Extension target ("Share from any shopping app").
- Alternatives / wardrobe gaps via outfit simulation; scheduled weight updates from decisions + wears.

### Phase 5 — Evaluation & polish
- `eval/`: 20 closet photos, 10 receipts, 15 links (Zara, Uniqlo, H&M, Aritzia, Shein); hand-check fields; tune duplicate threshold.
- Empty/error states, accessibility, seed demo wardrobe, keep-alive so the free Supabase project doesn't pause.

## Setup

1. Create a new Supabase project (free tier) for ClosetWise.
2. `brew install supabase/tap/supabase`, then from the repo root:
   `supabase link --project-ref <ref>` → `supabase db push`
3. Put your key in `supabase/functions/.env` (copy `.env.example`), then `supabase secrets set --env-file supabase/functions/.env` → `supabase functions deploy gemini`. Local testing: `supabase functions serve gemini --env-file supabase/functions/.env`
4. Copy `ios/ClosetWise/Config/Secrets.example.xcconfig` to `Secrets.xcconfig` and fill in the project URL and anon key.
5. `cd ios && xcodegen && open ClosetWise.xcodeproj`

## Status (2026-11-09)

Working end to end on the simulator against the live Supabase project:
- Onboarding → empty closet, with an optional demo closet (Settings → Load / Clear).
- Add a piece: photo → ClosetWise reads type, colour, fit, cut, fabric → confirm → saved and synced.
- Edit or remove a piece (removal archives it in Supabase).
- Log an outfit: photo → `detect_outfit` spots closet pieces → confirm, react → wear counts and style learning update.
- Purchase check from a link, a photo or typed details → duplicates, style fit, outfits, cost per wear, plus ClosetWise's written verdict.
- Two-way sync: launch and returning to the app pull the account's copy, then push this phone's. The newer edit wins
  (`updated_at`), wear counts never go backwards, and deletions (items, outfits, checks) carry across phones.
  Photos taken on another phone download. Settings → Account saves the closet to an email with a 6-digit code;
  "I already have a closet saved" signs a new phone in (also on the welcome screen).
  Needs `{{ .Token }}` in the Supabase "Magic Link" and "Change Email Address" email templates.

Not built yet:
- Receipt scanning (bulk add from a receipt photo).
- Share Extension (check straight from Safari or a shop app).
- Inspiration photos are stored locally but not uploaded or sent to Gemini.
- Visual duplicate search: embeddings are stored, but `match_items` isn't blended into the duplicate score yet.
