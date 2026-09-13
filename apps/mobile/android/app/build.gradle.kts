import java.util.Properties
import java.util.Base64
import java.net.URI
import java.security.KeyStore
import javax.naming.ldap.LdapName

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    implementation("androidx.exifinterface:exifinterface:1.3.7")
}

// Environment injection is atomic: never mix a partial CI identity with local secrets.
val releaseFields = mapOf(
    "storeFile" to "ANDROID_RELEASE_STORE_FILE",
    "storePassword" to "ANDROID_RELEASE_STORE_PASSWORD",
    "keyAlias" to "ANDROID_RELEASE_KEY_ALIAS",
    "keyPassword" to "ANDROID_RELEASE_KEY_PASSWORD",
)
val useReleaseEnvironment = releaseFields.values.any { System.getenv(it) != null }
val releaseProperties = Properties().apply {
    val source = rootProject.file("key.properties")
    if (!useReleaseEnvironment && source.isFile) source.inputStream().use { load(it) }
}
fun releaseValue(name: String): String? =
    if (useReleaseEnvironment) System.getenv(releaseFields.getValue(name))
    else releaseProperties.getProperty(name)
val releaseStore = releaseValue("storeFile")?.takeIf { it.isNotBlank() }?.let { rootProject.file(it) }

val validateReleaseConfiguration = tasks.register("validateReleaseConfiguration") {
    doLast {
        check(releaseFields.keys.all { !releaseValue(it).isNullOrBlank() }) {
            "Release signing is required: configure android/key.properties or all four ANDROID_RELEASE_* variables. No debug fallback."
        }
        check(releaseStore?.isFile == true) { "Release keystore does not exist." }
        val store = try {
            KeyStore.getInstance(releaseStore!!, releaseValue("storePassword")!!.toCharArray())
        } catch (_: Exception) {
            error("Cannot open release keystore. Check its format and credentials.")
        }
        val alias = releaseValue("keyAlias")!!
        check(store.isKeyEntry(alias)) { "Release alias must identify a private key." }
        try {
            check(store.getKey(alias, releaseValue("keyPassword")!!.toCharArray()) != null)
        } catch (_: Exception) {
            error("Cannot unlock release signing key.")
        }
        val cert = store.getCertificate(alias) as java.security.cert.X509Certificate
        cert.checkValidity()
        check(LdapName(cert.subjectX500Principal.name).rdns.none {
            it.type.equals("CN", true) && it.value.toString().equals("Android Debug", true)
        }) { "Android Debug certificates are forbidden for Release." }
        val allDefinitions = (project.findProperty("dart-defines") as? String).orEmpty()
            .split(',').filter { it.isNotEmpty() }.map {
                String(Base64.getDecoder().decode(it), Charsets.UTF_8)
            }
        val definitions = allDefinitions.filter { it.startsWith("API_BASE_URL=") }
        check(definitions.size == 1) { "Release requires exactly one explicit API_BASE_URL dart-define." }
        val endpoint = URI(definitions.single().substringAfter('='))
        val lanCertificates = allDefinitions.filter { it.startsWith("LAN_ACCEPTANCE_CA_BASE64=") }
        if (endpoint.host == "pig-inventory.local") {
            check(lanCertificates.size == 1 && lanCertificates.single().substringAfter('=').isNotBlank()) {
                "LAN acceptance requires exactly one explicit certificate."
            }
        } else {
            check(lanCertificates.isEmpty()) { "LAN certificate is restricted to pig-inventory.local." }
        }
        check(endpoint.scheme == "https" && !endpoint.host.isNullOrBlank() &&
            endpoint.userInfo == null && endpoint.rawQuery == null && endpoint.rawFragment == null &&
            endpoint.host != "localhost" && !endpoint.host.endsWith(".localhost") &&
            !endpoint.host.matches(Regex("[0-9.]+")) && !endpoint.host.contains(':')) {
            "Release API_BASE_URL must be a stable HTTPS DNS URL without credentials, query, fragment or IP literals."
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(validateReleaseConfiguration)
}

android {
    namespace = "com.smartfarm.smart_pig_inventory"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.smartfarm.smart_pig_inventory"
        // Version values are sourced from pubspec.yaml through Flutter.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStore
            storePassword = releaseValue("storePassword")
            keyAlias = releaseValue("keyAlias")
            keyPassword = releaseValue("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
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
