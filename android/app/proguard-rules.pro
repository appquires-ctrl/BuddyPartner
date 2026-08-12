# Proguard rules for BuddyPartner (release build optimizations)

# Agora RTC SDK rules
-keep class io.agora.**{*;}
-dontwarn io.agora.**

# Flutter and standard android rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class androidx.lifecycle.** { *; }

# Keep platform-specific methods
-keepclasseswithmembers class * {
    native <methods>;
}

# Ignore warnings from Google Play Core classes referenced by Flutter Embedding
-dontwarn com.google.android.play.core.**

