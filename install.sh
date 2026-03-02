#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_OWNER="sirvkrm"
DEFAULT_REPO="flutter-android-bionic-builder"
DEFAULT_INSTALL_ROOT="${PREFIX:-$HOME/.local}/opt/flutter-bionic"

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
  ./install.sh --abi arm64-v8a
  ./install.sh --all
  ./install.sh --asset flutter-android-bionic-debug-arm64-v8a-20260302.tar.gz
  ./install.sh --list-releases

Defaults:
  - downloads the latest release from sirvkrm/flutter-android-bionic-builder
  - auto-detects the current device ABI
  - installs under $PREFIX/opt/flutter-bionic on Termux

Options:
  --interactive        Choose a release asset from a numbered list
  --list-releases      Print available release tags and exit
  --tag TAG            Install from a specific release tag
  --asset NAME         Install a specific asset name from the selected tag
  --abi ABI            Choose ABI: arm64-v8a, armeabi-v7a, x86, x86_64
  --all                Prefer the combined all-ABI bundle
  --install-root DIR   Override the installation root
  --owner NAME         Override the GitHub owner (default: sirvkrm)
  --repo NAME          Override the GitHub repo (default: flutter-android-bionic-builder)
  --keep-archive       Keep the downloaded tarball in tmp/
  -h, --help           Show this help
EOF
}

is_termux() {
  [[ -n "${PREFIX:-}" && "$PREFIX" == *"/com.termux/"* ]]
}

command_missing() {
  ! command -v "$1" >/dev/null 2>&1
}

ensure_termux_prereqs() {
  local missing=()
  local pkg_name

  for pkg_name in tar unzip python; do
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

detect_abi() {
  case "$(uname -m)" in
    aarch64|arm64)
      printf 'arm64-v8a\n'
      ;;
    armv7l|armv8l)
      printf 'armeabi-v7a\n'
      ;;
    x86_64|amd64)
      printf 'x86_64\n'
      ;;
    i?86)
      printf 'x86\n'
      ;;
    *)
      die "unsupported host architecture: $(uname -m)"
      ;;
  esac
}

normalize_abi() {
  case "${1,,}" in
    arm64|arm64-v8a|aarch64)
      printf 'arm64-v8a\n'
      ;;
    arm|armeabi|armeabi-v7a)
      printf 'armeabi-v7a\n'
      ;;
    x86)
      printf 'x86\n'
      ;;
    x64|x86_64)
      printf 'x86_64\n'
      ;;
    *)
      die "unsupported ABI: $1"
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
    "User-Agent": "flutter-bionic-termux-installer",
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
  local abi=$1
  local want_all=$2

  if [[ "$want_all" == "1" ]]; then
    printf 'flutter-android-bionic-debug-all-abis-*.tar.gz\n'
    return 0
  fi

  printf 'flutter-android-bionic-debug-%s-*.tar.gz\n' "$abi"
}

asset_to_abi() {
  case "$1" in
    flutter-android-bionic-debug-arm64-v8a-*.tar.gz)
      printf 'arm64-v8a\n'
      ;;
    flutter-android-bionic-debug-armeabi-v7a-*.tar.gz)
      printf 'armeabi-v7a\n'
      ;;
    flutter-android-bionic-debug-x86_64-*.tar.gz)
      printf 'x86_64\n'
      ;;
    flutter-android-bionic-debug-x86-*.tar.gz)
      printf 'x86\n'
      ;;
    *)
      return 1
      ;;
  esac
}

abi_native_jar_name() {
  case "$1" in
    arm64-v8a)
      printf 'arm64_v8a_debug.jar\n'
      ;;
    armeabi-v7a)
      printf 'armeabi_v7a_debug.jar\n'
      ;;
    x86)
      printf 'x86_debug.jar\n'
      ;;
    x86_64)
      printf 'x86_64_debug.jar\n'
      ;;
    *)
      die "unsupported ABI: $1"
      ;;
  esac
}

resolve_asset_name() {
  local owner=$1
  local repo=$2
  local tag=$3
  local requested_asset=$4
  local abi=$5
  local want_all=$6
  local interactive=$7
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

  preferred_pattern=$(preferred_asset_pattern "$abi" "$want_all")
  for line in "${assets[@]}"; do
    if [[ "$line" == $preferred_pattern ]]; then
      selected=$line
      break
    fi
  done

  if [[ -z "$selected" && "$want_all" == "0" ]]; then
    preferred_pattern=$(preferred_asset_pattern "$abi" "1")
    for line in "${assets[@]}"; do
      if [[ "$line" == $preferred_pattern ]]; then
        selected=$line
        break
      fi
    done
  fi

  [[ -n "$selected" ]] || die "no matching asset found for ABI $abi in $tag"
  printf '%s\n' "$selected"
}

