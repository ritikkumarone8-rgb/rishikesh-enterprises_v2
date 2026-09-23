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
4. Both files are safe to re-run if you need to (they use `create or replace` /
   `if not exists` guards throughout).

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
   app), but it's what seller logins use (step 5).

## 4. Create the product-images storage bucket

Already created for you by `001_schema.sql` (a public-read, seller-write bucket
called `product-images`). Nothing to do here — just confirm it shows up under
**Storage** in the dashboard.

## 5. Create your first seller login

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

Repeat step 5 for each additional staff member who needs dashboard access.

## 6. Get your API keys

**Project Settings → API**:
- **Project URL** → this is `SUPABASE_URL`.
- **anon / public key** → this is `SUPABASE_ANON_KEY`. Safe to ship in the app and
  the seller dashboard — RLS is what actually protects the data, not secrecy of
  this key.
- **service_role key** → **never** put this in the app or the seller dashboard.
  Supabase Edge Functions get it automatically at runtime as
  `SUPABASE_SERVICE_ROLE_KEY` — you don't need to copy it anywhere yourself.

## 7. Deploy the Edge Functions

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

## 8. Configure the seller web dashboard

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

## 9. Add some real catalogue data

The schema ships empty. Before the app is useful, add at least:
- A few rows in `categories` (via the SQL editor, or build this into the seller
  dashboard later — categories/brands management wasn't in scope for v1, see
  `docs/WHAT_COULD_BE_BETTER.md`).
- A few rows in `brands` (Havells, etc.).
- Products — easiest done from the seller dashboard once it's configured (step
  8), since that's where the multi-image upload UI lives.

## 10. Run the Flutter app against it

```bash
cd mobile
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT-REF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-public-key \
  --dart-define=RAZORPAY_KEY_ID=rzp_test_xxxxxxxx
```

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
then layers on the two things this app needs that the bare template doesn't add
(location permissions, the app's display name) — see that script's docstring.

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
