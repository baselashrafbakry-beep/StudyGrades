# StudyGrades 2026 - نشر التطبيق
# StudyGrades 2026 - Deployment Instructions

## 🚀 نشر على Render (Backend)
## 🚀 Deployment on Render (Backend)

### الخطوات:

1. **تسجيل الدخول إلى Render:**
   - اذهب إلى https://render.com
   - سجل الدخول باستخدام حسابك

2. **إنشاء خدمة جديدة:**
   - اضغط على "New +"
   - اختر "Web Service"
   - اربط مستودع GitHub الخاص بك

3. **إعدادات الخدمة:**
   - **Name**: `studygrades-backend`
   - **Environment**: `Docker`
   - **Build Command**: `flutter pub get && flutter build web --release`
   - **Start Command**: `python3 -m http.server $PORT --directory build/web --bind 0.0.0.0`
   > ⚠️ **ملاحظة مهمة**: `flutter run -d web` هو أمر تطوير (dev mode) فقط ولا يصلح للإنتاج — يجب بناء المشروع أولاً (`flutter build web --release`) ثم تقديم محتوى `build/web` عبر خادم ملفات ثابتة (Static File Server) كما هو موضح أعلاه.

4. **متغيرات البيئة:**
   ```
   FLUTTER_ENV=production
   API_URL=<ضع رابط الـ Backend الفعلي هنا>
   ```
   > ⚠️ يجب استبدال `API_URL` بعنوان الـ Backend الفعلي والمُتحقق منه؛ الروابط النائبة (placeholder) لا تعمل.

5. **النشر:**
   - اضغط "Deploy"
   - انتظر حتى ينتهي البناء والنشر

---

## 🌐 نشر على Netlify (Frontend)
## 🌐 Deployment on Netlify (Frontend)

### الخطوات:

1. **تسجيل الدخول إلى Netlify:**
   - اذهب إلى https://netlify.com
   - سجل الدخول باستخدام حسابك

2. **ربط المستودع:**
   - اضغط على "Add new site"
   - اختر "Import an existing project"
   - اختر GitHub
   - اختر مستودع `StudyGrades`

3. **إعدادات البناء:**
   - **Build command**: `flutter build web --release`
   - **Publish directory**: `build/web`

4. **متغيرات البيئة:**
   ```
   FLUTTER_ENV=production
   API_URL=<ضع رابط الـ Backend الفعلي هنا>
   ```

5. **النشر:**
   - اضغط "Deploy site"
   - انتظر حتى ينتهي البناء والنشر

---

## 📱 بناء APK و IPA
## 📱 Building APK and IPA

### بناء APK (Android):

```bash
flutter build apk --release
# أو للحصول على split APKs
flutter build apk --split-per-abi --release
```

الملفات ستكون في: `build/app/outputs/flutter-apk/`

### بناء IPA (iOS):

```bash
flutter build ios --release
# ثم استخدم Xcode لإكمال البناء
open ios/Runner.xcworkspace
```

---

## ✅ اختبار النشر
## ✅ Testing Deployment

### اختبار محلي:

```bash
# تشغيل على الويب
flutter run -d chrome

# تشغيل على Android
flutter run -d emulator-5554

# تشغيل على iOS
flutter run -d iPhone
```

### اختبار الإنتاج:

1. **اختبر الرابط المنشور:**
   - تحقق من أن الموقع يحمل بدون أخطاء
   - اختبر جميع الميزات الأساسية

2. **اختبر الأداء:**
   - استخدم Chrome DevTools
   - تحقق من سرعة التحميل
   - تحقق من استهلاك الذاكرة

3. **اختبر على أجهزة حقيقية:**
   - اختبر على iOS و Android
   - اختبر على اتصالات مختلفة
   - اختبر مع بطارية منخفضة

---

## 🔧 استكشاف الأخطاء
## 🔧 Troubleshooting

### المشكلة: الشاشة البيضاء عند الفتح

**الحل:**
1. تحقق من رسائل الخطأ في console
2. تأكد من تحميل جميع الخدمات بنجاح
3. تحقق من توفر الاتصال بالإنترنت

### المشكلة: بطء التحميل

**الحل:**
1. تحقق من سرعة الإنترنت
2. تحقق من أداء الخادم
3. قم بتحسين الصور والموارد

### المشكلة: أخطاء في الوصول

**الحل:**
1. تحقق من CORS settings
2. تحقق من متغيرات البيئة
3. تحقق من صحة الـ API endpoints

---

## 📊 المراقبة والتحليل
## 📊 Monitoring and Analytics

### استخدام Render Analytics:
- اذهب إلى لوحة التحكم
- اختر "Analytics"
- راقب الأداء والأخطاء

### استخدام Netlify Analytics:
- اذهب إلى "Analytics"
- راقب عدد الزيارات والأخطاء
- راقب سرعة التحميل

---

## 🔐 الأمان
## 🔐 Security

### قائمة التحقق:

- [ ] تحديث جميع الـ dependencies
- [ ] تفعيل HTTPS
- [ ] تفعيل CORS بشكل صحيح
- [ ] إخفاء المفاتيح الحساسة
- [ ] تفعيل المصادقة الآمنة
- [ ] تفعيل التشفير للبيانات الحساسة

---

## 📝 ملاحظات مهمة

1. **استخدم الرموز المقدمة بحذر:**
   - لا تشارك الرموز في الكود العام
   - استخدم متغيرات البيئة فقط

2. **قم بالنسخ الاحتياطية:**
   - قم بنسخ احتياطية للبيانات بانتظام
   - احتفظ بنسخ احتياطية من قاعدة البيانات

3. **راقب الأداء:**
   - راقب سرعة التحميل
   - راقب استهلاك الموارد
   - راقب الأخطاء

---

**تم التحديث:** يوليو 2026
**الإصدار:** 2.0.0