write_env_file() {
  local env_file=$1
  local install_dir=$2
  local tag=$3
  local asset=$4
  local abi=$5
  local native_jar=$6
  local lib_path=$7
  local gen_snapshot=$8

  cat >"$env_file" <<EOF
export FLUTTER_BIONIC_HOME="$install_dir"
export FLUTTER_BIONIC_RELEASE_TAG="$tag"
export FLUTTER_BIONIC_ASSET="$asset"
export FLUTTER_BIONIC_ABI="$abi"
export FLUTTER_BIONIC_EMBEDDING_JAR="$install_dir/embedding/flutter_embedding_classes.jar"
export FLUTTER_BIONIC_NATIVE_JAR="$native_jar"
export FLUTTER_BIONIC_LIB="$lib_path"
export FLUTTER_BIONIC_GEN_SNAPSHOT="$gen_snapshot"
EOF
}

main() {
  local owner="$DEFAULT_OWNER"
  local repo="$DEFAULT_REPO"
  local install_root="$DEFAULT_INSTALL_ROOT"
  local requested_tag=""
  local requested_asset=""
  local requested_abi=""
  local list_releases=0
  local interactive=0
  local want_all=0
  local keep_archive=0

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
        requested_abi=$(normalize_abi "$1")
        ;;
      --all)
        want_all=1
        ;;
      --install-root)
        shift
        [[ $# -gt 0 ]] || die "--install-root requires a value"
        install_root=$1
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

  ensure_termux_prereqs

  if [[ "$list_releases" == "1" ]]; then
    github_release_query "list-releases" "$owner" "$repo"
    return 0
  fi

  local abi
  abi=${requested_abi:-$(detect_abi)}

  local tag
  tag=${requested_tag:-$(github_release_query "latest-tag" "$owner" "$repo")}

  local asset
  asset=$(resolve_asset_name "$owner" "$repo" "$tag" "$requested_asset" "$abi" "$want_all" "$interactive")

  local download_url
  download_url=$(github_release_query "asset-url" "$owner" "$repo" "$tag" "$asset")

  local tmp_dir="$SCRIPT_DIR/tmp"
  mkdir -p "$tmp_dir"
  local archive_path="$tmp_dir/$asset"

  note "Downloading $asset from $owner/$repo $tag"
  download_to "$download_url" "$archive_path"

  local version_dir="$install_root/releases/$tag"
  mkdir -p "$version_dir"

  local top_level
  top_level=$(archive_top_level_dir "$archive_path")
  [[ -n "$top_level" ]] || die "unable to inspect archive: $archive_path"

  rm -rf "$version_dir/$top_level"
  tar -xzf "$archive_path" -C "$version_dir"

  local install_dir="$version_dir/$top_level"
  local selected_abi="$abi"
  local native_jar_name
  local native_jar

  if asset_to_abi "$asset" >/dev/null 2>&1; then
    selected_abi=$(asset_to_abi "$asset")
  fi

  native_jar_name=$(abi_native_jar_name "$selected_abi")
  native_jar="$install_dir/embedding/$native_jar_name"
  [[ -f "$native_jar" ]] || die "missing native jar: $native_jar"

  local runtime_dir="$install_dir/runtime"
  mkdir -p "$runtime_dir"
  unzip -o "$native_jar" "lib/$selected_abi/libflutter.so" -d "$runtime_dir" >/dev/null

  local lib_path="$runtime_dir/lib/$selected_abi/libflutter.so"
  [[ -f "$lib_path" ]] || die "missing extracted libflutter.so for $selected_abi"

  local gen_snapshot="$install_dir/host-tools/linux-x64/gen_snapshot"
  local env_file="$install_dir/env.sh"
  write_env_file "$env_file" "$install_dir" "$tag" "$asset" "$selected_abi" "$native_jar" "$lib_path" "$gen_snapshot"

  mkdir -p "$install_root"
  ln -sfn "$install_dir" "$install_root/current"
  ln -sfn "$env_file" "$install_root/env.sh"

  if [[ "$keep_archive" != "1" ]]; then
    rm -f "$archive_path"
  fi

  note ""
  note "Installed: $install_dir"
  note "Current:   $install_root/current"
  note "ABI:       $selected_abi"
  note "lib:       $lib_path"
  note "embedding: $install_dir/embedding/flutter_embedding_classes.jar"
  note "native jar: $native_jar"
  note ""
  note "Load the environment with:"
  note "  source \"$install_root/env.sh\""
}

main "$@"
