# 🍎 دليل بناء iOS IPA — StudyGrades 2026

## ⚠️ متطلبات أساسية
بناء IPA لنظام iOS يتطلب جهاز **macOS** مع **Xcode** مثبتاً (لا يمكن بناؤه على Linux/Windows).

## 📋 المتطلبات

| العنصر | المواصفة |
|--------|----------|
| نظام التشغيل | macOS 12 (Monterey) أو أحدث |
| Xcode | 15.0 أو أحدث |
| Flutter SDK | 3.35.4 (مطابق للسandbox) |
| CocoaPods | آخر إصدار (`sudo gem install cocoapods`) |
| Apple Developer Account | $99/year (للنشر على App Store) |

## ⚙️ الإعدادات الجاهزة في المشروع

تم ضبط كل التالي مسبقاً:

✅ **Bundle Identifier**: `com.studygrades.app` (مطابق لـ Android)
✅ **Display Name**: `StudyGrades 2026`
✅ **Bundle Name**: `StudyGrades`
✅ **Orientation**: Portrait فقط
✅ **Region**: `ar` (Arabic)
✅ **Localizations**: `ar`, `en`
✅ **App Category**: Education
✅ **HTTPS Only**: مفعّل

### 🔐 صلاحيات iOS المضبوطة في `Info.plist`:
- `NSMicrophoneUsageDescription` — للإدخال الصوتي
- `NSSpeechRecognitionUsageDescription` — للتعرّف على الكلام
- `NSPhotoLibraryUsageDescription` — لحفظ التقارير
- `NSPhotoLibraryAddUsageDescription` — لإضافة الملفات للمعرض
- `NSDocumentsFolderUsageDescription` — لتصدير CSV

## 🚀 خطوات البناء على macOS

### 1. تنزيل المشروع وإعداده
```bash
git clone <repo-url> studygrades
cd studygrades
flutter pub get
```

### 2. تثبيت Pods
```bash
cd ios
pod install --repo-update
cd ..
```

### 3. فتح المشروع في Xcode
```bash
open ios/Runner.xcworkspace
```
> ⚠️ افتح `.xcworkspace` وليس `.xcodeproj`

### 4. تكوين التوقيع (Signing)
- في Xcode: حدد **Runner** ← **Signing & Capabilities**
- اختر **Team** (حساب Apple Developer)
- تأكد من **Bundle Identifier** = `com.studygrades.app`
- اضغط **Automatically manage signing**

### 5. بناء IPA للتوزيع

**أ) للاختبار على جهازك (Development):**
```bash
flutter build ios --release
```

**ب) للنشر على App Store:**
```bash
flutter build ipa --release
```
الملف الناتج: `build/ios/ipa/StudyGrades.ipa`

**ج) للتوزيع الداخلي (Ad-Hoc / Enterprise):**
```bash
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

### 6. الرفع إلى App Store Connect
```bash
xcrun altool --upload-app -f build/ios/ipa/StudyGrades.ipa \
  -u <your-apple-id> -p <app-specific-password>
```
أو استخدم **Transporter** من Mac App Store.

## 🌐 البديل: PWA على iPhone (بدون macOS)

إذا لم يتوفر macOS، يمكن للمستخدمين تثبيت التطبيق كـ **PWA** عبر Safari:
1. افتح: `https://5060-i1pqquuiprxjis16s9egz-2e77fc33.sandbox.novita.ai/`
2. اضغط زر المشاركة ⬆️
3. اختر "Add to Home Screen"
4. التطبيق سيعمل كأي تطبيق عادي.

## 📝 ملاحظات

- **حسابات المستخدمين** و**لوحة الإدارة** تعمل بنفس الطريقة على iOS و Android (Backend موحّد).
- **الإدخال الصوتي** يستخدم Speech Framework من Apple بشكل تلقائي.
- **التشفير** و **JWT** يعمل بنفس آلية Android.

## 🆘 مشاكل شائعة

### "No team selected"
حل: افتح Xcode ← Preferences ← Accounts ← أضف Apple ID.

### "Provisioning profile doesn't include this device"
حل: من Xcode، اربط جهازك ثم أعد البناء.

### "Pod install failed"
حل:
```bash
cd ios
rm -rf Pods Podfile.lock
pod install --repo-update
```

---
**تطوير: باسل أشرف** • © 2026 StudyGrades
