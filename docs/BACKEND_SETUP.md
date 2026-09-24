# Backend setup — new Supabase project

This app uses a **new, separate Supabase project** (per your choice, not the one the
existing website uses). Nothing here touches the live site's data. Follow these
steps in order the first time.

## 1. Create the project

1. Go to [supabase.com](https://supabase.com) → New project.
2. Pick a name (e.g. `rishikesh-enterprises`), a strong database password (save it
   somewhere safe — you won't need it day-to-day, but you'll want it if you ever
   need to connect a raw Postgres client), and a region close to India
   (`ap-south-1`/Mumbai if offered).
3. Wait for provisioning to finish (a couple of minutes).

## 2. Run the database schema

1. In the Supabase dashboard, open **SQL Editor**.
2. Paste the full contents of `backend/sql/001_schema.sql` and run it.
3. Then paste and run `backend/sql/002_order_rpc.sql`.
4. If you're setting up Google sign-in (step 4 below), also paste and run
   `backend/sql/003_google_signin_profile.sql`. If not, skip it for now —
   it's safe to run later, whenever you do enable Google sign-in.
5. All three files are safe to re-run if you need to (they use
   `create or replace` / `if not exists` guards throughout).

This creates every table, the search function, and — importantly — all the Row
Level Security policies that keep customer data private and prevent price
tampering. Don't skip RLS or "temporarily disable" it while testing; the app
depends on it being on (see `SECURITY.md`).

## 3. Enable phone (SMS OTP) auth for customers

1. **Authentication → Providers → Phone** → enable it.
2. You need an SMS provider configured (Supabase doesn't send SMS itself). In the
   same screen, connect **Twilio**, **MessageBird**, or **Vonage** — Twilio is the
   most commonly used. You'll need a Twilio account, a phone number capable of
   sending SMS to Indian numbers, and its Account SID / Auth Token / phone number
   pasted into the Supabase provider settings.
   - Budget for this: Twilio SMS to India costs a small amount per message, and
     Twilio requires an initial account top-up. There's no way around some SMS
     provider cost for OTP login — it's how every phone-OTP flow works.
2. **Authentication → Settings**: leave email auth as-is for now (unused by the
   app), but it's what seller logins use (step 6).

## 4. Enable Google sign-in for customers ("Continue with Google")

This is separate from and additional to phone-OTP login (step 3) — customers
can use either. It needs setup in **two places**: Google Cloud Console (to
create the credentials) and the Supabase dashboard (to accept them). Do not
substitute any of the values below with something invented — they all come
from your own Google Cloud project.

### 4.1 Google Cloud Console

1. Go to [console.cloud.google.com](https://console.cloud.google.com/) and
   either select an existing project or create a new one (e.g.
   `rishikesh-enterprises`).
2. **APIs & Services → OAuth consent screen**:
   - User type: **External** (unless you have a Google Workspace org you want
     to restrict to).
   - App name, support email, developer contact email — fill these in with
     your own details.
   - Scopes: the default (`email`, `profile`, `openid`) is enough — the app
     only asks for `email` and `profile`.
   - While the app is in **Testing** mode, only the Google accounts you add
     as test users can sign in. Add your own phone-testing Google account
     here, or click **Publish app** when you're ready for any Google account
     to be able to sign in.
3. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
   You need to create **two** separate OAuth clients here:
   - **Application type: Web application.**
     - Name it something like `rishikesh-enterprises-web` (this is only ever
       used server-side / as an identifier — customers never see a web page
       for this).
     - No redirect URIs are required for this app's sign-in flow (it uses
       Google's native Android sign-in, not a browser redirect).
     - After creating it, Google shows you a **Client ID** *and* a **Client
       Secret**. You need both — the Client ID goes into this app (as
       `GOOGLE_WEB_CLIENT_ID`, see step 4.3) and into the Supabase dashboard;
       the Client Secret goes **only** into the Supabase dashboard, never
       into this app's code or repo.
   - **Application type: Android.**
     - **Package name**: `com.rishikeshenterprises.rishikesh_enterprises`
       (this is the `applicationId`/`namespace` the CI build generates —
       see `mobile/scripts/patch_android.py` and
       `.github/workflows/build.yml`, which run
       `flutter create --org com.rishikeshenterprises .`).
     - **SHA-1 certificate fingerprint**: the SHA-1 of whatever key actually
       signs the APK you're testing/shipping. Right now that's Flutter's
       **debug key** (see the signing note at the bottom of
       `.github/workflows/build.yml` — this app isn't using a real upload
       keystore yet). To get the debug key's SHA-1 from a machine with the
       Flutter/Android SDK installed:
       ```bash
       keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
       ```
       Copy the `SHA1:` value shown. **This SHA-1 is different on every
       machine's debug keystore** (including GitHub Actions' own ephemeral
       one) — so Google Sign-In may only work on whichever machine's debug
       key you registered. Once you generate a real upload keystore for the
       Play Store (see `docs/PLAY_STORE_CHECKLIST.md`), come back and add
       *that* keystore's SHA-1 as a second entry here (the Android OAuth
       client accepts multiple SHA-1 fingerprints).
     - This Android client has no Client Secret (Android clients never do)
       and its Client ID isn't pasted into the app's code — Google validates
       requests using the package name + SHA-1 you registered here, and
       Supabase is told about it in step 4.2 below.

### 4.2 Supabase dashboard

1. **Authentication → Providers → Google** → enable it.
2. **Client ID (for OAuth)**: paste the **Web application** Client ID from
   step 4.1.
3. **Client Secret (for OAuth)**: paste the **Web application** Client
   Secret from step 4.1. (Only ever goes here — never in the Flutter app.)
4. **Authorized Client IDs**: paste **both** Client IDs from step 4.1 (the
   Web one and the Android one), one per line/comma-separated as the field
   asks. This is what lets Supabase accept ID tokens minted for either
   client — without it, the native Android sign-in will fail even though
   the "Client ID"/"Client Secret" fields above look correct.
5. No redirect URL or deep-link configuration is needed for this app —
   that's only required for the browser-based OAuth flow, and this app uses
   Google's native Android sign-in instead.

### 4.3 This app's configuration

The only value this app's code needs is the **Web application Client ID**
from step 4.1 (not the secret, not the Android client). It's supplied at
build time the same way `SUPABASE_URL` etc. already are — see step 11
below and `mobile/lib/core/env.dart`.

## 5. Create the product-images storage bucket

Already created for you by `001_schema.sql` (a public-read, seller-write bucket
called `product-images`). Nothing to do here — just confirm it shows up under
**Storage** in the dashboard.

## 6. Create your first seller login

Seller accounts are **not self-service** — there's no signup form, by design (see
`SECURITY.md`). You create one manually, once, per person who should have seller
access (yourself, staff, etc.):

