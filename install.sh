#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_OWNER="sirvkrm"
DEFAULT_REPO="flutter-android-bionic-builder"
DEFAULT_INSTALL_ROOT="${PREFIX:-$HOME/.local}/opt/flutter-termux"
DEFAULT_FLUTTER_REPO="https://github.com/flutter/flutter.git"
DEFAULT_FLUTTER_REF="stable"
PATCH_FILE="$SCRIPT_DIR/patches/0001-termux-android-host-support.patch"

note() {
  printf '%s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./install.sh
  ./install.sh --interactive
  ./install.sh --tag v2026.03.02
  ./install.sh --asset flutter-android-bionic-termux-host-arm64-20260302.tar.gz
  ./install.sh --list-releases

Defaults:
  - downloads the latest Termux host bundle from sirvkrm/flutter-android-bionic-builder
  - installs a Flutter SDK checkout under $PREFIX/opt/flutter-termux/flutter
  - applies the Termux host compatibility patch
  - overlays the Android-bionic Dart SDK and host tools into bin/cache
  - writes env.sh and a flutter-termux wrapper script

Options:
  --interactive        Choose a release asset from a numbered list
  --list-releases      Print available release tags and exit
  --tag TAG            Install from a specific release tag
  --asset NAME         Install a specific host bundle asset from the selected tag
  --abi ABI            Host arch alias (currently only arm64-v8a)
  --install-root DIR   Override the installation root
  --flutter-dir DIR    Override the Flutter SDK checkout path
  --flutter-repo URL   Override the Flutter framework repo (default: official repo)
  --flutter-ref REF    Override the Flutter git ref to clone (default: stable)
  --owner NAME         Override the GitHub owner (default: sirvkrm)
  --repo NAME          Override the GitHub repo (default: flutter-android-bionic-builder)
  --keep-archive       Keep the downloaded tarball in tmp/
  --precache           Run flutter precache --android after install
  -h, --help           Show this help
EOF
}

is_termux() {
  [[ -n "${PREFIX:-}" && "$PREFIX" == *"/com.termux/"* ]]
}

command_missing() {
  ! command -v "$1" >/dev/null 2>&1
}

ensure_git_exec_path() {
  if ! command -v git >/dev/null 2>&1; then
    die "git is required"
  fi

  if [[ -n "${GIT_EXEC_PATH:-}" && -x "${GIT_EXEC_PATH}/git-remote-https" ]]; then
    return 0
  fi

  local current_exec_path=""
  current_exec_path=$(git --exec-path 2>/dev/null || true)
  if [[ -n "$current_exec_path" && -x "$current_exec_path/git-remote-https" ]]; then
    export GIT_EXEC_PATH="$current_exec_path"
    return 0
  fi

  if [[ -x /snap/codex/21/usr/lib/git-core/git-remote-https ]]; then
    export GIT_EXEC_PATH=/snap/codex/21/usr/lib/git-core
    return 0
  fi

  die "unable to locate git remote helpers; set GIT_EXEC_PATH"
}

ensure_prereqs() {
  local missing=()
  local pkg_name

  for pkg_name in git tar python unzip; do
    case "$pkg_name" in
      python)
        if command_missing python3; then
          missing+=("$pkg_name")
        fi
        ;;
      *)
        if command_missing "$pkg_name"; then
          missing+=("$pkg_name")
        fi
        ;;
    esac
  done

  if ((${#missing[@]} == 0)); then
    return 0
  fi

  if is_termux && command -v pkg >/dev/null 2>&1; then
    note "Installing Termux prerequisites: ${missing[*]}"
    pkg install -y "${missing[@]}"
    return 0
  fi

  die "missing required tools: ${missing[*]}"
}

download_to() {
  local url=$1
  local dest=$2

  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --output "$dest" "$url"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -O "$dest" "$url"
    return 0
  fi

  python3 - "$url" "$dest" <<'PY'
import pathlib
import sys
import urllib.request

url, dest = sys.argv[1], sys.argv[2]
path = pathlib.Path(dest)
path.parent.mkdir(parents=True, exist_ok=True)
with urllib.request.urlopen(url) as response:
    path.write_bytes(response.read())
PY
}

archive_top_level_dir() {
  local archive_path=$1

  python3 - "$archive_path" <<'PY'
import sys
import tarfile

archive_path = sys.argv[1]
with tarfile.open(archive_path, "r:gz") as tf:
    for name in tf.getnames():
        top = name.split("/", 1)[0]
        if top:
            print(top)
            break
    else:
        sys.exit(1)
PY
}

detect_host_bundle_arch() {
  case "$(uname -m)" in
    aarch64|arm64)
      printf 'arm64\n'
      ;;
    *)
      die "unsupported host architecture for the Termux bundle: $(uname -m)"
      ;;
  esac
}

