# سجل التغييرات — Changelog

جميع التغييرات الملحوظة في هذا المشروع موثّقة في هذا الملف.

التنسيق مبني على [Keep a Changelog](https://keepachangelog.com/ar/1.1.0/)،
ويتبع المشروع [الإصدار الدلالي (Semantic Versioning)](https://semver.org/lang/ar/).

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
