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
fun signingProperty(name: String): String? =
    keystoreProperties.getProperty(name)?.trim()?.takeIf { it.isNotEmpty() }

val releaseStoreFile = signingProperty("storeFile")?.let { file(it) }
val hasReleaseKeystore =
    signingProperty("keyAlias") != null &&
    signingProperty("keyPassword") != null &&
    releaseStoreFile?.isFile == true &&
    signingProperty("storePassword") != null

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
            keyAlias = signingProperty("keyAlias")
            keyPassword = signingProperty("keyPassword")
            storeFile = releaseStoreFile
            storePassword = signingProperty("storePassword")
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
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
}

flutter {
    source = "../.."
}

gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any {
        it.name.contains("Release", ignoreCase = true)
    }
    if (releaseRequested && !hasReleaseKeystore) {
        throw GradleException(
            "Release signing is required. Configure android/key.properties " +
                "with keyAlias, keyPassword, storeFile, and storePassword. " +
                "storeFile must point to an existing keystore file."
        )
    }
}

