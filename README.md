<p align="center"><img src="ClosetWiseLogo.png" width="128" alt="ClosetWise logo"></p>

<h1 align="center">ClosetWise</h1>

A wardrobe-aware shopping check for iOS. Before you buy something, ClosetWise compares it with the closet you already own: look-alikes you have, how well it fits your style, how many outfits it makes, and its likely cost per wear. You decide; the app only informs.

- **Your closet as a clothing rail:** add pieces from a photo, and Gemini fills in type, colour, fit, cut and fabric.
- **Purchase check** from a product link, a photo or typed details, with a written verdict that names what you already own.
- **Outfit logging** from a mirror selfie: it spots your pieces, updates wear counts and learns your style.
- **Your style:** vibes, fits, colours and dressiness you tell it, plus what it learns from what you wear.
- **Accounts and sync:** sign up with email and password; your closet syncs through Supabase to any phone you sign in on.

---

## ⚡ Quick start (teammates)

1. Install **Xcode 16+** and **XcodeGen**: `brew install xcodegen`.
2. Clone the repo, then create your secrets file:
   ```bash
   git clone https://github.com/biplopghimire/ClosetWise.git && cd ClosetWise
   cp ios/ClosetWise/Config/Secrets.example.xcconfig ios/ClosetWise/Config/Secrets.xcconfig
   ```
3. Paste the **Supabase URL** and **anon key** (ask the project owner) into `Secrets.xcconfig`. Keep the URL's `https:/$()/` form.
4. Build and run:
   ```bash
   cd ios && xcodegen generate && open ClosetWise.xcodeproj
   ```
   Pick an iPhone simulator and press **⌘R**.
