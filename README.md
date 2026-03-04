# Flutter Termux Installer

This repo installs a full Flutter SDK checkout for Termux-style Android shells and overlays it with Android-bionic host tools built from the Flutter engine.

It pulls the host bundle from:

- `https://github.com/sirvkrm/flutter-android-bionic-builder`

It pulls Android-bionic Dart SDK mirror zips from:

- `https://github.com/sirvkrm/dart-android-bionic-builder`

The host bundle provides the pieces the stock Flutter SDK does not ship for Android-hosted terminals:

- `bin/cache/dart-sdk` built for Android bionic host arch (`arm64` or `x64`)
- `bin/cache/artifacts/engine/linux-<host-arch>/font-subset`
- `bin/cache/artifacts/engine/linux-<host-arch>/const_finder.dart.snapshot`
- `bin/cache/artifacts/engine/android-*-{profile,release}/android-<host-arch>/gen_snapshot`

The installer patches `flutter_tools` so Android-hosted Termux uses the
`android-<host-arch>` Android snapshot tool cache namespace instead of `linux-x64`.
It also sets `FLUTTER_TERMUX_ARTIFACT_BASE_URL` in `env.sh`, so Android-host
snapshot zips can be fetched from this project's GitHub releases if missing.
It also sets `FLUTTER_TERMUX_DART_ARTIFACT_BASE_URL` in `env.sh`, so Android
hosts fetch Dart SDK zips from the Dart mirror repo (same release tag as the
installed host bundle) instead of Flutter's Google-hosted Linux Dart zip.
The patch set uses `engine.stamp` to select engine-matched mirror assets for
`dart-sdk`, `flutter_patched_sdk(_product)`, and `linux-<host-arch>` host tools.
The patch set also whitelists this base URL in Flutter's artifact downloader,
so custom mirror downloads do not emit SDK-bug warnings.

The installer also applies a small Flutter framework patch so the tool treats Termux as a Linux-like host for host-platform selection and Android SDK path discovery.

## What It Does

By default, `./install.sh`:

- clones the latest Flutter tag that still targets Dart `3.7` (`3.32.8`) if it is not already present
- downloads the latest Termux host bundle release asset
- extracts the bundle
- applies the Termux host compatibility patch
- auto-reclones the Flutter checkout if a previous local patch state is incompatible with the current patch set
- clears stale `bin/cache/artifacts/engine/common`, `linux-arm64`, and `linux-x64` cache directories before overlaying
- overlays the bionic host tools into the Flutter SDK cache
- normalizes the overlaid Dart SDK semver so `pub` accepts the prebuilt bundle
- writes `env.sh`
- writes a `flutter-termux` wrapper in `bin/`
- configures engine-stamp keyed Dart mirror env vars to avoid kernel format skew

## Current Scope

Current validated host bundle targets:

- `arm64` Android / Termux hosts
- `x64` Android / Termux hosts

This is aimed at running the Flutter tool itself inside Termux. Android target runtime artifacts still come from the normal Flutter cache flow (`flutter precache --android` or first use).

## Requirements

The installer itself needs:

- `git`
- `tar`
- `python3`
- `unzip`

On Termux it can install missing prerequisites automatically with `pkg`.

For actual Flutter app builds you still need the normal platform dependencies:

- Android APK builds:
  - Java/JDK
  - Android SDK command-line tools or Android Studio
  - accepted Android licenses
- Web builds:
  - Flutter web artifacts (`flutter precache --web`)
  - a browser for local debug if you want `flutter run -d chrome`

## Install

```bash
git clone https://github.com/sirvkrm/flutter-android-bionic-termux-installer.git
cd flutter-android-bionic-termux-installer
chmod +x install.sh
./install.sh
```

Default install root on Termux:

```bash
$PREFIX/opt/flutter-termux
```

That produces:

- `flutter/` for the Flutter SDK checkout
- `env.sh`
- `bin/flutter-termux`

## Choose A Release

Install a specific tag:

```bash
./install.sh --tag v2026.03.04
```

Choose an asset interactively:

```bash
./install.sh --tag v2026.03.04 --interactive
```

Install a specific host bundle asset:

```bash
./install.sh --tag v2026.03.04 --asset flutter-android-bionic-termux-host-x64-20260304.tar.gz
```

List release tags:

```bash
./install.sh --list-releases
```

## Flutter SDK Options

Use a different install root:

```bash
./install.sh --install-root "$HOME/my-flutter-termux"
```

Reuse or target a different Flutter checkout path:

```bash
./install.sh --flutter-dir "$HOME/flutter-termux-sdk"
```

If an existing checkout is present at a different Flutter ref, the installer now
replaces it automatically. Use `--reclone` if you want to force a fresh clone
even when the checkout already matches the requested ref.

Clone a different Flutter ref:

```bash
./install.sh --flutter-ref master
```

The default ref is intentionally pinned to `3.32.8`, because the current public
engine source used to build the bionic host bundle still provides Dart `3.7`.
Newer Flutter framework refs such as current `stable` require newer Dart SDK
versions and will fail during `flutter_tools` bootstrap with this host bundle.

Override Dart mirror owner/repo:

```bash
./install.sh --dart-owner sirvkrm --dart-repo dart-android-bionic-builder
```

Run Android precache immediately after install:

```bash
./install.sh --precache
```

## After Install

Load the environment:

```bash
source "$PREFIX/opt/flutter-termux/env.sh"
```

Or use the wrapper directly:

```bash
$PREFIX/opt/flutter-termux/bin/flutter-termux --version
```

Recommended first checks:

```bash
flutter --version
flutter doctor -v
flutter precache --android
```

If your Android SDK was not auto-detected, set these in `env.sh`:

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
```

Engine-stamp specific mirror variables written by installer:

```bash
export FLUTTER_TERMUX_ENGINE_STAMP="..."
export FLUTTER_TERMUX_HOST_ARCH="arm64|x64"
export FLUTTER_TERMUX_ARTIFACT_BASE_URL="https://github.com/sirvkrm/flutter-android-bionic-builder/releases/download/<tag>"
export FLUTTER_TERMUX_DART_ARTIFACT_BASE_URL="https://github.com/sirvkrm/dart-android-bionic-builder/releases/download/<tag>"
export FLUTTER_TERMUX_DART_SDK_ASSET="dart-sdk-android-<host-arch>-<engine-stamp>.zip"
```

If your NDK is installed in Termux build-tools, also set:

```bash
export ANDROID_NDK_HOME="$HOME/.build-tools/android/android-ndk-r27c"
```

## Patch Files

The Flutter framework patches applied during install are stored here:

- `patches/0001-termux-android-host-support.patch`
- `patches/0002-termux-android-flutter-cache-support.patch`
- `patches/0003-termux-android-web-chrome-support.patch`
- `patches/0004-termux-android-adb-discovery-tolerance.patch`
- `patches/0005-termux-android-artifact-namespace-and-mirror.patch`
- `patches/0006-termux-android-allow-custom-artifact-base-url.patch`
- `patches/0007-termux-android-dart-sdk-mirror.patch`
- `patches/0008-termux-android-gradle-wrapper-shell.patch`

## Limitations

- Host bundles are published per host arch (`arm64` and `x64`).
- This installer patches the Flutter framework checkout locally; if you switch branches or reset the SDK repo, re-run the installer.
- The builder repo must publish `flutter-android-bionic-termux-host-<host-arch>-*.tar.gz` for the selected release tag.
