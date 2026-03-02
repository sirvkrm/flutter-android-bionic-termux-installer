# Flutter Android Bionic Termux Installer

This repo installs the prebuilt Flutter Android bionic engine bundles published from:

- `https://github.com/sirvkrm/flutter-android-bionic-builder`

It is focused on Termux and Linux shell use. By default it:

- detects your current ABI
- fetches the latest release
- downloads the matching per-ABI bundle
- extracts it under your install root
- extracts `libflutter.so`
- writes an `env.sh` file you can source

## Current Flutter Requirements

Official Flutter docs currently require, on a Linux host:

- Base Flutter install:
  - Flutter SDK
  - `curl`
  - `git`
  - `unzip`
  - `xz`
  - `zip`
  - `libglu1-mesa`
- Android APK builds:
  - Android Studio or equivalent Android SDK command-line setup
  - installed Android SDK components
  - accepted Android SDK licenses
- Web builds:
  - Flutter SDK
  - a browser (Chrome or Edge are the standard local debug targets)
- Linux desktop builds:
  - `clang`
  - `cmake`
  - `ninja-build`
  - `pkg-config`
  - `libgtk-3-dev`
  - `libstdc++-12-dev`

For a full Flutter SDK check, always run:

```bash
flutter doctor -v
```

## Termux Requirements

The installer can auto-install these through `pkg` when needed:

- `tar`
- `unzip`
- `python`

You can also install them manually:

```bash
pkg install -y tar unzip python curl
```

`curl` is optional because the installer can fall back to `python3` for downloads.

## Install

Clone this repo:

```bash
git clone https://github.com/sirvkrm/flutter-android-bionic-termux-installer.git
cd flutter-android-bionic-termux-installer
chmod +x install.sh
```

Install the latest matching ABI bundle:

```bash
./install.sh
```

On a typical Termux device this installs under:

```bash
$PREFIX/opt/flutter-bionic
```

## Choose What To Download

Install the latest bundle for a specific ABI:

```bash
./install.sh --abi arm64-v8a
./install.sh --abi armeabi-v7a
./install.sh --abi x86
./install.sh --abi x86_64
```

Install the combined all-ABI bundle:

```bash
./install.sh --all
```

Install from a specific release tag:

```bash
./install.sh --tag v2026.03.02
```

Install a specific asset name:

```bash
./install.sh --tag v2026.03.02 --asset flutter-android-bionic-debug-arm64-v8a-20260302.tar.gz
```

List release tags:

```bash
./install.sh --list-releases
```

Choose interactively from the assets in a release:

```bash
./install.sh --tag v2026.03.02 --interactive
```

## After Install

Load the installed environment:

```bash
source "$PREFIX/opt/flutter-bionic/env.sh"
```

This exports:

- `FLUTTER_BIONIC_HOME`
- `FLUTTER_BIONIC_RELEASE_TAG`
- `FLUTTER_BIONIC_ASSET`
- `FLUTTER_BIONIC_ABI`
- `FLUTTER_BIONIC_EMBEDDING_JAR`
- `FLUTTER_BIONIC_NATIVE_JAR`
- `FLUTTER_BIONIC_LIB`
- `FLUTTER_BIONIC_GEN_SNAPSHOT`

You can then inspect the installed files:

```bash
echo "$FLUTTER_BIONIC_LIB"
ls -l "$FLUTTER_BIONIC_HOME/embedding"
```

## Android Project Use

Add these jars to your Android project:

- `flutter_embedding_classes.jar`
- the ABI-specific native jar selected by the installer

A concrete Gradle example is included here:

- `examples/ANDROID_APP_SETUP.md`

If you need the raw shared library directly, the installer already extracts it into:

```bash
$FLUTTER_BIONIC_HOME/runtime/lib/<abi>/libflutter.so
```

## Important Note About `gen_snapshot`

The published bundles include the Linux x64 `gen_snapshot` binary from the build machine. That is useful on Linux x64 hosts, but it will not run natively on most ARM Termux phones.

The main Termux use case here is:

- fetching the correct prebuilt Android engine artifacts
- extracting `libflutter.so`
- wiring those artifacts into an Android project or custom embedder