5. In the app: **Create account** (email + password), then tap your initials → **Settings → Gemini API key** and paste your free key from [AI Studio](https://aistudio.google.com/apikey).

Stuck? Each step is explained in detail in [Path A](#path-a-use-the-teams-backend), and common problems are in [Troubleshooting](#troubleshooting).

---

## 🚀 Getting started

There are two ways to set things up. **Most teammates only need Path A.**

| | What you get | Time |
|---|---|---|
| **Path A: Use the team's backend** | Run the app against the Supabase project we already share, with **your own Gemini API key**. | ~10 min |
| **Path B: Your own backend** | Your own Supabase project, e.g. to change the database or the Edge Function without affecting anyone else. | ~30 min |

> 🔑 **Everyone brings their own Gemini key.** You paste it in the app (**Settings → Gemini API key**), and it's sent with each AI request, so you use your own free Gemini quota, not someone else's. See [How your Gemini key is handled](#how-your-gemini-key-is-handled).

> 💡 The app also runs with **no backend at all** (no `Secrets.xcconfig`): it skips sign-in, saves your closet on the phone only, and Home says *"Supabase isn't configured"*. That's handy for UI work, but accounts, sync and AI features need a backend.

### Before you start: install the tools

You need a **Mac**. Then:

1. **Xcode 16 or newer** from the Mac App Store. Open it once so it installs its extra components, and install an **iOS simulator** if it asks (Xcode → Settings → Components).
2. **Homebrew** if you don't have it: see [brew.sh](https://brew.sh).
3. **XcodeGen** (generates the Xcode project from `ios/project.yml`):
   ```bash
   brew install xcodegen
   ```
4. **Node.js** (only for Path B, to run the Supabase CLI with `npx`):
   ```bash
   brew install node
   ```

Then clone the repo:

```bash
git clone https://github.com/biplopghimire/ClosetWise.git
```

```bash
cd ClosetWise
```

---

## Path A: Use the team's backend

The Supabase project already has the database and the Edge Function set up. You point the app at it, create an account in the app, and add your own Gemini key.

### 1. Get your own Gemini API key

1. Go to [Google AI Studio → API keys](https://aistudio.google.com/apikey) and sign in with a Google account.
2. Click **Create API key** and copy it.

Make a **new key just for ClosetWise** (don't reuse one from another project), so you can delete it any time without breaking anything else. The free tier is plenty for testing. Keep it handy: you'll paste it into the app in step 5.

### 2. Get the Supabase URL and anon key from a teammate

Ask the project owner (or check Supabase → **Project Settings → API**, if you've been added to the project) for:

- **Project URL**, which looks like `https://abcdefghijkl.supabase.co`
- **anon public key**, a long string starting with `eyJ...` (it's also called the *publishable* key)

> 🔒 Share these in a private message, not in the repo or a public channel. **Never** share the `service_role` key; the app doesn't need it.

### 3. Create your secrets file

```bash
cp ios/ClosetWise/Config/Secrets.example.xcconfig ios/ClosetWise/Config/Secrets.xcconfig
```

Open `ios/ClosetWise/Config/Secrets.xcconfig` and fill it in:

```
SUPABASE_URL = https:/$()/abcdefghijkl.supabase.co
SUPABASE_ANON_KEY = eyJhbGciOi...the-anon-key...
GEMINI_API_KEY =
DEVELOPMENT_TEAM = YOUR-TEAM-ID
```

Leave `GEMINI_API_KEY` empty: you'll add your key inside the app instead.

⚠️ **Keep the `$()` in the URL.** It must be `https:/$()/...`, not `https://...`, because `//` starts a comment in `.xcconfig` files and the URL would be cut off.

`DEVELOPMENT_TEAM` is only needed to run on a **real iPhone** (see [Running on your iPhone](#running-on-your-iphone)). For the simulator you can leave it as is.

### 4. Generate the Xcode project and run

```bash
cd ios && xcodegen generate && open ClosetWise.xcodeproj
```

In Xcode:

1. Pick the **ClosetWise** scheme and an iPhone simulator at the top of the window.
2. Press **⌘R** to build and run. The first build takes a few minutes while Xcode downloads the Supabase package.

### 5. Create your account and add your Gemini key

1. The app opens on **Create your account**. Enter your email and a password (8+ characters) and tap **Create account**.
2. Tap your initials (top right of Home) to open **Settings → Gemini API key**, paste the key from step 1 and tap **Save key**. The app checks it with Google before saving.
3. Try adding an item from a photo: if ClosetWise fills in the details, everything works. 🎉

Already have an account (e.g. from another phone)? Tap **I already have an account** instead.

**Useful Settings:**
- **Account → Set a password:** set or change your password while signed in. No email needed, which helps accounts made with the old email-code sign-in.
- **Closet → Load / Remove the demo closet:** try the app with 16 sample pieces, then remove them. Pieces you added yourself stay.

That's it. Skip to [Everyday workflow](#everyday-workflow).

---

## Path B: Your own backend

Use this if you want a separate Supabase project.

### 1. Create a Supabase project

1. Sign up at [supabase.com](https://supabase.com) and click **New project**. Any name and region works; save the database password somewhere.
2. Once it's ready, note the **project ref**: the `abcdefghijkl` part of `https://abcdefghijkl.supabase.co` (also shown under **Project Settings → General**).

### 2. Set up the database

From the repo root:

```bash
npx supabase login
```

```bash
npx supabase link --project-ref YOUR-PROJECT-REF
```

```bash
npx supabase db push
```

This creates the tables, row-level security policies and storage buckets from `supabase/migrations/`.

### 3. Turn on the sign-in options

In the Supabase dashboard:

- **Authentication → Sign In / Providers → Email:** make sure **Email** is enabled and turn **off** **Confirm email**, so new accounts work right away.
- **Authentication → Emails → Templates:** in the **Magic Link** template, add `{{ .Token }}` somewhere in the body, e.g. `Your ClosetWise code is {{ .Token }}`. **Forgot password?** in the app emails this one-time code.

### 4. Deploy the Edge Function

```bash
npx supabase functions deploy gemini
```

The function needs no secrets: each app sends its own Gemini key. (If you want a server-side key as well, see [For the project owner](#for-the-project-owner-optional-server-key).)

### 5. Point the iOS app at your project

Follow [Path A](#path-a-use-the-teams-backend), steps 1, 3, 4 and 5, using **your** project's URL and anon key from **Project Settings → API**.

---

## How your Gemini key is handled

- You paste your key in **Settings → Gemini API key**. It's stored in the phone's **Keychain** (encrypted, never synced to Supabase), so each phone needs it once.
- The app sends it over HTTPS in an `x-gemini-key` header, **only** to the `gemini` Edge Function. The function uses it for that one call to Google and never stores or logs it.
- Requests without a key are refused with `missing_gemini_key`, so nobody can accidentally run on someone else's quota.

**Things to know:**

- Whoever owns the Supabase project controls the Edge Function, so you're trusting them with your key. That's fine within the team; use a separate ClosetWise-only key anyway.
- If you put a key in `Secrets.xcconfig` instead (optional, for development), it's built into that copy of the app: **don't share such builds** (TestFlight, an `.ipa`), since anyone with the build could get the key out.
- For extra safety, restrict your key: in [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials), edit the key and limit it to the **Generative Language API**.
- Think your key leaked? Delete it in AI Studio, make a new one and paste it in **Settings → Gemini API key**. It takes 30 seconds.

### For the project owner: optional server key

If you'd rather not paste a key in your own app, the function can use a server-side key, but **only for email addresses you list**. Everyone else still has to bring their own.

```bash
cp supabase/functions/.env.example supabase/functions/.env
```

Fill in `GEMINI_API_KEY` and `SERVER_KEY_EMAILS` (the email you sign in to the app with), then:

```bash
npx supabase secrets set --env-file supabase/functions/.env
```

Use the email of your ClosetWise account.

---

## Running on your iPhone

1. Find your Apple **Team ID**: Xcode → **Settings → Accounts**, add your Apple ID if needed, select your team. A free personal team works. (The ID is also on [developer.apple.com/account](https://developer.apple.com/account) under Membership.)
2. Put it in `Secrets.xcconfig` as `DEVELOPMENT_TEAM = ABCDE12345`, then run `xcodegen generate` again in `ios/`.
3. Plug in your iPhone, select it at the top of Xcode and press **⌘R**.
4. The first time, on the iPhone: **Settings → General → VPN & Device Management**, trust your developer certificate. You may also need to turn on **Settings → Privacy & Security → Developer Mode**.

If Xcode says the bundle identifier `edu.cmu.closetwise.app` is unavailable (someone else's team already registered it), change `PRODUCT_BUNDLE_IDENTIFIER` in `ios/project.yml` locally to something unique like `edu.cmu.closetwise.yourname`, and don't commit that change.

---

## Everyday workflow

- **Pulled new changes?** Run `xcodegen generate` in `ios/` again if any files were added, removed or renamed. The `.xcodeproj` is generated and git-ignored, so never edit project settings in Xcode; change `ios/project.yml` instead.
- **Tests:** press **⌘U** in Xcode with the **ClosetWise** scheme.
- **Changed the database?** Add a new file in `supabase/migrations/` and run `npx supabase db push`.
- **Changed the Edge Function?** Run `npx supabase functions deploy gemini`. On the shared project, check with the team first, since everyone uses it.

## Files you create (and never commit)

| File | What's in it | Who needs it |
|---|---|---|
| `ios/ClosetWise/Config/Secrets.xcconfig` | Supabase URL, anon key, Apple Team ID (and optionally a dev Gemini key) | Everyone |
| `supabase/functions/.env` | Server-side Gemini key and allowed emails | Only the project owner, and only if using the optional server key |

Both are already in `.gitignore`. If `git status` ever shows one of them, stop and don't commit it.

## Troubleshooting

| Problem | Fix |
|---|---|
| `xcodegen: command not found` | `brew install xcodegen` |
| Home says *"Saved on this phone — Supabase isn't configured"* | `Secrets.xcconfig` is missing or empty. Check the file name and values, run `xcodegen generate` again, then **Product → Clean Build Folder** (⇧⌘K) and run. |
| Cloud status shows an error, or sign-in fails | The URL is probably cut off: make sure it's written `https:/$()/...`. Also check the anon key was copied in full. |
| Home says *"Add your Gemini API key"*, or AI features fail with `missing_gemini_key` | Add your key in **Settings → Gemini API key**. |
| *"Google says that key isn't valid"*, or `API key not valid` | The Gemini key is wrong or was deleted. Make a new one in AI Studio and save it again. |
| *"Email sign-ups need Confirm email turned off"* | In Supabase: **Authentication → Sign In / Providers → Email**, turn off **Confirm email**. |
| *"That email and password don't match"* for an account you made before passwords existed | On a phone still signed in to it, use **Settings → Account → Set a password**. Otherwise use **Forgot password?** |
| The forgot-password email never arrives | Supabase's built-in mailer only sends to members of the Supabase team, a few emails per hour. Ask the project owner to add you to the team, or set up custom SMTP (**Authentication → Emails → SMTP Settings**). |
| AI features say Gemini is busy, or fail with `429` | You've hit your key's free-tier rate limit. Wait a minute and try again. |
| "Signing for ClosetWise requires a development team" | Only on a real iPhone: set `DEVELOPMENT_TEAM` (see [Running on your iPhone](#running-on-your-iphone)). |
| The forgot-password email has no code in it | Add `{{ .Token }}` to the Magic Link email template (Path B, step 3). |
| Home looks cut off at the edges | Pull the latest code; this was fixed. |
| Package resolution errors on first build | **File → Packages → Reset Package Caches**, then build again. |

---

## How it's built

- **iOS:** SwiftUI (iOS 17+), project generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen), [supabase-swift](https://github.com/supabase/supabase-swift).
- **Backend:** Supabase (Postgres + pgvector, Storage, Auth with email + password, row-level security).
- **AI:** Google Gemini, called only from the Supabase Edge Function in `supabase/functions/gemini`, using the key each user saves in the app and sends in `x-gemini-key`.

```
ios/                 SwiftUI app (ios/project.yml → Xcode project)
  ClosetWise/        App, Models, Services, Features, Design
  ClosetWiseTests/   Unit tests (purchase-check engine, sync merge rules)
supabase/
  migrations/        Database schema, RLS policies, storage buckets
  functions/gemini/  Edge Function: item attributes, style summary, purchase verdict, outfit detection, embeddings
PLAN.md              Architecture, phases and current status
```