normalize_host_bundle_arch() {
  case "${1,,}" in
    arm64|arm64-v8a|aarch64)
      printf 'arm64\n'
      ;;
    *)
      die "unsupported host bundle architecture: $1"
      ;;
  esac
}

github_release_query() {
  local mode=$1
  local owner=$2
  local repo=$3
  local tag=${4:-}
  local asset_name=${5:-}

  python3 - "$mode" "$owner" "$repo" "$tag" "$asset_name" <<'PY'
import json
import sys
import urllib.error
import urllib.request

mode, owner, repo, tag, asset_name = sys.argv[1:6]
headers = {
    "Accept": "application/vnd.github+json",
    "User-Agent": "flutter-termux-installer",
}

def fetch(url):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as response:
        return json.load(response)

base = f"https://api.github.com/repos/{owner}/{repo}/releases"

try:
    if mode == "latest-tag":
        data = fetch(f"{base}/latest")
        print(data["tag_name"])
    elif mode == "list-releases":
        data = fetch(base)
        for item in data:
            print(item["tag_name"])
    elif mode == "list-assets":
        data = fetch(f"{base}/tags/{tag}")
        for asset in data.get("assets", []):
            print(asset["name"])
    elif mode == "asset-url":
        data = fetch(f"{base}/tags/{tag}")
        for asset in data.get("assets", []):
            if asset["name"] == asset_name:
                print(asset["browser_download_url"])
                break
        else:
            sys.exit(3)
    else:
        sys.exit(2)
except urllib.error.HTTPError as exc:
    print(f"HTTP {exc.code}", file=sys.stderr)
    sys.exit(1)
PY
}

