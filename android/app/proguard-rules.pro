# Flutter Local Notifications - Gson TypeToken fix
# https://github.com/MaikuB/flutter_local_notifications/issues/2074

-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Keep generic signatures (required for Gson)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Flutter Local Notifications plugin
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# Keep TypeToken
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Flutter WebRTC
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# General Flutter rules
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

