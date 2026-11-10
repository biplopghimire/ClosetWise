# ClosetWise

A wardrobe-aware shopping check for iOS. Before you buy something, ClosetWise compares it with the closet you already own: look-alikes you have, how well it fits your style, how many outfits it makes, and its likely cost per wear. You decide; the app only informs.

- **Your closet as a clothing rail:** add pieces from a photo, and Gemini fills in type, colour, fit, cut and fabric.
- **Purchase check** from a product link, a photo or typed details, with a written verdict that names what you already own.
- **Outfit logging** from a mirror selfie: it spots your pieces, updates wear counts and learns your style.
- **Your style:** vibes, fits, colours and dressiness you tell it, plus what it learns from what you wear.
- **Sync** across phones through Supabase, with an email code to save your closet or sign in on another phone.

## Stack

- **iOS:** SwiftUI (iOS 17+), project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen), [supabase-swift](https://github.com/supabase/supabase-swift).
- **Backend:** Supabase (Postgres + pgvector, Storage, Auth with anonymous and email-code sign-in, row-level security).
- **AI:** Google Gemini, called only from the Supabase Edge Function in `supabase/functions/gemini`. The Gemini key never ships in the app.

```
ios/                 SwiftUI app (ios/project.yml → Xcode project)
  ClosetWise/        App, Models, Services, Features, Design
  ClosetWiseTests/   Unit tests (purchase-check engine, sync merge rules)
supabase/
  migrations/        Database schema, RLS policies, storage buckets
  functions/gemini/  Edge Function: item attributes, style summary, purchase verdict, outfit detection, embeddings
PLAN.md              Architecture, phases and current status
```

## Setup

You need Xcode 16+, XcodeGen (`brew install xcodegen`), Node (for `npx supabase`), a Supabase project and a Gemini API key.

1. **Supabase**
   ```bash
   npx supabase login
   npx supabase link --project-ref YOUR-PROJECT-REF
   npx supabase db push
   ```
   Then, in the Supabase dashboard:
   - **Authentication → Sign In / Providers:** turn on **Allow anonymous sign-ins**.
   - **Authentication → Emails:** in the **Magic Link** and **Change Email Address** templates, add `{{ .Token }}` (the app signs in with a 6-digit code).

2. **Gemini key (server side only)**
   ```bash
   cp supabase/functions/.env.example supabase/functions/.env   # add GEMINI_API_KEY
   npx supabase secrets set --env-file supabase/functions/.env
   npx supabase functions deploy gemini
   ```

3. **iOS app**
   ```bash
   cp ios/ClosetWise/Config/Secrets.example.xcconfig ios/ClosetWise/Config/Secrets.xcconfig
   # fill in SUPABASE_URL, SUPABASE_ANON_KEY (Project Settings → API) and DEVELOPMENT_TEAM
   cd ios && xcodegen generate && open ClosetWise.xcodeproj
   ```
   Run the **ClosetWise** scheme on a simulator or an iPhone. Run the tests with ⌘U.

`Secrets.xcconfig` and `.env` are git-ignored; never commit them.
