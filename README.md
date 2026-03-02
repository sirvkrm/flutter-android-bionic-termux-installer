# Flutter Termux Installer

This repo installs a full Flutter SDK checkout for Termux-style Android shells and overlays it with Android-bionic host tools built from the Flutter engine.

It pulls the host bundle from:

- `https://github.com/sirvkrm/flutter-android-bionic-builder`

The host bundle provides the pieces the stock Flutter SDK does not ship for Android-hosted terminals:

- `bin/cache/dart-sdk` built for Android bionic `aarch64`
- `bin/cache/artifacts/engine/linux-arm64/font-subset`
- `bin/cache/artifacts/engine/linux-arm64/const_finder.dart.snapshot`
- `bin/cache/artifacts/engine/android-arm-profile/linux-arm64/gen_snapshot`

The installer also applies a small Flutter framework patch so the tool treats Termux as a Linux-like host for host-platform selection and Android SDK path discovery.

## What It Does

By default, `./install.sh`:

- clones the latest Flutter tag that still targets Dart `3.7` (`3.32.8`) if it is not already present
- downloads the latest Termux host bundle release asset
- extracts the bundle
- applies the Termux host compatibility patch
- overlays the bionic host tools into the Flutter SDK cache
- normalizes the overlaid Dart SDK semver so `pub` accepts the prebuilt bundle
- writes `env.sh`
- writes a `flutter-termux` wrapper in `bin/`

## Current Scope

Current validated host bundle target:

- `arm64` Android / Termux hosts

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
./install.sh --tag v2026.03.02
```

Choose an asset interactively:

```bash
./install.sh --tag v2026.03.02 --interactive
```

Install a specific host bundle asset:

```bash
./install.sh --tag v2026.03.02 --asset flutter-android-bionic-termux-host-arm64-20260302.tar.gz
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

If your NDK is installed in Termux build-tools, also set:

```bash
export ANDROID_NDK_HOME="$HOME/.build-tools/android/android-ndk-r27c"
```

## Patch Files

The Flutter framework patch applied during install is stored here:

- `patches/0001-termux-android-host-support.patch`

## Limitations

- The current host bundle is `arm64` only.
- This installer patches the Flutter framework checkout locally; if you switch branches or reset the SDK repo, re-run the installer.
- The builder repo must publish the `flutter-android-bionic-termux-host-arm64-*.tar.gz` asset for the selected release tag.