1. **Authentication → Users → Add user** → enter an email and a password. Untick
   "Auto confirm" only if you want to verify email first; for an internal tool,
   ticking "Auto confirm user" is simplest.
2. Copy that user's UUID (shown in the users list).
3. Back in **SQL Editor**, run:
   ```sql
   insert into sellers (user_id, name) values ('paste-the-uuid-here', 'Your Name');
   ```
4. That email/password now works at the seller dashboard (`seller-web/index.html`).

Repeat step 6 for each additional staff member who needs dashboard access.

## 7. Get your API keys

**Project Settings → API**:
- **Project URL** → this is `SUPABASE_URL`.
- **anon / public key** → this is `SUPABASE_ANON_KEY`. Safe to ship in the app and
  the seller dashboard — RLS is what actually protects the data, not secrecy of
  this key.
- **service_role key** → **never** put this in the app or the seller dashboard.
  Supabase Edge Functions get it automatically at runtime as
  `SUPABASE_SERVICE_ROLE_KEY` — you don't need to copy it anywhere yourself.

## 8. Deploy the Edge Functions

You'll need the [Supabase CLI](https://supabase.com/docs/guides/cli) installed
locally (`npm install -g supabase`), then from the `backend/` directory:

```bash
supabase login
supabase link --project-ref YOUR-PROJECT-REF
supabase functions deploy create-razorpay-order
supabase functions deploy verify-payment
supabase functions deploy razorpay-webhook
```

Then set the Razorpay secrets these functions need (get these from your Razorpay
dashboard → Settings → API Keys, after creating a Razorpay account):

```bash
supabase secrets set RAZORPAY_KEY_ID=rzp_live_xxxxxxxx
supabase secrets set RAZORPAY_KEY_SECRET=xxxxxxxxxxxxxxxx
supabase secrets set RAZORPAY_WEBHOOK_SECRET=xxxxxxxxxxxxxxxx
```

