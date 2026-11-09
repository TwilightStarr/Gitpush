plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// ---- Sürüm ------------------------------------------------------------------------------
// CI, sürümü otomatik hesaplar (.github/scripts/next_version.py) ve -PVERSION_NAME=X.Y.Z ile verir.
// Verilmezse (yerel derleme) version.properties içindeki taban sürüm "-dev" ekiyle kullanılır.
// versionCode, sürümden türetilir: MAJOR*1_000_000 + MINOR*1_000 + PATCH  (her yeni sürümde artar).
val baseVersion: String = java.util.Properties()
    .also { p -> rootProject.file("version.properties").inputStream().use { p.load(it) } }
    .getProperty("BASE_VERSION")
val appVersionName: String = (project.findProperty("VERSION_NAME") as String?)
    ?.takeIf { it.isNotBlank() } ?: "$baseVersion-dev"
val appVersionCode: Int = appVersionName.substringBefore('-').split('.').map { it.toInt() }
    .let { (major, minor, patch) -> major * 1_000_000 + minor * 1_000 + patch }

android {
    namespace = "com.example.gitpush"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.example.gitpush"
        minSdk = 24
        targetSdk = 34
        versionCode = appVersionCode
        versionName = appVersionName

        // Herkese açık OAuth Client ID (Device Flow). client_secret asla istemciye konmaz.
        // Kullanım: ./gradlew assembleDebug -PGITHUB_CLIENT_ID=<client_id>
        val clientId = (project.findProperty("GITHUB_CLIENT_ID") as String?) ?: ""
        buildConfigField("String", "GITHUB_CLIENT_ID", "\"$clientId\"")
    }

    // Sabit imza: CI, keystore'u GitHub secret'larından alıp ortam değişkenleriyle verir
    // (KEYSTORE_FILE, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD). Böylece her sürüm aynı anahtarla
    // imzalanır ve telefonda eski sürümün üzerine güncelleme olarak kurulabilir.
    // Değişkenler yoksa (yerel derleme) debug anahtarına düşer.
    signingConfigs {
        val ksFile = System.getenv("KEYSTORE_FILE")
        if (!ksFile.isNullOrBlank()) {
            create("release") {
                storeFile = file(ksFile)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions { jvmTarget = "17" }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.3")

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")

    val composeBom = platform("androidx.compose:compose-bom:2025.06.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // Cam / bulanıklık efektleri (Apache-2.0, Maven Central). Kaynak koda kopyalanmaz; yalnızca bağımlılık.
    // Tüm artifact'lar AYNI sürümde olmalı.
    implementation("dev.chrisbanes.haze:haze:2.1.0")
    implementation("dev.chrisbanes.haze:haze-glass:2.1.0")

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
}
