plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.suishouhua.tv"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.suishouhua.tv"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    packaging {
        resources.excludes += setOf(
            "META-INF/INDEX.LIST",
            "META-INF/DEPENDENCIES",
            "META-INF/{AL2.0,LGPL2.1}",
            "META-INF/versions/**",
        )
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")

    val ktor = "2.3.13"
    implementation("io.ktor:ktor-server-core:$ktor")
    implementation("io.ktor:ktor-server-cio:$ktor")
    implementation("io.ktor:ktor-server-websockets:$ktor")

    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // 二维码生成（仅 core，无相机依赖）
    implementation("com.google.zxing:core:3.5.3")

    testImplementation(kotlin("test"))
}
