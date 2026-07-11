# StudyGrades Commercial Readiness

## Mobile entitlement contract

The mobile app enforces subscriptions locally after login. The backend should
return subscription data either inside `user.subscription` or as top-level
subscription fields in the login response.

Example:

```json
{
  "access": "jwt",
  "refresh": "jwt",
  "user": {
    "id": 12,
    "username": "teacher1",
    "email": "teacher@example.com",
    "role": "teacher",
    "subscription": {
      "plan": "professional",
      "status": "active",
      "expires_at": "2027-07-01T00:00:00Z"
    }
  }
}
```

Supported plans:

- `trial`
- `starter`
- `professional`
- `school`
- `enterprise`

Supported statuses:

- `trialing`
- `active`
- `past_due`
- `canceled`
- `expired`
- `none`

## Enforced mobile limits

- Expired or inactive subscriptions cannot save or sync grades.
- Expired subscriptions can still authenticate, open `/account/me/`, refresh
  tokens, and create `/billing/intention/` checkout sessions so customers can
  renew without manual intervention.
- Class student count is capped by plan and larger classes are trimmed in-app.
- Offline pending sync queue is capped by plan.
- Whisper AI server transcription is fail-closed until a production provider
  and endpoint are configured. Device speech recognition remains available.
- Excel export is gated by plan.
- User management is gated by role and plan.

Existing non-developer accounts without valid subscription fields fail closed as
unlicensed. Legacy `developer` records receive the same server-side Enterprise
lifetime entitlement as the mobile model, so the owner can migrate and license
those accounts without a database backfill.

## Launch pricing

Prices are selected only by server-side environment variables. The production
launch catalog is:

| Plan | Monthly | Annual |
| --- | ---: | ---: |
| Starter | EGP 50 | EGP 500 |
| Professional | EGP 100 | EGP 1,000 |
| School | EGP 1,000 | EGP 11,000 |

## Commercial backend

The Netlify backend under `commercial_backend/` is the payment and entitlement
source of truth. Mobile clients must never be trusted for payment state.

Required Netlify environment variables:

- `JWT_SECRET`: at least 32 characters.
- `PAYMOB_SECRET_KEY`: Paymob secret/API token for creating intentions.
- `PAYMOB_PUBLIC_KEY`: Paymob public checkout key.
- `PAYMOB_HMAC_SECRET`: Paymob callback HMAC secret.
- `PAYMOB_CARD_INTEGRATION_ID`: the card integration id expected in callbacks.
- `PRICE_STARTER_MONTHLY_EGP`
- `PRICE_STARTER_ANNUAL_EGP`
- `PRICE_PROFESSIONAL_MONTHLY_EGP`
- `PRICE_PROFESSIONAL_ANNUAL_EGP`
- `PRICE_SCHOOL_MONTHLY_EGP`
- `PRICE_SCHOOL_ANNUAL_EGP`
- `ALLOWED_ORIGINS`: comma-separated browser origins allowed to call the API,
  for example `https://studygrades-2026.netlify.app`.

The backend creates Paymob intentions server-side, verifies Paymob HMAC before
reading payment records, checks amount/currency/integration id against the
stored order, and claims successful callbacks before fulfillment so duplicate or
concurrent callbacks do not extend a subscription twice.
The backend remains the only trusted source for checkout prices and subscription
activation; client-supplied amounts are ignored.

Commercial account creation and maintenance are also server-backed. Production
builds use authenticated `/admin/users/` endpoints and never fall back to the
local Hive account store. Password resets and account deactivation revoke all
active sessions. Blob writes use ETag-based conditional updates so concurrent
function instances do not silently overwrite account, grade, payment, or audit
changes.

## Production status

- API: `https://studygrades-2026.netlify.app/api/mobile`
- Paymob card integration: `5344998`
- Webhook: `https://studygrades-2026.netlify.app/api/mobile/billing/paymob/webhook/`
- Payment return: `https://studygrades-2026.netlify.app/api/mobile/billing/paymob/return/`
- Privacy policy: `https://studygrades-2026.netlify.app/privacy.html`
- Terms: `https://studygrades-2026.netlify.app/terms.html`
- Support: `https://studygrades-2026.netlify.app/support.html`
- Paymob automatic callback retry is enabled.
- Settlement beneficiary and Vodafone Cash customer-payment activation remain
  pending written confirmation from Paymob support. Do not release paid sales or
  payouts until Paymob confirms the intended beneficiary through its secure
  account process.

## Release checklist

- Return subscription fields from login and cached-user APIs.
- Configure all Netlify environment variables listed above.
- Keep the Paymob callback URL set to `/api/mobile/billing/paymob/webhook/`.
- Keep the Paymob redirect URL set to `/api/mobile/billing/paymob/return/`.
- Keep `ALLOWED_ORIGINS` restricted to owned domains only.
- Keep release builds without `ALLOW_OFFLINE_ADMIN_LOGIN`.
- Verify the signed APK/AAB before distribution.
- Upload `build/app/outputs/bundle/release/app-release.aab` to Google Play.
- Use `build/app/outputs/flutter-apk/app-release.apk` only for direct APK
  distribution/testing outside Google Play.

The Android release is verified with Gradle 8.14.4, Android Gradle Plugin
8.11.1, and Kotlin 2.2.20. Flutter reports a forward-looking Built-in Kotlin
migration warning for the app and several third-party plugins; this is not a
current build failure and must be reassessed when Flutter makes that migration
mandatory.
