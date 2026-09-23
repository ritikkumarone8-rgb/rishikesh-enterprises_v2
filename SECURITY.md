# Security posture

A summary of what changed from the old website/admin, and why, for anyone
picking this project up later.

## What the old site got wrong

The original `index.html`/`admin.html` (reviewed and partially fixed earlier in
this project) had a few structural issues that a fresh backend was the right
opportunity to fix properly, rather than patch around:

1. **No real customer identity.** Anyone could type any phone number into a
   field and see "their" past orders — there was no verification that the
   person typing the number actually owned it.
2. **Client-trusted pricing.** Nothing stopped a modified client from sending
   whatever price/total it wanted when placing an order.
3. **Auto-triggered geolocation.** The site requested the browser's location on
   page load, before the user asked for anything location-based.
4. A single hardcoded admin path/credential model rather than a real,
   revocable per-person login.

## What this rebuild does instead

**Customer identity is real.** Login is phone number + SMS OTP via Supabase
Auth. Nothing about "who is this customer" is ever taken from client input —
every read/write that's customer-scoped (addresses, orders, wishlist) is
enforced by Postgres Row Level Security keyed off `auth.uid()`, which only
Supabase's own auth server can set, not the app.

**Orders can't be created directly by the client, at all.** There is
deliberately **no INSERT policy on the `orders` table** for ordinary
authenticated users (see `backend/sql/001_schema.sql`, "orders / order_items"
section). The only way an order comes into existence is the `create_order()`
Postgres function (`backend/sql/002_order_rpc.sql`), which:
- runs as `SECURITY DEFINER` so it can insert despite the missing policy, but
- always takes the customer id from `auth.uid()`, never a parameter,
- re-reads every product's real price and stock from the database (never
  trusts a price the client sends),
- locks each product row (`SELECT ... FOR UPDATE`) and checks stock atomically,
  so two simultaneous orders for the last item in stock can't both succeed,
- re-validates any coupon server-side (scope, date window, minimum order
  value) rather than trusting a client-computed discount.

A modified or malicious client can change what it *asks* for, but it cannot
change what it *gets charged*, and it cannot place an order impersonating
another customer's account, address, or payment.

**Payments are verified server-side.** `create-razorpay-order` and
`verify-payment` (Edge Functions) never trust the client's word that a payment
succeeded — `verify-payment` recomputes the HMAC-SHA256 signature Razorpay
signs the payment with and rejects anything that doesn't match. A separate
`razorpay-webhook` function provides a second, fully server-to-server
confirmation path (using its own webhook secret) so a payment still gets marked
paid even if the customer's app closes or loses connection right after paying.

**Seller access is a real, revocable role**, not a hardcoded path. The
`sellers` table maps specific `auth.users` rows to seller privileges; every
catalogue/order-management write anywhere in the schema checks
`is_seller()`. Revoking access is one `delete from sellers where user_id = …`.
There's no seller self-signup (see `docs/BACKEND_SETUP.md` step 5) — a store
owner creates each seller login manually, which is the right tradeoff for a
single small business where the alternative (public signup + manual approval
queue) is more attack surface for no real benefit.

**Location is opt-in only.** The Flutter app never requests location
automatically. The only place it's requested is the explicit "Use my current
location" button on the add-address form
(`mobile/lib/features/checkout/widgets/address_form_sheet.dart`), and only
after the OS permission prompt the user sees and can deny.

**Least-privilege dependencies.** The customer app doesn't bundle
camera/gallery/storage permissions it doesn't use — product photo upload lives
entirely in the separate seller web dashboard, so `image_picker` and
`permission_handler` were removed from `mobile/pubspec.yaml` rather than left
in "just in case."

**Secrets never ship in a client.** The Supabase **anon** key is the only
Supabase key in either the Flutter app or the seller dashboard — safe by
design, since RLS (not key secrecy) is what actually gates access to data. The
**service-role** key (which bypasses RLS entirely) exists only as a Supabase
Edge Function runtime secret, injected by Supabase itself; it is never in
source control, never in `--dart-define`, never in `seller-web/`. Similarly,
the Razorpay **secret** key and webhook secret live only as Edge Function
secrets (`supabase secrets set …`), never client-side — only the Razorpay
**key id** (public by design) ships in the app.

**XSS-conscious seller dashboard.** `seller-web/app.js` runs every piece of
data pulled from the database (product names, customer phone numbers, order
details, etc.) through an `escapeHtml()` helper before it's interpolated into
rendered HTML, rather than trusting that database content can't contain
`<script>`-shaped text.

## Known limitations / things to revisit

Being upfront about what's *not* hardened yet, so it doesn't get assumed:

- **Image upload validation is client-side only** (file type/size checks in
  `seller-web/app.js` before upload). A determined seller-account holder could
  bypass this and upload something other than an intended image type directly
  via the API. Since only trusted sellers can upload at all (gated by
  `is_seller()` + storage bucket policies), this is a low-severity gap for now,
  but a production hardening step would be a Supabase Storage Edge Function
  hook or a scheduled job that validates/re-encodes uploaded files server-side.
- **No rate limiting on OTP requests** beyond whatever Supabase Auth applies by
  default. Worth checking Supabase's current defaults before launch and
  layering app-level throttling if needed.
- **No account deletion flow.** See `docs/PLAY_STORE_CHECKLIST.md` section 5 —
  currently handled as a manual request to the store, which needs to be
  genuinely honored, not just documented.
- **This code was never compiled/run** (Dart/Flutter side) before landing here
  — see `docs/BACKEND_SETUP.md`'s closing section. The backend SQL and the
  seller dashboard's JS *were* independently tested/verified; the Flutter app's
  first real compiler pass happens in CI. Treat anything CI flags as expected
  follow-up, and review it for logic bugs beyond what a compiler catches, too.
