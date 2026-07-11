# StudyGrades Store Submission

## Public URLs

- Privacy policy: `https://studygrades-2026.netlify.app/privacy.html`
- Terms of use: `https://studygrades-2026.netlify.app/terms.html`
- Support: `https://studygrades-2026.netlify.app/support.html`
- Support email: `baselashraf.bakry@gmail.com`

## Google Play listing

- App name: `StudyGrades`
- Default language: Arabic (`ar-EG`)
- Category: Education
- Package id: `com.studygrades.app`
- Short description: `رصد درجات الطلاب صوتياً ويدوياً مع العمل دون إنترنت وتقارير دقيقة`
- Full description:

  `StudyGrades يساعد المعلمين والمدارس على رصد درجات الطلاب بسرعة ودقة. يدعم الإدخال الصوتي العربي والإدخال اليدوي، العمل دون إنترنت، المزامنة التلقائية، الإحصاءات، وتصدير تقارير Excel وPDF وفق صلاحيات الاشتراك. يحمي التطبيق الحسابات عبر جلسات مشفرة وحدود للأجهزة، ويتيح للإدارة تنظيم المستخدمين والفصول والمواد من مكان واحد.`

The app requires an account created by the service administrator. Supply a
dedicated, non-production review account in Play Console's App access section.
Never commit review credentials to this repository.

## Google Play Data safety draft

Review these declarations against the final Play Console wording before
submission:

- Data encrypted in transit: Yes (HTTPS).
- Account deletion/data deletion request: Available through the support email.
- Data sold: No.
- Advertising or cross-app tracking: No.
- Personal info collected: user ID/username, name, email address, and phone
  number; used for account management, authentication, support, and payments.
- App activity/user content collected: class catalog, student identifiers or
  names, grades, and generated reports; used only for the education service.
- Device or other IDs collected: a random installation identifier; used for
  security and subscription device limits.
- Financial data collected by StudyGrades: purchase history/payment references.
  Full card details are handled by Paymob and are not stored by StudyGrades.
- Diagnostics collected: limited security and error records used for fraud
  prevention, reliability, and support.
- Audio collected by the StudyGrades server: No. Current voice recognition is
  performed through the device speech service and server transcription is
  disabled.
- Third-party processing: Netlify hosts service data; Paymob processes checkout
  contact and payment data. These are service providers, not advertising SDKs.

## Permissions disclosure

`RECORD_AUDIO` is requested only when the user starts voice entry. Manual grade
entry remains available when microphone permission is denied. The microphone is
declared as optional hardware in the Android manifest.

## Audience and review notes

- Intended users: teachers, school administrators, and authorized education
  staff.
- The app is not designed for direct use by children and contains no advertising.
- Student records are entered and controlled by the subscribing school or
  authorized teacher.
- Content rating: no violence, sexual content, gambling, or user-to-user public
  communication.
- Provide the signed AAB from `D:\StudyGrades_MobileApp\artifacts` for Play
  Console. The APK is for controlled direct testing only.

## Apple submission notes

The same public privacy URL can be used as the required App Store privacy policy
URL. App Store Connect privacy answers must include account identifiers,
education/user content, purchase history, device identifiers, and diagnostics as
described above. Microphone and speech recognition usage descriptions are
already present in `ios/Runner/Info.plist`.
