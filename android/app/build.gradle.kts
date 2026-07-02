import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Настройки подписи release читаются из android/key.properties (в .gitignore,
// НЕ коммитится). Если файла нет — release подписывается debug-ключом, чтобы
// `flutter run --release` и CI работали без секретного keystore (аудит OPS-1).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.orpheus_project"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // !!! ВАЖНОЕ ИЗМЕНЕНИЕ 1: Включаем Desugaring
        isCoreLibraryDesugaringEnabled = true

        // Java 17 required by flutter_callkit_incoming
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.orpheus_project"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Рекомендуется включить MultiDex, так как у вас Firebase + Notifications
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            // Заполняется только если есть key.properties (иначе конфиг пустой и
            // не используется — см. buildTypes.release ниже).
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // Если настроен key.properties — подписываем своим release-ключом,
            // иначе остаёмся на debug-ключе, чтобы сборка работала без keystore
            // (аудит OPS-1).
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Настройки для релизной сборки (сжатие)
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // !!! ВАЖНОЕ ИЗМЕНЕНИЕ 2: Библиотека Desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    implementation(platform("com.google.firebase:firebase-bom:34.6.0"))
    implementation("com.google.firebase:firebase-analytics")
}