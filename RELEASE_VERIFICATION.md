# StudyGrades Release Verification

Verification date: 2026-07-11 (Africa/Cairo)

## Production backend

- Production URL: `https://studygrades-2026.netlify.app`
- API base URL: `https://studygrades-2026.netlify.app/api/mobile`
- Latest verified deployment ID: `6a51780b34dff4e51692ef25`
- Netlify reported the deployment as live after bundling the production function.
- Backend test suite: 43 passed, 0 failed.
- Backend syntax check: passed.
- Production dependency audit: 0 known vulnerabilities after the tested
  OpenTelemetry 2.9.0 security override.
- Flutter static analysis: no issues found.
- Flutter test suite: 120 passed, 0 failed.

GitHub Actions run `29142782342` performed the post-deployment smoke test from
an independent Ubuntu runner. It verified the production health response,
confirmed that unauthenticated admin access returns 401, confirmed that an
unsigned Paymob webhook returns 401, and confirmed that the payment return page
publishes a Content-Security-Policy header. The same run passed formatting,
static analysis, all Flutter tests, Web build, and Android debug build.

## Android artifacts

### Google Play bundle

- File: `build/app/outputs/bundle/release/app-release.aab`
- Release copy: `D:\StudyGrades_MobileApp\artifacts\StudyGrades-1.0.0+1-release.aab`
- Size: 69,682,447 bytes
- SHA-256: `97033879299F7D409359B5E69B1F95F72961ECC09F4522CA95F8342958EB582A`
- `bundletool 1.18.1 validate`: passed.
- Bundle package id: `com.studygrades.app`.

### Direct-distribution APK

- File: `build/app/outputs/flutter-apk/app-release.apk`
- Release copy: `D:\StudyGrades_MobileApp\artifacts\StudyGrades-1.0.0+1-release.apk`
- Size: 73,015,655 bytes
- SHA-256: `C6E8AAD122BF2AAB9FF14433C1855D59A52B376EFE4CA43B19FC28397102C4E1`
- APK Signature Scheme v2: verified.
- Number of signers: 1.
- Signing certificate: `CN=StudyGrades, OU=Mobile, O=StudyGrades, L=Cairo, ST=Cairo, C=EG`.
- Certificate SHA-256: `67B32E9EBEB392F0771D70C33883EC567B58F7A27B429251ACCF4D8D23BDA8E1`.

The new APK was installed on the Android 35 emulator and launched as
`com.studygrades.app/.MainActivity`. The onboarding flow reached the production
login screen, the activity remained top-resumed, and the filtered Android error
log contained zero
`FATAL EXCEPTION`/application crash matches. Visual evidence is stored outside
the repository at:

- `D:\StudyGrades_MobileApp\artifacts\studygrades_clean.png`
- `D:\StudyGrades_MobileApp\artifacts\studygrades_login_clean.png`

## Build environment

- Flutter: 3.44.3 stable.
- Dart: 3.12.2.
- Java: Temurin JDK 17.0.18.
- Android SDK: `D:\Android\Sdk` (Android 36, build-tools 36.0.0).
- Gradle cache: `D:\.gradle`; retained for faster future builds.
- Gradle: 8.14.4.
- Android Gradle Plugin: 8.11.1.
- Kotlin Gradle Plugin: 2.2.20.
- Pub cache: `D:\StudyGrades_MobileApp\.pub-cache`; configured as the permanent
  user `PUB_CACHE` so future dependency work does not consume drive C.
- Flutter still reports a forward-looking Built-in Kotlin migration warning for
  the app and several third-party plugins. It is not a current build failure;
  both signed release artifacts completed with the versions above.

## Paymob state

- Merchant ID: `1085005`.
- Online card integration: `5344998`.
- Production webhook and redirect URLs are configured.
- Automatic callback retry is enabled.
- Launch prices are configured server-side as EGP 50/500 for Starter,
  EGP 100/1,000 for Professional, and EGP 1,000/11,000 for School.
- Balance & Transfers currently shows only `Account **** 0000`, no selectable
  beneficiary, no transfer history, and no balance. There is no dashboard action
  that identifies or removes an external settlement beneficiary.
- Vodafone Cash customer-payment activation and the settlement beneficiary still
  require written confirmation from Paymob support. Paid commercial launch and
  payout release must remain blocked until that confirmation is received through
  Paymob's secure process.

No API keys, tokens, passwords, signing-store secrets, or full bank details are
recorded in this document.
