# Flutter ProGuard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# speech_to_text
-keep class com.csdcorp.speech_to_text.** { *; }

# record (audio recording)
-keep class com.llfbandit.record.** { *; }

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# audioplayers
-keep class xyz.luan.audioplayers.** { *; }

# share_plus
-keep class dev.fluttercommunity.plus.share.** { *; }

# path_provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# connectivity_plus
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Hive
-keep class * extends io.flutter.plugin.common.MethodCallHandler { *; }

# JSON serialization
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings {
    <fields>;
}

# Dio / OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# General Android
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Suppress warnings for missing classes
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Keep model classes (data classes)
-keep class com.studygrades.app.models.** { *; }

# ────────── COMPREHENSIVE PROGUARD RULES (FINAL) ──────────

# google_fonts (reflection-heavy)
-keep class com.google.fonts.** { *; }
-dontwarn com.google.fonts.**

# fl_chart
-keep class fl_chart.** { *; }

# Hive type adapters
-keep class **$HiveFieldAdapter { *; }
-keep class **$HiveTypeAdapter { *; }
-keepclassmembers class * {
    @hive.HiveField *;
    @hive.HiveType *;
}

# excel package
-keep class com.example.excel.** { *; }
-keep class * implements java.io.Serializable { *; }

# Dio retrofit/interceptors safety
-keep class dio.** { *; }
-dontwarn dio.**

# Audio: audioplayers + record
-keep class xyz.luan.audioplayers.** { *; }
-keep class com.llfbandit.record.** { *; }

# Lottie
-keep class com.airbnb.lottie.** { *; }
-dontwarn com.airbnb.lottie.**

# Reflection - keep all annotation processors
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeInvisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations
-keepattributes RuntimeInvisibleParameterAnnotations

# Keep all serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Don't strip Generic Signature (needed for Dio/Hive)
-keepattributes Signature,Exceptions,*Annotation*,EnclosingMethod,InnerClasses
