import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key for Google Play lives outside the repository. `android/key.properties`
// (git-ignored) points at it:
//   storeFile=C:/Users/<you>/keys/ownit2buildit-upload.jks   (forward slashes)
//   storePassword=...
//   keyAlias=upload
//   keyPassword=...
// See docs/play-store-release.md.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val releaseKeyFields = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseKey = releaseKeyFields.all { !keystoreProperties.getProperty(it).isNullOrBlank() }

android {
    namespace = "com.ownit2buildit.builder_pro_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ownit2buildit.builder_pro_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Without key.properties a release APK is signed with the debug key so
            // `flutter run --release` still works on a device. Such a build can never
            // go to Google Play, and the guard below stops a bundle (the Play format)
            // from being built that way.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

gradle.taskGraph.whenReady {
    if (!hasReleaseKey && allTasks.any { it.path.endsWith(":bundleRelease") }) {
        throw GradleException(
            "No upload key: android/key.properties is missing or incomplete " +
                "(needs ${releaseKeyFields.joinToString(", ")}). " +
                "Create the key and file as described in docs/play-store-release.md, " +
                "then run the bundle build again."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