choose_interactively() {
  local -a assets=("$@")
  local idx

  ((${#assets[@]} > 0)) || die "no assets available to choose from"
  [[ -t 0 ]] || die "--interactive requires a TTY"

  printf '%s\n' "Available assets:" >&2
  for idx in "${!assets[@]}"; do
    printf '  %d. %s\n' "$((idx + 1))" "${assets[$idx]}" >&2
  done

  local choice=""
  while true; do
    read -r -p "Choose an asset number: " choice || die "interactive selection aborted"
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#assets[@]})); then
      printf '%s\n' "${assets[$((choice - 1))]}"
      return 0
    fi
    printf '%s\n' "Invalid selection." >&2
  done
}

preferred_asset_pattern() {
  local host_arch=$1
  printf 'flutter-android-bionic-termux-host-%s-*.tar.gz\n' "$host_arch"
}

resolve_asset_name() {
  local owner=$1
  local repo=$2
  local tag=$3
  local requested_asset=$4
  local host_arch=$5
  local interactive=$6
  local preferred_pattern
  local selected=""
  local -a assets=()
  local line

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    assets+=("$line")
  done < <(github_release_query "list-assets" "$owner" "$repo" "$tag")

  ((${#assets[@]} > 0)) || die "no assets found for $owner/$repo $tag"

  if [[ -n "$requested_asset" ]]; then
    for line in "${assets[@]}"; do
      if [[ "$line" == "$requested_asset" ]]; then
        printf '%s\n' "$line"
        return 0
      fi
    done
    die "asset not found in $tag: $requested_asset"
  fi

  if [[ "$interactive" == "1" ]]; then
    choose_interactively "${assets[@]}"
    return 0
  fi

  preferred_pattern=$(preferred_asset_pattern "$host_arch")
  for line in "${assets[@]}"; do
    if [[ "$line" == $preferred_pattern ]]; then
      selected=$line
      break
    fi
  done

  [[ -n "$selected" ]] || die "no matching host bundle found for $host_arch in $tag"
  printf '%s\n' "$selected"
}

detect_android_sdk() {
  local candidates=()

  if [[ -n "${ANDROID_HOME:-}" ]]; then
    candidates+=("$ANDROID_HOME")
  fi
  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    candidates+=("$ANDROID_SDK_ROOT")
  fi

  candidates+=(
    "$HOME/Android/Sdk"
    "$HOME/.local/share/android-sdk"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

detect_android_ndk() {
  local candidates=()

  if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
    candidates+=("$ANDROID_NDK_HOME")
  fi

  candidates+=(
    "$HOME/.build-tools/android/android-ndk-r27c"
    "$HOME/Android/Sdk/ndk"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -d "$candidate/toolchains/llvm/prebuilt" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_flutter_sdk() {
  local flutter_repo=$1
  local flutter_ref=$2
  local flutter_dir=$3

  if [[ -d "$flutter_dir/.git" ]]; then
    note "Using existing Flutter SDK checkout: $flutter_dir"
    return 0
  fi

  mkdir -p "$(dirname "$flutter_dir")"
  note "Cloning Flutter SDK ($flutter_ref) into $flutter_dir"
  git clone --depth 1 --branch "$flutter_ref" "$flutter_repo" "$flutter_dir"
}

apply_patch_if_needed() {
  local repo_dir=$1
  local patch_file=$2

  [[ -f "$patch_file" ]] || die "missing patch file: $patch_file"

  if git -C "$repo_dir" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    return 0
  fi

  if git -C "$repo_dir" apply --check "$patch_file" >/dev/null 2>&1; then
    note "Applying $(basename "$patch_file")"
    git -C "$repo_dir" apply "$patch_file"
    return 0
  fi

  die "unable to apply $(basename "$patch_file") cleanly in $repo_dir"
}

copy_overlay_dir() {
  local src_dir=$1
  local dest_dir=$2

  [[ -d "$src_dir" ]] || die "missing overlay directory: $src_dir"
  mkdir -p "$dest_dir"
  cp -a "$src_dir/." "$dest_dir/"
}

prime_flutter_cache_stamps() {
  local flutter_dir=$1
  local engine_stamp=""

  "$flutter_dir/bin/internal/update_engine_version.sh"
  engine_stamp="$flutter_dir/bin/cache/engine.stamp"
  [[ -f "$engine_stamp" ]] || die "missing engine.stamp after priming Flutter cache"
  cp -a "$engine_stamp" "$flutter_dir/bin/cache/engine-dart-sdk.stamp"
}

write_env_file() {
  local env_file=$1
  local install_root=$2
  local flutter_dir=$3
  local tag=$4
  local asset=$5
  local android_sdk=$6
  local android_ndk=$7

  {
    printf 'export FLUTTER_TERMUX_HOME="%s"\n' "$install_root"
    printf 'export FLUTTER_TERMUX_RELEASE_TAG="%s"\n' "$tag"
    printf 'export FLUTTER_TERMUX_ASSET="%s"\n' "$asset"
    printf 'export FLUTTER_ROOT="%s"\n' "$flutter_dir"
    printf 'export PATH="%s/bin:%s/bin:$PATH"\n' "$install_root" "$flutter_dir"
    if [[ -n "$android_sdk" ]]; then
      printf 'export ANDROID_HOME="%s"\n' "$android_sdk"
      printf 'export ANDROID_SDK_ROOT="%s"\n' "$android_sdk"
    fi
    if [[ -n "$android_ndk" ]]; then
      printf 'export ANDROID_NDK_HOME="%s"\n' "$android_ndk"
    fi
  } >"$env_file"
}

write_wrapper() {
  local wrapper_path=$1
  local install_root=$2

  mkdir -p "$(dirname "$wrapper_path")"
  cat >"$wrapper_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=/dev/null
source "$install_root/env.sh"
exec "\$FLUTTER_ROOT/bin/flutter" "\$@"
EOF
  chmod +x "$wrapper_path"
}

main() {
  local owner="$DEFAULT_OWNER"
  local repo="$DEFAULT_REPO"
  local install_root="$DEFAULT_INSTALL_ROOT"
  local flutter_repo="$DEFAULT_FLUTTER_REPO"
  local flutter_ref="$DEFAULT_FLUTTER_REF"
  local flutter_dir=""
  local requested_tag=""
  local requested_asset=""
  local requested_host_arch=""
  local list_releases=0
  local interactive=0
  local keep_archive=0
  local run_precache=0

  while (($#)); do
    case "$1" in
      --interactive)
        interactive=1
        ;;
      --list-releases)
        list_releases=1
        ;;
      --tag)
        shift
        [[ $# -gt 0 ]] || die "--tag requires a value"
        requested_tag=$1
        ;;
      --asset)
        shift
        [[ $# -gt 0 ]] || die "--asset requires a value"
        requested_asset=$1
        ;;
      --abi)
        shift
        [[ $# -gt 0 ]] || die "--abi requires a value"
        requested_host_arch=$(normalize_host_bundle_arch "$1")
        ;;
      --install-root)
        shift
        [[ $# -gt 0 ]] || die "--install-root requires a value"
        install_root=$1
        ;;
      --flutter-dir)
        shift
        [[ $# -gt 0 ]] || die "--flutter-dir requires a value"
        flutter_dir=$1
        ;;
      --flutter-repo)
        shift
        [[ $# -gt 0 ]] || die "--flutter-repo requires a value"
        flutter_repo=$1
        ;;
      --flutter-ref)
        shift
        [[ $# -gt 0 ]] || die "--flutter-ref requires a value"
        flutter_ref=$1
        ;;
      --owner)
        shift
        [[ $# -gt 0 ]] || die "--owner requires a value"
        owner=$1
        ;;
      --repo)
        shift
        [[ $# -gt 0 ]] || die "--repo requires a value"
        repo=$1
        ;;
      --keep-archive)
        keep_archive=1
        ;;
      --precache)
        run_precache=1
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
    shift
  done

  ensure_prereqs
  ensure_git_exec_path

  if [[ "$list_releases" == "1" ]]; then
    github_release_query "list-releases" "$owner" "$repo"
    return 0
  fi

  local host_arch
  host_arch=${requested_host_arch:-$(detect_host_bundle_arch)}

  local tag
  tag=${requested_tag:-$(github_release_query "latest-tag" "$owner" "$repo")}

  local asset
  asset=$(resolve_asset_name "$owner" "$repo" "$tag" "$requested_asset" "$host_arch" "$interactive")

  local download_url
  download_url=$(github_release_query "asset-url" "$owner" "$repo" "$tag" "$asset")

  local tmp_dir="$SCRIPT_DIR/tmp"
  mkdir -p "$tmp_dir"
  local archive_path="$tmp_dir/$asset"

  note "Downloading $asset from $owner/$repo $tag"
  download_to "$download_url" "$archive_path"

  local release_dir="$install_root/releases/$tag"
  mkdir -p "$release_dir"

  local top_level
  top_level=$(archive_top_level_dir "$archive_path")
  [[ -n "$top_level" ]] || die "unable to inspect archive: $archive_path"

  rm -rf "$release_dir/$top_level"
  tar -xzf "$archive_path" -C "$release_dir"

  local bundle_dir="$release_dir/$top_level"
  [[ -d "$bundle_dir/overlay" ]] || die "host bundle is missing overlay/: $bundle_dir"

  flutter_dir=${flutter_dir:-$install_root/flutter}
  ensure_flutter_sdk "$flutter_repo" "$flutter_ref" "$flutter_dir"
  apply_patch_if_needed "$flutter_dir" "$PATCH_FILE"
  copy_overlay_dir "$bundle_dir/overlay" "$flutter_dir"
  prime_flutter_cache_stamps "$flutter_dir"

  local android_sdk=""
  local android_ndk=""
  android_sdk=$(detect_android_sdk || true)
  android_ndk=$(detect_android_ndk || true)

  local env_file="$install_root/env.sh"
  local wrapper_path="$install_root/bin/flutter-termux"
  write_env_file "$env_file" "$install_root" "$flutter_dir" "$tag" "$asset" "$android_sdk" "$android_ndk"
  write_wrapper "$wrapper_path" "$install_root"

  if [[ "$run_precache" == "1" ]]; then
    note "Running flutter precache --android"
    (
      # shellcheck source=/dev/null
      source "$env_file"
      "$FLUTTER_ROOT/bin/flutter" precache --android
    )
  fi

  if [[ "$keep_archive" != "1" ]]; then
    rm -f "$archive_path"
  fi

  note ""
  note "Installed Flutter SDK: $flutter_dir"
  note "Applied host bundle:   $bundle_dir"
  note "Wrapper:              $wrapper_path"
  note ""
  note "Load the environment with:"
  note "  source \"$env_file\""
  note ""
  note "Then run:"
  note "  flutter --version"
  note "  flutter doctor -v"

  if [[ -n "$android_sdk" ]]; then
    note ""
    note "Detected Android SDK:  $android_sdk"
  else
    note ""
    note "Android SDK not auto-detected. Set ANDROID_HOME/ANDROID_SDK_ROOT in env.sh if needed."
  fi

  if [[ -n "$android_ndk" ]]; then
    note "Detected Android NDK:  $android_ndk"
  fi
}

main "$@"
