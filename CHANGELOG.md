# سجل التغييرات — Changelog

جميع التغييرات الملحوظة في هذا المشروع موثّقة في هذا الملف.

التنسيق مبني على [Keep a Changelog](https://keepachangelog.com/ar/1.1.0/)،
ويتبع المشروع [الإصدار الدلالي (Semantic Versioning)](https://semver.org/lang/ar/).

---

## [2.0.0+1] — 2026-07-07

### 🚀 تدقيق شامل قبل الإطلاق التجاري (Commercial Launch Audit)

#### ✨ ميزات جديدة (Added)
- تكامل تجاري كامل مع Paymob لبوابة الدفع المصرية (اشتراكات، تجديد، استرداد)
- تحقق ترخيص RSA-2048/PSS لمنع القرصنة والتلاعب بالاشتراكات
- تشفير Hive AES-256 لبيانات الطلاب والدرجات المحلية
- تصدير PDF رسمي بجانب Excel (كشوف درجات قابلة للطباعة)
- اختبار ضغط 100 طالب على تصدير Excel للتحقق من الأداء تحت الحمل
- تقسيم APK حسب ABI (armeabi-v7a / arm64-v8a / x86_64) لتقليل حجم التحميل حتى ~60%

#### 🛠️ إصلاحات حرجة (Fixed)
- إصلاح هوية الحزمة (Package Identity): توحيد com.studygrades.app عبر جميع ملفات Android (build.gradle.kts, AndroidManifest.xml, MainActivity.kt) و iOS (project.pbxproj، 6 مواقع)، بعد اكتشاف مشكلة ارتجاع القيم القديمة بسبب ذاكرة تخزين مؤقت لخدمة Gradle/Kotlin Daemon
- التحقق الثنائي من الهوية: تأكيد com.studygrades.app داخل ملفات APK المُجمَّعة (عبر pyaxmlparser) وملف AAB (عبر فحص بايتات protobuf الخام)، وليس فقط في الكود المصدري
- إصلاح خادم المعاينة العالق: حل مشكلة توقف المعاينة عند Checking service status بسبب عملية خادم Python قديمة كانت تشير إلى مجلد build/web محذوف بعد flutter clean
- تحديث proguard-rules.pro لمطابقة اسم الحزمة الجديد

#### 🧹 تنظيف المستودع (Repository Hygiene)
- إزالة الملفات القديمة غير الضرورية من التتبع: pubspec.yaml.original, pubspec.lock.backup, fallback.log, .pub-cache-policy, .pub-resolve-policy
- إزالة README_FINAL.md (نسخة مكررة تحتوي على معلومات غير دقيقة: إصدار وترخيص وFlutter version خاطئة)
- إزالة CRITICAL_ISSUES_ANALYSIS.md (ملاحظات تصحيح أخطاء قديمة تتعارض مع معايير الكود الحالية)
- تحديث .gitignore لمنع تتبع ملفات log و backup و original مستقبلاً
- تصحيح المرجع القديم لاسم الحزمة com.voicegrader.grader في ios/BUILD_IOS.md
- تحديث DEPLOYMENT_INSTRUCTIONS.md و TESTING_QA_GUIDE.md بأرقام إصدار صحيحة وتصحيحات فنية
- فحص أمني كامل لتاريخ Git للتأكد من عدم تسريب أي مفاتيح أو أسرار — النتيجة: نظيف 100%

#### 🧪 اختبارات الجودة
- 198 اختبار وحدة جميعها ناجحة (ارتفاع من 35 اختبار في v1.0.0)
- flutter analyze: 0 أخطاء، 0 تحذيرات
- dart format: تنسيق موحّد لكل الملفات

---

## [1.0.0+1] — 2026-05-05

### 🎉 الإصدار الأول للإنتاج

#### ✨ ميزات جديدة (Added)
- **التسجيل الصوتي الذكي (Auto-mode)**: ضغطة واحدة لبدء جلسة كاملة
- **التعرّف الفوري على الدرجات** بالعربية (لاتيني، عربي-هندي، كلمات)
- **الانتقال التلقائي** بين بنود التقييم بعد كل درجة منطوقة
- **رسالة تأكيد** قبل الانتقال للطالب التالي مع عرض الإجمالي والنسبة
- **9 أوامر صوتية**: التالي، السابق، حفظ، مسح، غائب، إيقاف، تأكيد، كاملة، صفر
- **دعم الكسور المنطوقة**: نص، ربع، تلت، ثلاثة أرباع
- **تصدير Excel رسمي** مطابق للنموذج اليدوي:
  - رؤوس عربية، اتجاه RTL
  - معلومات المدرسة والفصل والمعلم
  - صف الدرجات القصوى وصف النسب النهائية
  - تلوين تنازلي حسب الأداء + صفوف Zebra
  - إحصائيات الفصل (متوسط، نسبة نجاح، أعلى/أدنى)
  - 3 حقول توقيع (المعلم، الإدارة، المراجع)
- **العمل بدون اتصال** مع مزامنة تلقائية عند عودة الإنترنت
- **JWT (Access + Refresh)** مع تجديد تلقائي للرمز
- **إعادة محاولة تصاعدية** (exponential backoff) للطلبات الفاشلة

#### 🛠️ تحسينات (Changed / Improved)
- توسيع `NLPParser` لدعم >20 صيغة رقمية مصرية
- نقل من `WillPopScope` إلى `PopScope` (Flutter 3.35.4)
- استخدام `withValues(alpha:)` بدل `withOpacity()` المهجور
- تنظيف الكود وإزالة `print()` لصالح `debugPrint`
- إعادة هيكلة `GradingProvider` مع `saveAllStudents()` ومزامنة جزئية
- إضافة `replacePendingSyncs()` في `StorageService`

#### ⚡ تحسينات الإنتاج
- **ProGuard مفعّل** مع قواعد مخصصة لجميع الإضافات الأصلية
- **Resource Shrinking مفعّل** لتقليل حجم الموارد
- **packaging excludes** لإزالة ملفات META-INF غير الضرورية
- تقليل حجم APK من **59MB → 56MB** (وفّر 3MB / ~5%)
- توقيع رقمي **RSA 2048-bit** صالح حتى سبتمبر 2053

#### 🧪 اختبارات الجودة
- **35 اختبار وحدة** جميعها ناجحة
- **تغطية 66.43%** للملفات المختبرة
- **flutter analyze**: 0 أخطاء، 0 تحذيرات

#### 🤖 البنية التحتية للتطوير
- **GitHub Actions CI/CD** مع 3 jobs (analyze, build-apk, build-web)
- **اختبار تلقائي** عند كل push/PR
- **artifacts** تلقائية لـ APK و Web build

#### 🐛 إصلاحات أخطاء (Fixed)
- إصلاح `WillPopScope deprecated` في `grading_screen.dart`
- إزالة `dart:io` غير المستخدم في `voice_service.dart`
- إصلاح حساب `total` ليتجاهل قيم NaN/Infinity
- معالجة آمنة للقيم النصية في `GradeField.fromJson`

---

## الروابط
- [GitHub Repository](https://github.com/baselashrafbakry-beep/StudyGrades)
- [Production Site](https://studygrades-2026.netlify.app)
- [APK Download](https://studygrades-2026.netlify.app/downloads/StudyGrades2026.apk)
- [AAB Download](https://studygrades-2026.netlify.app/downloads/StudyGrades2026.aab)
- [PWA](https://studygrades-2026.netlify.app/app/)
