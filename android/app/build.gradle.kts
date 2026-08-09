import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = rootProject.file("key.properties")
if (releaseSigningPropertiesFile.exists()) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}

fun releaseSigningValue(propertyName: String, environmentName: String): String? {
    return System.getenv(environmentName) ?: releaseSigningProperties.getProperty(propertyName)
}

// 本机（或 CI）配了签名才启用发布证书；没配置的贡献者继续用默认 debug keystore，
// 直接 clone 下来也能构建。
val hasReleaseSigning = releaseSigningValue("storeFile", "ANDROID_KEYSTORE_PATH") != null

android {
    namespace = "com.cold04.uwhlife"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.cold04.uwhlife"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseSigningValue("storeFile", "ANDROID_KEYSTORE_PATH")
                ?.let(rootProject::file)
            storePassword = releaseSigningValue(
                "storePassword",
                "ANDROID_KEYSTORE_PASSWORD",
            )
            keyAlias = releaseSigningValue("keyAlias", "ANDROID_KEY_ALIAS")
            keyPassword = releaseSigningValue("keyPassword", "ANDROID_KEY_PASSWORD")
        }
    }

    buildTypes {
        debug {
            // 与 release 用同一证书，debug / release 之间切换不再需要卸载重装。
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.webkit:webkit:1.11.0")
}

flutter {
    source = "../.."
}
