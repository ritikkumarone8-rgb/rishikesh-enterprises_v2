# What could be done better

You asked me to flag this explicitly, so here's an honest backlog — split into
what would meaningfully help soon, and what's genuinely optional. Nothing here
blocks using the app; it's a prioritized list for whenever you want to keep
improving it.

## Worth doing soon

**Wishlist and reviews have no UI yet.** The database schema already supports
both fully (`wishlist`, `reviews` tables, RLS policies, the rating-aggregation
trigger that keeps `products.avg_rating` in sync) — they're wired up
server-side but nothing in the Flutter app lets a customer add to a wishlist or
leave a review yet. This was left out of the v1 screen set to focus on the
core browse → order → track loop first. Adding them is mostly frontend work at
this point since the backend is ready.

**Categories/brands management isn't in the seller dashboard.** Sellers can add
products, but new categories or brands currently need a manual SQL insert
(`docs/BACKEND_SETUP.md` step 9). Worth adding simple add/edit screens for both
in `seller-web/` — same pattern as the deals screen already there.

**No push notifications.** A customer placing an order has no way to know it
was confirmed or shipped except opening the app and checking. Supabase
supports this via a database webhook on `orders` status changes → a service
like Firebase Cloud Messaging or OneSignal. This is probably the single highest
customer-experience improvement available, and wasn't in scope for v1 mainly
because it adds a third external service (on top of Supabase and Razorpay) to
set up.

**Order cancellation.** Customers can view their orders but can't cancel one
themselves (e.g. within a grace window before the seller confirms it). Right
now that has to go through the seller dashboard. A `cancel_order()` RPC
mirroring `create_order()`'s pattern (only allowed while `status = 'new'`,
restores stock) would close this gap.

**No automated tests beyond one model-logic file.** `mobile/test/` currently
has unit tests for the pure pricing/stock helpers only
(`test/models/product_test.dart`) — there's no widget or integration test
coverage for the screens themselves, and no tests at all for the SQL layer
beyond the manual `psql` verification done while building it (worth turning
those manual test queries into a checked-in `pgTAP` or similar suite so
regressions get caught automatically as the schema evolves).

## Worth doing eventually

**Hindi (or Hinglish) language support.** Given the store's location, a
significant share of customers may prefer Hindi. Flutter's built-in
localization (`flutter_localizations` + `.arb` files) would handle this
cleanly; it wasn't attempted here since it's a meaningful chunk of additional
work (translating every string, right layout testing) better scoped as its own
task.

**Image handling could be smarter.** Product photos upload at whatever
resolution the seller's phone/camera produces. Client-side compression before
upload (e.g. resize to a max dimension, re-encode as WebP) would cut load
times and Supabase Storage costs noticeably at scale, at minimal quality cost.

**Delivery tracking is status-only.** Orders show a status (confirmed → in
transit → delivered) but no live location or ETA. Fine for a single-store
local delivery operation today; would need a real dispatch/rider system if you
ever expand beyond the store owner or a couple of staff doing deliveries
directly.

**No analytics.** There's no visibility into what customers search for but
don't find, cart abandonment, or which products get viewed but not bought.
Even lightweight event logging (a Supabase table + a few `insert` calls from
the app) would inform inventory/marketing decisions over time.

**Coupon discovery.** Customers currently have to already know a coupon code
to use one — there's no "available offers" list shown at checkout. The
`coupons` table already supports everything needed to list active,
currently-valid coupons; it's a UI gap, not a backend one.

**iOS was intentionally not built.** You asked specifically about the Play
Store, so this whole effort targeted Android. The Flutter codebase itself is
cross-platform and the backend doesn't care what client calls it, so adding
`mobile/ios/` later (same `flutter create --platforms=ios .` pattern used for
Android — see `docs/BACKEND_SETUP.md`) is realistic if you ever want an App
Store listing too. Two things would need attention specifically: Razorpay's
iOS SDK setup (a few extra `Info.plist` entries), and Apple's own review
process/guidelines for OTP login flows.

**Seller dashboard has no pagination.** Product/order/customer lists load up
to a fixed limit (200 products, 100 orders, 300 customers) in one request each.
Completely fine at your current and near-term catalogue size; would need real
pagination (or moving to the search RPC) if the catalogue grows into the
thousands of SKUs.

## Deliberately not done (and why)

**No admin "god mode" bypass of RLS anywhere in the client.** It would be
faster to add a special case that lets the dashboard skip RLS checks, but that
defeats the entire point of the security model in `SECURITY.md` — every seller
action goes through the same `is_seller()`-gated policies a compromised client
couldn't forge its way around.

**No support chat / ticketing system built in.** The profile screen has a
placeholder "Contact / Support" entry showing store info. A real in-app support
flow (chat, tickets) is a substantial feature on its own and felt out of scope
for "get the store online" — worth revisiting once real order volume surfaces
what customers actually need help with.
