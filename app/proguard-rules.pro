# kotlinx.serialization (yalnızca JsonElement API'si kullanılır)
-dontwarn kotlinx.serialization.**
-keep class kotlinx.serialization.json.** { *; }
# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
# Tink (androidx.security:security-crypto) -> Error Prone annotation'ları (yalnızca derleme zamanı)
-dontwarn com.google.errorprone.annotations.CanIgnoreReturnValue
-dontwarn com.google.errorprone.annotations.CheckReturnValue
-dontwarn com.google.errorprone.annotations.Immutable
-dontwarn com.google.errorprone.annotations.RestrictedApi
-dontwarn com.google.errorprone.annotations.**
