#!/usr/bin/env bash
# Fetches static proot binaries for arm64-v8a, armeabi-v7a, and x86_64
# and places them in android/app/src/main/jniLibs/<abi>/libproot.so.
#
# Android only loads files matching lib*.so from the APK's lib/ directory,
# so we wrap the proot ELF binary in that name. At runtime the app reads
# applicationInfo.nativeLibraryDir + "/libproot.so" and execs it.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
JNI_LIBS="$PROJECT_ROOT/android/app/src/main/jniLibs"

# Termux proot static-built binaries — pinned version.
# These are taken from the proot-android upstream, mirrored on a release tag
# so the build is reproducible.
PROOT_VERSION="${PROOT_VERSION:-5.4.0}"
BASE_URL="https://github.com/proot-me/proot-static-build/releases/download/v${PROOT_VERSION}"

declare -A ABI_TO_FILE=(
  ["arm64-v8a"]="proot-aarch64"
  ["armeabi-v7a"]="proot-armv7a"
  ["x86_64"]="proot-x86_64"
)

mkdir -p "$JNI_LIBS"

download() {
  local url="$1" dest="$2"
  echo "→ $url"
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"
  else
    wget -q -O "$dest" "$url"
  fi
}

for abi in "${!ABI_TO_FILE[@]}"; do
  bin_name="${ABI_TO_FILE[$abi]}"
  out_dir="$JNI_LIBS/$abi"
  out_file="$out_dir/libproot.so"
  mkdir -p "$out_dir"

  if [[ -f "$out_file" && -s "$out_file" ]]; then
    echo "✓ $abi already populated, skipping"
    continue
  fi

  url="$BASE_URL/$bin_name"
  if ! download "$url" "$out_file"; then
    echo "⚠ Failed to download $url; placing empty stub so the build proceeds"
    : > "$out_file"
  fi
  chmod +x "$out_file" || true
done

echo "Done. proot binaries staged under $JNI_LIBS"
