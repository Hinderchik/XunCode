#!/usr/bin/env bash
# Fetches static proot binaries for arm64-v8a, armeabi-v7a, x86_64, and x86 and
# places them in android/app/src/main/jniLibs/<abi>/libproot.so.
#
# Android only loads files matching lib*.so from the APK's lib/ directory, so
# we wrap the proot ELF binary in that name. At runtime the app reads
# applicationInfo.nativeLibraryDir + "/libproot.so" and execs it.
#
# If the script fails to populate jniLibs (offline build environment, mirrors
# down, etc.), the app falls back to downloading proot at runtime via
# TerminalService.downloadProot() — so a missing binary at build time doesn't
# brick the terminal. Set STRICT=1 to fail the build instead.
#
# Modes:
#   default         — download missing binaries
#   STRICT=1        — exit 1 if any binary cannot be downloaded
#   --check         — print expected paths and current state, then exit

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
JNI_LIBS="$PROJECT_ROOT/android/app/src/main/jniLibs"

PROOT_VERSION="${PROOT_VERSION:-5.4.0}"
STRICT="${STRICT:-0}"

# Mirrors of the proot static binary. We try several upstreams in order:
#   1. termux/proot — Termux-maintained static builds (most reliable for arm).
#   2. proot-me/proot-static-build — original upstream's GitHub releases.
#   3. proot-me/proot-static-build/latest — moving alias for the most recent build.
declare -a MIRRORS=(
  "https://github.com/termux/proot/releases/download/v5.3.0"
  "https://github.com/proot-me/proot-static-build/releases/download/v${PROOT_VERSION}"
  "https://github.com/proot-me/proot-static-build/releases/latest/download"
)

# termux/proot uses different filenames than proot-static-build, so each ABI has
# a primary file plus a list of aliases the loop will try in turn.
declare -A ABI_TO_FILE=(
  ["arm64-v8a"]="proot-aarch64"
  ["armeabi-v7a"]="proot-armv7a"
  ["x86_64"]="proot-x86_64"
  ["x86"]="proot-x86"
)
declare -A ABI_TO_ALIAS=(
  ["arm64-v8a"]="proot-aarch64 proot-arm64"
  ["armeabi-v7a"]="proot-armv7a proot-arm"
  ["x86_64"]="proot-x86_64"
  ["x86"]="proot-x86 proot-i686"
)

if [[ "${1:-}" == "--check" ]]; then
  echo "PROOT_VERSION=$PROOT_VERSION"
  echo "JNI_LIBS=$JNI_LIBS"
  for abi in "${!ABI_TO_FILE[@]}"; do
    out="$JNI_LIBS/$abi/libproot.so"
    if [[ -s "$out" ]]; then
      bytes=$(wc -c < "$out")
      echo "  ✓ $abi  ($bytes bytes)"
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

  if [[ -f "$out_file" && -s "$out_file" && $(wc -c < "$out_file") -gt 1024 ]]; then
    echo "✓ $abi already populated, skipping"
    continue
  fi

  ok=0
  # Try every mirror × every alias filename until something sticks.
  aliases="${ABI_TO_ALIAS[$abi]:-$bin_name}"
  for base in "${MIRRORS[@]}"; do
    [[ $ok -eq 1 ]] && break
    for alias_name in $aliases; do
      if download "$base/$alias_name" "$out_file" 2>/dev/null; then
        sz=$(wc -c < "$out_file" 2>/dev/null || echo 0)
        if [[ $sz -lt 1024 ]]; then
          echo "  ⚠ downloaded file too small ($sz bytes), trying next"
          rm -f "$out_file"
          continue
        fi
        chmod +x "$out_file" || true
        ok=1
        break
      fi
      rm -f "$out_file"
    done
  done

  if [[ $ok -eq 0 ]]; then
    echo "⚠ failed to download $bin_name from any mirror"
    failed=$((failed + 1))
    if [[ "$STRICT" != "1" ]]; then
      : > "$out_file"  # empty stub so the build still succeeds; runtime will fetch
    fi
  fi
done

if [[ $failed -gt 0 && "$STRICT" == "1" ]]; then
  echo "FAIL: $failed ABI(s) could not be populated (STRICT=1)" >&2
  exit 1
fi

echo "Done. proot binaries staged under $JNI_LIBS"
echo "Tip: at runtime the app re-downloads proot if any libproot.so is empty."
