# StudyGrades 2026 — تطبيق الدرجات الصوتي

[![Flutter](https://img.shields.io/badge/Flutter-3.35.4-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.9.2-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-Private-red.svg)](#)
[![Build](https://img.shields.io/badge/Build-Passing-brightgreen)](#)

تطبيق مبتكر لإدخال درجات الطلاب صوتياً باللهجة المصرية، مع وضع تلقائي ذكي وتصدير Excel رسمي مطابق للنموذج اليدوي المعتمد في المدارس.

---

## ✨ الميزات الرئيسية

### 🎙️ التسجيل الصوتي الذكي
- **وضع تلقائي (Auto-mode)**: ضغطة واحدة على الميكروفون لبدء الجلسة
- **التعرف الفوري** على الأرقام بالعربية والمصرية (٠–١٠٠، نص، ربع، تلت...)
- **انتقال تلقائي** بين بنود التقييم بعد كل درجة منطوقة
- **رسالة تأكيد** قبل الانتقال إلى الطالب التالي مع عرض الإجمالي والنسبة
- **أوامر صوتية**: التالي، السابق، حفظ، مسح، غائب، إيقاف، تأكيد، كاملة

### 📊 تصدير Excel رسمي
- محاكاة كاملة لكشف الدرجات اليدوي
- رؤوس عربية، اتجاه RTL، تنسيق جدولي احترافي
- معلومات المدرسة، الفصل، المادة، المعلم، التاريخ
- صف الدرجات القصوى، صف النسب المئوية النهائية
- تلوين تنازلي حسب الأداء، صفوف Zebra
- إحصائيات الفصل (متوسط، نسبة نجاح، أعلى/أدنى درجة)
- ثلاثة حقول توقيع (المعلم، الإدارة، المراجع)

### 🌐 العمل بدون اتصال
- حفظ محلي عبر Hive للحالات بدون إنترنت
- مزامنة تلقائية عند عودة الاتصال
- إعادة محاولة تصاعدية (exponential backoff) لطلبات API

### 🔐 الأمان
- JWT (Access + Refresh tokens) مع تحديث تلقائي
- تخزين آمن للبيانات الحساسة عبر Flutter Secure Storage
- توقيع APK بمفتاح RSA 2048-bit (صالح حتى 2053)

---

## 🛠️ التقنيات المستخدمة

| الفئة | التقنية |
|-------|----------|
| الواجهة | Flutter 3.35.4 + Material Design 3 |
| اللغة | Dart 3.9.2 |
| إدارة الحالة | Provider |
| التخزين المحلي | Hive + SharedPreferences |
| الشبكة | Dio + HTTP |
| الصوت | speech_to_text + record |
| التصدير | excel + share_plus |
| المخططات | fl_chart + percent_indicator |

---

## 📦 البناء والتشغيل

### المتطلبات
- Flutter SDK 3.35.4
- Dart SDK 3.9.2
- Android SDK 35

### التثبيت
```bash
git clone https://github.com/baselashrafbakry-beep/StudyGrades.git
cd StudyGrades
flutter pub get
```

### التشغيل
```bash
# Web
flutter run -d chrome

# Android
flutter run -d android

# Build Production APK
flutter build apk --release

# Build App Bundle for Play Store
flutter build appbundle --release
```

---

## 🏗️ هيكل المشروع

```
lib/
├── models/         # نماذج البيانات (Student, Hierarchy, User...)
├── providers/      # إدارة الحالة (Auth, Grading, Theme)
├── screens/        # شاشات التطبيق
├── services/       # خدمات API، الصوت، التحليل، التخزين
├── widgets/        # مكونات الواجهة القابلة لإعادة الاستخدام
└── utils/          # أدوات مساعدة
```

---

## 🚀 الإصدارات المنشورة

- **APK**: https://studygrades-2026.netlify.app/downloads/StudyGrades2026.apk
- **AAB**: https://studygrades-2026.netlify.app/downloads/StudyGrades2026.aab
- **PWA**: https://studygrades-2026.netlify.app/app/

> ⚠️ **ملاحظة**: نقطة نهاية الـ API المذكورة سابقاً (`pythonanywhere.com/api/mobile/`) غير متاحة حالياً (404) — يُرجى تحديث عنوان الـ Backend الفعلي هنا عند توفره.

---

## ✅ ضمان الجودة

- ✓ `flutter analyze` — 0 أخطاء، 0 تحذيرات
- ✓ APK موقّع رقمياً (SHA256 RSA-2048)
- ✓ ProGuard مفعّل لتقليل الحجم
- ✓ تحسين الموارد (resource shrinking)
- ✓ CI/CD عبر GitHub Actions

---

## 📝 الترخيص

ملكية خاصة — جميع الحقوق محفوظة © 2026

---

## 👤 المطور

تم تطوير هذا المشروع بواسطة فريق StudyGrades 2026.
