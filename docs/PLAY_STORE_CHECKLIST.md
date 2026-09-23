# Play Store readiness checklist

You said you're not sure yet about a Play Store account — this doc is here for
when you are. Nothing below needs to happen before you can build and test the
app; it's only needed to actually publish it.

## 1. Google Play Console account

- Go to [play.google.com/console](https://play.google.com/console/signup) and
  sign up as an organization or individual developer. As of 2025 this is a
  one-time **$25 USD** registration fee, plus identity verification (can take a
  few days — Google sometimes asks for a government ID and/or a short video, and
  new developer accounts may have a 14-day publishing hold on their first app for
  review). Start this early since the verification wait is the slowest part.

## 2. Decide your final application ID

`flutter create --org com.rishikeshenterprises .` (see `docs/BACKEND_SETUP.md`)
produces the application ID `com.rishikeshenterprises.rishikesh_enterprises`.
**This cannot be changed after your first Play Store upload** — Google treats a
new application ID as a completely different app. Before you build the version
you intend to actually upload:
- If you're happy with that id, no action needed.
- If you want something shorter/different (e.g. `com.rishikeshenterprises.app`),
  change it *before* your first upload: `android/app/build.gradle` →
  `applicationId`, and the matching `android:name` package references — or
  regenerate with a different `--org`/project name. Do this once, early, and
  don't touch it again after publishing.

## 3. Signing (the part CI doesn't do for you yet)

`.github/workflows/build.yml` currently builds a **debug-signed** release AAB —
fine for internal testing and sideloading APKs to your own phone, but the Play
Store will reject a debug-signed upload. Before your first real Play Console
upload:

1. Generate an upload keystore (do this once, keep the file and its passwords
   somewhere safe — losing it means you can't update the app under the same
   listing again without going through Google's account-recovery process):
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Create `mobile/android/key.properties` (don't commit this file — add it to
   `.gitignore`):
   ```properties
   storePassword=<the password you set>
   keyPassword=<the password you set>
   keyAlias=upload
   storeFile=/absolute/path/to/upload-keystore.jks
   ```
3. In `mobile/android/app/build.gradle`, add a release signing config that reads
   `key.properties` and use it for the `release` build type instead of the debug
   signing config that's there by default. (This file doesn't exist in the repo
   until you run `flutter create` — see `docs/BACKEND_SETUP.md` — so this step
   happens locally, once, after that.)
4. For CI to build a properly-signed release automatically, base64-encode the
   keystore and store it as a GitHub Actions secret, then add a step to
   `.github/workflows/build.yml` that decodes it to a file before the build
   steps, plus `KEYSTORE_PASSWORD`/`KEY_PASSWORD`/`KEY_ALIAS` secrets referenced
   from `key.properties`. This is intentionally left as a manual step for when
   you're ready — wiring up signing secrets before you have a Play Console
   account (and know you're actually publishing) would just be secrets sitting
   unused.

Once you upload your first properly-signed build, enroll in **Play App
Signing** (Google's recommended default) — Google then re-signs the app for
distribution and manages the distribution key for you; you keep using your
upload key for future releases.

## 4. Store listing assets

You'll need, at minimum:
- **App icon**: 512×512 PNG. Also update the in-app launcher icons — the
  `flutter create` scaffold ships a placeholder Flutter icon; replace
  `mobile/android/app/src/main/res/mipmap-*/ic_launcher.png` (all densities) or
  use the `flutter_launcher_icons` package to generate them from one source
  image.
- **Feature graphic**: 1024×500 PNG/JPG.
- **Screenshots**: at least 2, phone-sized (the app is phone-only for now — no
  tablet-specific layouts were built).
- **Short description** (80 chars) and **full description** (4000 chars) — e.g.
  "Shop electricals from Rishikesh Enterprises, Hajipur — Havells switches,
  wires, fans, lighting and more. Browse, search, and order for pickup or
  delivery."
- **App category**: Shopping.
- **Contact details**: an email and, ideally, a website or physical address for
  the store.

## 5. Privacy policy (required — the app collects phone numbers and addresses)

Google requires a privacy policy URL for any app handling personal data,
including phone number login. At minimum it should disclose:
- What's collected: phone number (for login), name/email (optional, if you add
  profile editing later), delivery addresses, order history, and — only if the
  user taps "use current location" — device location at that moment (never
  collected automatically or in the background; see `SECURITY.md`).
- Why: to authenticate the customer, fulfil orders, and show relevant delivery
  options.
- Who it's shared with: Razorpay (for payment processing only, if the customer
  pays online) and your SMS provider (to deliver the OTP). Not sold or shared
  for advertising.
- How to request deletion: give a contact email; you'd delete the row(s) from
  `customers`/`addresses`/`orders` (or anonymize) manually via the Supabase
  dashboard on request, since there's no in-app "delete my account" flow yet
  (see `docs/WHAT_COULD_BE_BETTER.md`).

Host this as a simple page anywhere (even a single static HTML page next to the
seller dashboard) and put its URL in the Play Console listing.

## 6. Data safety form (Play Console)

Play Console will ask you to fill in a "Data safety" questionnaire describing
what data the app collects and why. Based on what this app actually does:
- **Personal info**: phone number (required, for account creation/login).
- **Location**: approximate/precise location, collected only when the user
  explicitly taps "use my current location," used for delivery address
  autofill, not shared with third parties, not used for advertising.
- **Financial info**: payment info is collected and processed by Razorpay
  directly (the app never sees card/UPI details) — declare accordingly per
  Razorpay's own Play Store data-safety guidance.
- Declare data is encrypted in transit (Supabase/Razorpay both enforce HTTPS)
  and that users can request deletion (via the contact method in your privacy
  policy).

## 7. Content rating questionnaire

Standard for a retail/shopping app — no user-generated content beyond product
reviews (which are seller-moderated via `is_visible`), no violence/gambling/etc.
Should land in the lowest rating tier (e.g. "Everyone").

## 8. Before you submit: test the whole flow for real

- Run a real end-to-end order with Razorpay in **test mode** first, then switch
  to live keys (`docs/BACKEND_SETUP.md` step 7) and do one real small-value
  order to confirm live payments actually work end-to-end, including the
  webhook.
- Test phone OTP login with a real phone number, not just Supabase's dashboard.
- Test on a real low-end Android device if you can — the target market here is
  price-sensitive Android phones, not necessarily the latest hardware.

## 9. Internal testing track first

Don't publish straight to production. Use Play Console's **Internal testing**
track first (instant availability to a small list of testers' emails you
provide, no review wait) to sanity-check the actual signed release build on
real devices before rolling out further.