(`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` are provided to
every Edge Function automatically by Supabase — you don't set those.)

For the webhook secret: in the Razorpay dashboard, **Settings → Webhooks → Add
new webhook**, point it at
`https://YOUR-PROJECT-REF.supabase.co/functions/v1/razorpay-webhook`, subscribe to
`payment.captured` and `payment.failed`, and Razorpay will show you the secret to
use for `RAZORPAY_WEBHOOK_SECRET`.

Use Razorpay **test mode** keys until you're ready to accept real payments — the
app works identically, payments just don't move real money.

## 9. Configure the seller web dashboard

Edit `seller-web/config.js`:

```js
window.APP_CONFIG = {
  SUPABASE_URL: 'https://YOUR-PROJECT-REF.supabase.co',
  SUPABASE_ANON_KEY: 'your-anon-public-key',
};
```

Then host `seller-web/` anywhere that can serve static files (Netlify, Vercel,
GitHub Pages, or even just open `index.html` locally for testing). It's a
password-protected internal tool — see `SECURITY.md` for why it doesn't need
anything fancier than that for a single-store setup, and what to reconsider if
you grow into a multi-location or bigger business.

## 10. Add some real catalogue data

The schema ships empty. Before the app is useful, add at least:
- A few rows in `categories` (via the SQL editor, or build this into the seller
  dashboard later — categories/brands management wasn't in scope for v1, see
  `docs/WHAT_COULD_BE_BETTER.md`).
- A few rows in `brands` (Havells, etc.).
- Products — easiest done from the seller dashboard once it's configured (step
  9), since that's where the multi-image upload UI lives.

## 11. Run the Flutter app against it

```bash
cd mobile
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT-REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-public-key \
  --dart-define=RAZORPAY_KEY_ID=rzp_test_xxxxxxxx \
  --dart-define=GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

Leave off `GOOGLE_WEB_CLIENT_ID` (or leave it blank) if you haven't done step 4
yet — the app runs fine without it, "Continue with Google" just shows a
friendly "not configured" error instead of the account picker until it's set.

For CI (`.github/workflows/build.yml`), add the same value as a GitHub Actions
repository secret named `GOOGLE_WEB_CLIENT_ID` (**Settings → Secrets and
variables → Actions**), alongside the `SUPABASE_URL` / `SUPABASE_ANON_KEY` /
`RAZORPAY_KEY_ID` secrets that are presumably already there.

### About the Android platform folder

The `mobile/android/` directory isn't committed to this repo. It's generated by
running:

```bash
flutter create --platforms=android --org com.rishikeshenterprises .
python3 scripts/patch_android.py
```

from inside `mobile/`, before your first `flutter run`/`flutter build`. CI does
this automatically (`.github/workflows/build.yml`). Why it's not committed: this
project was built in a sandboxed environment with no Flutter SDK available and no
network access to the Google Maven/Gradle package repositories Android tooling
needs — so there was no way to generate or verify a hand-written
`android/build.gradle` tree here. Letting the real `flutter create` (running
wherever you or CI actually have the Flutter SDK) generate it guarantees it
matches whatever Flutter/Android Gradle Plugin version you're building with,
rather than a hand-typed one that could quietly go stale. `patch_android.py`
then layers on what this app needs that the bare template doesn't add
(location permissions, the app's display name, and SDK version pins some
dependencies require) — see that script's docstring.

This is a one-time step per checkout; once `android/` exists, `flutter run` works
normally.

## Why this session couldn't verify the Flutter/Dart code by compiling it

Worth being upfront about: the sandbox this app was built in has no Flutter SDK
installed, and its network egress policy blocks `pub.dev` and
`storage.googleapis.com` (confirmed by direct probing — both returned
`403 connect_rejected` from the environment's proxy), which is where Flutter's
own SDK and every Dart package come from. So every `.dart` file in `mobile/lib/`
and `mobile/test/` was hand-written and carefully self-reviewed, but never
actually compiled or run before reaching this repo. The SQL backend
(`backend/sql/`) and the seller dashboard (`seller-web/`) **were** verified —
PostgreSQL 16 and Node.js were available locally, so the schema, RLS policies,
and RPC functions were tested end-to-end against a real Postgres instance, and
`app.js` was syntax-checked and had its DOM id/class references cross-checked
against `index.html` programmatically.

`.github/workflows/build.yml` is where the Flutter app gets its first real
compiler pass. Expect to spend a little time there fixing whatever it finds —
that's normal for code that's never been built, not a sign something unusual
went wrong.
