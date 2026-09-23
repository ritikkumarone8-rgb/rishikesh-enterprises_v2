# Rishikesh Enterprises — customer app, seller dashboard & backend

A Flipkart-inspired shopping app for **Rishikesh Enterprises** (Havells dealer
& electricals store, Hajipur, Bihar): customers browse/search the catalogue,
place orders, and track them; sellers manage products (with multi-photo
uploads), stock, and orders from a web dashboard.

## Structure

```
backend/          New Supabase project: SQL schema + RLS policies, and the
                   Edge Functions that handle payments securely server-side.
mobile/            The Flutter customer app (Android first — see
                   docs/PLAY_STORE_CHECKLIST.md).
seller-web/        A single-page web dashboard for the store's own staff to
                   manage products, stock, orders and deals.
docs/              Setup guide, Play Store checklist, and an honest backlog
                   of what could still be improved.
.github/workflows/ CI: builds and tests the Flutter app on every push.
SECURITY.md        What changed from the old site's security model, and why.
```

## Start here

1. **[docs/BACKEND_SETUP.md](docs/BACKEND_SETUP.md)** — set up the new
   Supabase project, deploy the Edge Functions, create your first seller
   login. Do this first; nothing else works without it.
2. **[SECURITY.md](SECURITY.md)** — what this rebuild does differently from
   the old site and why, plus known limitations worth knowing about.
3. **[docs/PLAY_STORE_CHECKLIST.md](docs/PLAY_STORE_CHECKLIST.md)** — for when
   you're ready to actually publish (you said you're not sure yet, which is
   completely fine — the app builds and runs without a Play Console account).
4. **[docs/WHAT_COULD_BE_BETTER.md](docs/WHAT_COULD_BE_BETTER.md)** — a
   prioritized backlog of real next steps, split from things intentionally
   left out of v1.

## The honest caveat

The Flutter/Dart code in `mobile/` was hand-written without ever being
compiled — this sandbox has no Flutter SDK and blocks the network access
Flutter tooling needs (see the last section of `docs/BACKEND_SETUP.md` for the
full explanation). `.github/workflows/build.yml` is where it gets compiled for
the first time. The SQL backend and the seller dashboard's JavaScript, by
contrast, *were* tested — the backend against a real local PostgreSQL
instance (RLS policies, the order-placement transaction, concurrent stock
handling, and the typo-tolerant search all verified with real queries), and
the dashboard's script syntax-checked and cross-referenced against its HTML.
Expect the first CI run on `mobile/` to surface something to fix — that's
normal for code that's never been built, not a sign anything is unusually
wrong.

## What's using what

- **Customers** log in with phone number + SMS OTP (no password) — see
  `mobile/lib/features/auth/`.
- **Orders** can only ever be created through the `create_order` Postgres
  function, never a direct table write from the app — this is what stops a
  modified client from tampering with prices (`SECURITY.md` has the full
  reasoning).
- **Search** combines Postgres full-text ranking with trigram fuzzy matching,
  so a typo like "buld" still finds "Bulb" — see `search_products` in
  `backend/sql/001_schema.sql`.
- **Payments** go through Razorpay; the app never sees or handles card/UPI
  details directly, and payment success is verified server-side (HMAC
  signature check + a webhook fallback), never trusted from the client alone.
- **Sellers** log in with email/password (provisioned manually, not
  self-service) at `seller-web/`, where they manage the catalogue — including
  uploading multiple photos per product that customers can then scroll
  through on the product page.
