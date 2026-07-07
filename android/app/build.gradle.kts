// ✅ CRITICAL: Required imports for signing configuration
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load signing properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.studygrades.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.studygrades.app"
        // App needs minSdk 23+ for speech_to_text, record, and secure storage
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // CRITICAL: Disabled minify/shrink to prevent ProGuard/R8 from
            // stripping reflection-based classes used by Flutter plugins.
            // Earlier builds with minify=true caused the app to freeze on
            // splash because R8 removed flutter_secure_storage / Hive /
            // speech_to_text classes that are loaded reflectively.
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/license.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/notice.txt",
                "META-INF/ASL2.0",
                "META-INF/*.kotlin_module"
            )
        }
    }

    // ✅ تحسين حجم التطبيق (App Size Optimization) بطريقة آمنة تماماً:
    // تقسيم APK حسب معمارية المعالج (ABI) بدلاً من "universal APK" واحد
    // يحوي كل المعماريات معاً (armeabi-v7a + arm64-v8a + x86_64). هذا
    // يقلّل حجم الملف الذي يُنزّله المستخدم النهائي بنسبة تصل لـ ~60%
    // دون أي تأثير على كود التطبيق أو الـ reflection (بعكس isMinifyEnabled
    // المُعطَّل عمداً أعلاه لأسباب موثَّقة). مهم بشكل خاص لأن ملف الإعداد
    // التجاري (StudyGrades-commercial.env) يحدد DISTRIBUTION_CHANNEL=direct
    // — أي توزيع مباشر لملف APK للمستخدم (ليس عبر Google Play الذي يُوزّع
    // تلقائياً الـ ABI المناسب من AAB بدون الحاجة لهذا التقسيم اليدوي).
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = true // يُنتج أيضاً نسخة شاملة كخيار احتياطي متوافق مع كل الأجهزة
        }
    }
}

flutter {
    source = "../.."
}




