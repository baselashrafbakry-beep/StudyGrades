# StudyGrades 2026 🎓
## نظام رصد الدرجات الصوتي الاحترافي
## Professional Voice-Based Grading System

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Flutter](https://img.shields.io/badge/flutter-3.22.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Status](https://img.shields.io/badge/status-Production%20Ready-brightgreen)

---

## 📱 نظرة عامة
## 📱 Overview

**StudyGrades 2026** هو نظام متقدم لرصد درجات الطلاب باستخدام تقنية التعرف على الكلام. يوفر واجهة احترافية سهلة الاستخدام مع دعم كامل للغة العربية والأرقام العربية.

**StudyGrades 2026** is an advanced student grading system using speech recognition technology. It provides a professional, user-friendly interface with full Arabic language support.

### ✨ الميزات الرئيسية
### ✨ Key Features

- 🎤 **التعرف على الكلام**: تحويل الكلام العربي إلى درجات رقمية
- 📊 **إحصائيات متقدمة**: تحليل شامل لأداء الطلاب والفصول
- 💾 **تخزين آمن**: تشفير البيانات والنسخ الاحتياطية التلقائية
- 🌙 **الوضع الليلي**: دعم كامل للوضع الليلي
- 📱 **تطبيق متجاوب**: يعمل على الهواتف والأجهزة اللوحية والويب
- 🔐 **أمان عالي**: مصادقة آمنة وتشفير البيانات
- 🌍 **دعم عربي كامل**: واجهة عربية 100% مع دعم الأرقام العربية
- ⚡ **أداء عالي**: تطبيق سريع وخفيف الوزن
- 🔄 **مزامنة سحابية**: مزامنة البيانات عبر الأجهزة
- 📤 **تصدير متقدم**: تصدير البيانات بصيغ متعددة (CSV, PDF, Excel)

---

## 🚀 البدء السريع
## 🚀 Quick Start

### المتطلبات
- Flutter 3.22.0+
- Dart 3.2.0+
- iOS 12.0+ أو Android 5.0+

### التثبيت

```bash
# استنساخ المشروع
git clone https://github.com/baselashrafbakry-beep/StudyGrades.git
cd StudyGrades

# تثبيت الـ dependencies
flutter pub get

# تشغيل التطبيق
flutter run
```

### التشغيل على منصات مختلفة

```bash
# تشغيل على الويب
flutter run -d chrome

# تشغيل على Android
flutter run -d emulator-5554

# تشغيل على iOS
flutter run -d iPhone
```

---

## 📋 الهيكل
## 📋 Project Structure

```
StudyGrades/
├── lib/
│   ├── main.dart                          # نقطة البداية
│   ├── screens/                           # الشاشات
│   │   ├── splash_screen.dart
│   │   ├── login_screen.dart
│   │   ├── home_screen.dart
│   │   └── ...
│   ├── providers/                         # إدارة الحالة
│   │   ├── auth_provider.dart
│   │   ├── grading_provider.dart
│   │   └── theme_provider.dart
│   ├── services/                          # الخدمات
│   │   ├── storage_service.dart
│   │   ├── connectivity_service.dart
│   │   ├── admin_service.dart
│   │   ├── app_initialization_service.dart
│   │   └── ...
│   ├── utils/                             # الأدوات
│   │   ├── error_handler.dart
│   │   ├── error_recovery.dart
│   │   └── ...
│   ├── theme/                             # المظهر
│   │   └── app_theme.dart
│   └── models/                            # نماذج البيانات
│       └── ...
├── test/                                  # الاختبارات
├── pubspec.yaml                           # الـ dependencies
└── README.md                              # هذا الملف
```

---

## 🔧 التكوين
## 🔧 Configuration

### متغيرات البيئة

```bash
# .env
FLUTTER_ENV=development
API_URL=http://localhost:3000
LOG_LEVEL=debug
```

### إعدادات التطبيق

تحرير `lib/config/app_config.dart`:

```dart
class AppConfig {
  static const String appName = 'StudyGrades 2026';
  static const String appVersion = '1.0.0';
  static const String apiUrl = 'https://api.studygrades.com';
  // ... إعدادات أخرى
}
```

---

## 🎯 الاستخدام
## 🎯 Usage

### تسجيل الدخول

```
1. افتح التطبيق
2. أدخل بريدك الإلكتروني وكلمة المرور
3. اضغط "تسجيل الدخول"
```

### إضافة فصل جديد

```
1. اذهب إلى الشاشة الرئيسية
2. اضغط "إضافة فصل جديد"
3. أدخل اسم الفصل والسنة الدراسية
4. اضغط "حفظ"
```

### تسجيل درجة صوتياً

```
1. اختر الفصل
2. اختر الطالب
3. اضغط على زر الميكروفون
4. تحدث بالدرجة (مثلاً: "تسعة وتسعون")
5. انتظر التحويل والتأكيد
6. اضغط "حفظ"
```

---

## 📊 الإحصائيات
## 📊 Statistics

### عرض الإحصائيات

```
1. اذهب إلى تبويب "الإحصائيات"
2. اختر الفصل أو الطالب
3. عرض الرسوم البيانية والإحصائيات
```

### تصدير البيانات

```
1. اذهب إلى "الإعدادات"
2. اختر "تصدير البيانات"
3. اختر الصيغة (CSV, PDF, Excel)
4. اضغط "تصدير"
```

---

## 🔐 الأمان
## 🔐 Security

### معايير الأمان

- ✅ تشفير البيانات المحلية
- ✅ اتصالات HTTPS آمنة
- ✅ مصادقة آمنة
- ✅ معالجة آمنة للأخطاء
- ✅ عدم تسرب البيانات الحساسة

### الأذونات المطلوبة

```xml
<!-- Android -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />

<!-- iOS -->
NSMicrophoneUsageDescription
NSPhotoLibraryUsageDescription
```

---

## 🧪 الاختبار
## 🧪 Testing

### تشغيل الاختبارات

```bash
# جميع الاختبارات
flutter test

# اختبار محدد
flutter test test/services/storage_service_test.dart

# مع تقرير التغطية
flutter test --coverage
```

### اختبارات التكامل

```bash
# تشغيل اختبارات التكامل
flutter drive --target=test_driver/app.dart
```

---

## 📈 الأداء
## 📈 Performance

### معايير الأداء

| المقياس | الهدف |
|--------|-------|
| وقت البدء | < 2 ثانية |
| تحميل الشاشة | < 500 مللي ثانية |
| استهلاك الذاكرة | < 100 MB |
| استهلاك البطارية | < 5% في الساعة |

### تحسين الأداء

```bash
# بناء الإصدار
flutter build apk --release
flutter build ios --release

# تحليل الأداء
flutter run --profile
```

---

## 🐛 استكشاف الأخطاء
## 🐛 Troubleshooting

### المشكلة: الشاشة البيضاء عند الفتح

**الحل:**
1. تحقق من رسائل الخطأ في console
2. تأكد من تحميل جميع الخدمات
3. تحقق من الاتصال بالإنترنت

### المشكلة: عدم عمل الميكروفون

**الحل:**
1. تحقق من الأذونات
2. تحقق من توفر الميكروفون
3. أعد تشغيل التطبيق

### المشكلة: بطء التطبيق

**الحل:**
1. أغلق التطبيقات الأخرى
2. امسح ذاكرة التطبيق
3. أعد تثبيت التطبيق

---

## 📚 التوثيق
## 📚 Documentation

- [دليل النشر](DEPLOYMENT_INSTRUCTIONS.md)
- [دليل الاختبار](TESTING_QA_GUIDE.md)
- [تحليل المشاكل](CRITICAL_ISSUES_ANALYSIS.md)

---

## 🤝 المساهمة
## 🤝 Contributing

نرحب بالمساهمات! يرجى:

1. Fork المشروع
2. إنشاء فرع جديد (`git checkout -b feature/amazing-feature`)
3. Commit التغييرات (`git commit -m 'Add amazing feature'`)
4. Push إلى الفرع (`git push origin feature/amazing-feature`)
5. فتح Pull Request

---

## 📝 الترخيص
## 📝 License

هذا المشروع مرخص تحت رخصة MIT. انظر ملف [LICENSE](LICENSE) للتفاصيل.

---

## 👨‍💻 المطور
## 👨‍💻 Developer

**باسل أشرف بكري**
- GitHub: [@baselashrafbakry-beep](https://github.com/baselashrafbakry-beep)
- البريد: basil@studygrades.dev

---

## 🙏 شكر وتقدير
## 🙏 Acknowledgments

شكر خاص لـ:
- فريق Flutter
- مجتمع Flutter العربي
- جميع المساهمين والمختبرين

---

## 📞 التواصل
## 📞 Contact

للأسئلة والاقتراحات:
- 📧 البريد: support@studygrades.com
- 🐦 تويتر: [@StudyGrades2026](https://twitter.com/StudyGrades2026)
- 💬 Discord: [StudyGrades Community](https://discord.gg/studygrades)

---

## 🗺️ خارطة الطريق
## 🗺️ Roadmap

### الإصدار 1.1.0 (قريباً)
- [ ] دعم الكاميرا لمسح الرموز
- [ ] تقارير متقدمة
- [ ] مشاركة البيانات مع الآباء

### الإصدار 1.2.0
- [ ] تطبيق ويب متقدم
- [ ] تطبيق سطح المكتب
- [ ] دعم لغات إضافية

### الإصدار 2.0.0
- [ ] الذكاء الاصطناعي للتنبؤ بالأداء
- [ ] تحليل متقدم للبيانات
- [ ] تكامل مع الأنظمة التعليمية

---

**آخر تحديث:** مايو 2026  
**الإصدار:** 1.0.0  
**الحالة:** جاهز للإنتاج ✅

---

<div align="center">

**صُنع بـ ❤️ من قبل فريق StudyGrades**

Made with ❤️ by StudyGrades Team

</div>
