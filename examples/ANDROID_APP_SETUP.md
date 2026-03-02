# Android App Setup

After running:

```bash
source "$PREFIX/opt/flutter-bionic/env.sh"
```

You will have:

- `FLUTTER_BIONIC_EMBEDDING_JAR`
- `FLUTTER_BIONIC_NATIVE_JAR`
- `FLUTTER_BIONIC_LIB`

## Copy Jars Into Your App

Place these jars into your Android app module, for example:

```bash
app/libs/flutter_embedding_classes.jar
app/libs/arm64_v8a_debug.jar
```

Use the ABI jar that matches the ABI you want to ship.

## Gradle (Groovy)

In `app/build.gradle`:

```groovy
android {
    sourceSets {
        main {
            jniLibs.srcDirs = ['src/main/jniLibs']
        }
    }
}

dependencies {
    implementation files(
        'libs/flutter_embedding_classes.jar',
        'libs/arm64_v8a_debug.jar'
    )
}
```

## Gradle (Kotlin DSL)

In `app/build.gradle.kts`:

```kotlin
android {
    sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")
}

dependencies {
    implementation(
        files(
            "libs/flutter_embedding_classes.jar",
            "libs/arm64_v8a_debug.jar",
        )
    )
}
```

## If You Want Raw `libflutter.so` Instead Of The ABI Jar

The installer already extracts:

```bash
$FLUTTER_BIONIC_LIB
```

You can copy it into:

```bash
app/src/main/jniLibs/<abi>/libflutter.so
```

Then keep only the classes jar as a Java dependency.
