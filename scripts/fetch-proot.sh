#!/usr/bin/env bash
# Fetches static proot binaries for arm64-v8a, armeabi-v7a, and x86_64 and
# places them in android/app/src/main/jniLibs/<abi>/libproot.so.
#
# Android only loads files matching lib*.so from the APK's lib/ directory, so
# we wrap the proot ELF binary in that name. At runtime the app reads
# applicationInfo.nativeLibraryDir + "/libproot.so" and execs it.
#
# Modes:
#   default                 — download missing binaries
#   STRICT=1                — fail (exit 1) if any binary cannot be downloaded
#                             (instead of producing an empty stub)
#   --check                 — print expected paths and current state, then exit
#
# Mirrors are tried in order. Override PROOT_VERSION to pin a different release.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
JNI_LIBS="$PROJECT_ROOT/android/app/src/main/jniLibs"

PROOT_VERSION="${PROOT_VERSION:-5.4.0}"
STRICT="${STRICT:-0}"

declare -a MIRRORS=(
  "https://github.com/proot-me/proot-static-build/releases/download/v${PROOT_VERSION}"
  "https://github.com/termux/proot/releases/download/v${PROOT_VERSION}"
)

declare -A ABI_TO_FILE=(
  ["arm64-v8a"]="proot-aarch64"
  ["armeabi-v7a"]="proot-armv7a"
  ["x86_64"]="proot-x86_64"
)

if [[ "${1:-}" == "--check" ]]; then
  echo "PROOT_VERSION=$PROOT_VERSION"
  echo "JNI_LIBS=$JNI_LIBS"
  for abi in "${!ABI_TO_FILE[@]}"; do
    out="$JNI_LIBS/$abi/libproot.so"
    if [[ -s "$out" ]]; then
      echo "  ✓ $abi  ($(wc -c < "$out") bytes)"
    else
      echo "  ✗ $abi  (missing)"
    fi
  done
  exit 0
fi

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

failed=0
for abi in "${!ABI_TO_FILE[@]}"; do
  bin_name="${ABI_TO_FILE[$abi]}"
  out_dir="$JNI_LIBS/$abi"
  out_file="$out_dir/libproot.so"
  mkdir -p "$out_dir"

  if [[ -f "$out_file" && -s "$out_file" ]]; then
    echo "✓ $abi already populated, skipping"
    continue
  fi

  ok=0
  for base in "${MIRRORS[@]}"; do
    if download "$base/$bin_name" "$out_file" 2>/dev/null; then
      ok=1
      break
    fi
    rm -f "$out_file"
  done

  if [[ $ok -eq 0 ]]; then
    echo "⚠ failed to download $bin_name from any mirror"
    failed=$((failed + 1))
    if [[ "$STRICT" != "1" ]]; then
      : > "$out_file"  # empty stub so the build still succeeds
    fi
  else
    chmod +x "$out_file" || true
  fi
done

if [[ $failed -gt 0 && "$STRICT" == "1" ]]; then
  echo "FAIL: $failed ABI(s) could not be populated (STRICT=1)" >&2
  exit 1
fi

echo "Done. proot binaries staged under $JNI_LIBS"
