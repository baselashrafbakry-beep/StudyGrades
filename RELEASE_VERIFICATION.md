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
- Flutter test suite: 82 passed, 0 failed.

The current workstation network cannot establish TCP port 443 connections to
the resolved Netlify CDN addresses. Live HTTP requests therefore time out before
reaching the service. This is recorded as a network-path limitation, not treated
as a successful endpoint check. The same endpoints were successfully exercised
before the latest hardening deployment, and the latest deployment completed in
Netlify, but an external post-deployment smoke test is still required when that
network path is available.

## Android artifacts

### Google Play bundle

- File: `build/app/outputs/bundle/release/app-release.aab`
- Size: 69,464,543 bytes
- SHA-256: `406BF2091DB1CA80AC630DE0B0BE82FC98F7B2EB2094F13D61A5296C261040FE`
- `bundletool 1.18.1 validate`: passed.

### Direct-distribution APK

- File: `build/app/outputs/flutter-apk/app-release.apk`
- Size: 72,798,906 bytes
- SHA-256: `0BD3C5AF507FE38E0D30BCEA3E5C2A7305211552F10C03711284EA9CF824BA70`
- APK Signature Scheme v2: verified.
- Number of signers: 1.
- Signing certificate: `CN=StudyGrades, OU=Mobile, O=StudyGrades, L=Cairo, ST=Cairo, C=EG`.
- Certificate SHA-256: `67B32E9EBEB392F0771D70C33883EC567B58F7A27B429251ACCF4D8D23BDA8E1`.

The new APK was installed on the existing Android 36 ATD emulator and launched
as `com.baselashraf.studygrades/.MainActivity`. The onboarding flow reached the
production login screen, the process retained the same PID after background and
foreground transitions, and the filtered Android error log contained zero
`FATAL EXCEPTION`/application crash matches. Visual evidence is stored outside
the repository at:

- `D:\StudyGrades_MobileApp\artifacts\studygrades_latest.png`
- `D:\StudyGrades_MobileApp\artifacts\studygrades_after_onboarding.png`

## Build environment

- Flutter: 3.44.3 stable.
- Dart: 3.12.2.
- Java: Temurin JDK 17.0.18.
- Android SDK: `D:\Android\Sdk` (Android 36, build-tools 36.0.0).
- Gradle cache: `D:\.gradle`; retained for faster future builds.
- Android build completed with the currently verified Gradle 8.12, AGP 8.9.1,
  and Kotlin 2.1.0 toolchain. Flutter reports future-deprecation warnings for
  these versions, but they are not current build failures.

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
