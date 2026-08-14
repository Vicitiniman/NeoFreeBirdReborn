#!/usr/bin/env bash
set -Eeuo pipefail

# NeoFreeBird builder with required flags.
# Usage: build.sh [--sideloaded | --rootless | --trollstore | --rootfull]

is_tty=0
if [[ -t 1 ]]; then is_tty=1; fi
bold='' green='' reset=''
if [[ "$is_tty" -eq 1 ]]; then
  if command -v tput >/dev/null 2>&1; then
    bold="$(tput bold || true)"
    green="$(tput setaf 2 || true)"
    reset="$(tput sgr0 || true)"
  else
    bold='\033[1m'; green='\033[32m'; reset='\033[0m'
  fi
fi

say() { if [[ -n "${bold}${green}${reset}" ]]; then printf "%b%s%b\n" "${bold}${green}" "$1" "${reset}"; else printf "%s\n" "$1"; fi; }
err() { printf "Error: %s\n" "$1" >&2; }
die() { err "$1"; exit 1; }

NFB_TIMINGS_FILE="${NFB_TIMINGS_FILE:-}"
BUILD_SCRIPT_STARTED_AT="$(date +%s)"

record_timing() {
  local phase="$1" started_at="$2" finished_at
  [[ -n "$NFB_TIMINGS_FILE" ]] || return 0
  finished_at="$(date +%s)"
  mkdir -p "$(dirname "$NFB_TIMINGS_FILE")"
  printf '%s\t%s\n' "$phase" "$((finished_at - started_at))" >> "$NFB_TIMINGS_FILE"
}

record_total_timing() {
  record_timing "Total build.sh" "$BUILD_SCRIPT_STARTED_AT"
}
trap record_total_timing EXIT

run_timed() {
  local phase="$1" started_at status=0
  shift
  started_at="$(date +%s)"
  "$@" || status=$?
  record_timing "$phase" "$started_at"
  return "$status"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [--sideloaded | --rootless | --trollstore | --rootfull]
TL;DR: You need to select one flag to build NeoFreeBird.

Flags (required):
  --sideloaded   Compile NeoFreeBird as a .ipa so you can sideload it with AltStore, Sideloadly or similar.
  --rootless     Compile NeoFreeBird as a rootless-jailbreak .deb file.
  --trollstore   Compile NeoFreeBird as a .tipa so you can install it using TrollStore.
  --rootfull     Compile NeoFreeBird as a rootful-jailbreak .deb file.

Options:
  -h, --help     Show this help

Sideloaded and TrollStore builds use the Twitter display name, replace the
pre-injection launch X with a blue bird, and include the selectable classic
Twitter bird icon. rebrand.sh can apply other theme packs.
EOF
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found in PATH"; }

require_cmd bash
require_cmd make

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

detect_build_jobs() {
  local jobs="${NFB_BUILD_JOBS:-}"
  if [[ -z "$jobs" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      jobs="$(sysctl -n hw.logicalcpu 2>/dev/null || printf '1')"
    elif command -v nproc >/dev/null 2>&1; then
      jobs="$(nproc)"
    else
      jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')"
    fi
  fi

  [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die "NFB_BUILD_JOBS must be a positive integer."
  # The tweak and FLEX compile comfortably in parallel, while this cap avoids
  # excessive memory pressure on shared CI runners and older development Macs.
  if (( jobs > 8 )); then jobs=8; fi
  printf '%s\n' "$jobs"
}

BUILD_JOBS="$(detect_build_jobs)"
say "Using ${BUILD_JOBS} parallel make job(s)."

MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sideloaded|--sideloaded=*)
      [[ -n "$MODE" ]] && die "Multiple flags provided. Choose one."
      MODE="sideloaded"; shift
      ;;
    --rootless|--rootless=*)
      [[ -n "$MODE" ]] && die "Multiple flags provided. Choose one."
      MODE="rootless"; shift
      ;;
    --trollstore)
      [[ -n "$MODE" ]] && die "Multiple flags provided. Choose one."
      MODE="trollstore"; shift
      ;;
    --rootfull)
      [[ -n "$MODE" ]] && die "Multiple flags provided. Choose one."
      MODE="rootfull"; shift
      ;;
    -h|--help)
      usage; exit 0
      ;;
    --)
      shift; break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      # no positional args expected
      die "Unexpected argument: $1"
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  usage
  exit 2
fi

clean_tree() {
  if [[ -d .theos ]]; then rm -rf .theos; fi
  if [[ -f Makefile ]]; then make clean || true; fi
}

run_make() {
  local phase="$1"
  shift
  run_timed "$phase" make -j"$BUILD_JOBS" "$@"
}

find_build_artifact() {
  local artifact="$1"
  local result
  result="$(find "$SCRIPT_DIR" -path '*/.theos/obj/*' -type f -name "$artifact" -print -quit)"
  [[ -n "$result" ]] || die "Build completed without producing $artifact."
  printf '%s\n' "$result"
}

validate_runtime_linkage() {
  local dylib="$1"
  if ! command -v otool >/dev/null 2>&1; then
    return 0
  fi

  local linked_frameworks
  linked_frameworks="$(otool -L "$dylib")"
  if grep -Eq 'Cephei(Prefs|UI)?\.framework|/Preferences\.framework' <<<"$linked_frameworks"; then
    printf '%s\n' "$linked_frameworks" >&2
    die "BHTwitter.dylib links a settings-only framework that must not load inside X."
  fi
}

apply_sideload_branding() {
  local ipa="$SCRIPT_DIR/packages/com.atebits.Tweetie2.ipa"
  local icon="$SCRIPT_DIR/branding/TwitterAppIcon.png"
  bash "$SCRIPT_DIR/rebrand.sh" --twitter-branding --twitter-icon "$icon" "$ipa"
}

# The ffmpeg stack is built from source, not tracked. Check a representative
# header and both wrapper/core archives so a partial cache cannot be accepted.
if [[ ! -f "$SCRIPT_DIR/deps/ffmpeg-kit-next/build/FFmpegKit.h" ||
      ! -f "$SCRIPT_DIR/deps/ffmpeg-kit-next/build/lib/libffmpegkit.a" ||
      ! -f "$SCRIPT_DIR/deps/ffmpeg-kit-next/build/lib/libavcodec.a" ]]; then
  say "ffmpeg libraries not found; building them from source (this takes a while)."
  git -C "$SCRIPT_DIR" submodule update --init --depth 1 deps/ffmpeg-kit-next/upstream
  run_timed "ffmpeg source build" "$SCRIPT_DIR/deps/ffmpeg-kit-next/build-ffmpeg.sh" || \
    die "An error occurred while building ffmpeg."
fi

case "$MODE" in
  sideloaded)
    say "Preparing to compile NeoFreeBird. Argument added: --sideloaded."
    run_timed "Clean build tree" clean_tree
    run_make "Sideloaded compile" SIDELOADED=1 || die "An error occurred when building."
    if [[ -e ./packages/com.atebits.Tweetie2.ipa ]]; then
      say "Building the IPA."
      run_timed "Sideloaded branding" apply_sideload_branding || die "Branding failed."
      if command -v cyan >/dev/null 2>&1; then
        BHT_DYLIB="$(find_build_artifact BHTwitter.dylib)"
        validate_runtime_linkage "$BHT_DYLIB"
        FLEX_DYLIB="$(find_build_artifact libbhFLEX.dylib)"
        ZX_DYLIB="$(find_build_artifact zxPluginsInject.dylib)"
        run_timed "Sideloaded IPA injection" cyan \
          -i packages/com.atebits.Tweetie2.ipa \
          -o packages/NeoFreeBird-sideloaded \
          --ignore-encrypted \
          -uwf "$ZX_DYLIB" "$FLEX_DYLIB" "$BHT_DYLIB" \
          "layout/Library/Application Support/BHT/BHTwitter.bundle" || \
          die "IPA injection failed."
      else
        say "Skipping cyan step because it is not installed."
      fi
      say "NeoFreeBird has been successfully built. Enjoy!"
    else
      err "packages/com.atebits.Tweetie2.ipa not found."
    fi
    ;;
  rootless)
    say "Preparing to compile NeoFreeBird. Argument added: --rootless."
    run_timed "Clean build tree" clean_tree
    export THEOS_PACKAGE_SCHEME="rootless"
    run_make "Rootless package" package || die "An error occurred when building."
    validate_runtime_linkage "$(find_build_artifact BHTwitter.dylib)"
    say "NeoFreeBird has been successfully built. Enjoy!"
    ;;
  trollstore)
    say "Preparing to compile NeoFreeBird. Argument added: --trollstore."
    run_timed "Clean build tree" clean_tree
    run_make "TrollStore compile" || die "An error occurred when building."
    if [[ -e ./packages/com.atebits.Tweetie2.ipa ]]; then
      say "Merging NeoFreeBird to provided Twitter IPA."
      run_timed "TrollStore branding" apply_sideload_branding || die "Branding failed."
      if command -v cyan >/dev/null 2>&1; then
        BHT_DYLIB="$(find_build_artifact BHTwitter.dylib)"
        validate_runtime_linkage "$BHT_DYLIB"
        FLEX_DYLIB="$(find_build_artifact libbhFLEX.dylib)"
        run_timed "TrollStore IPA injection" cyan \
          -i packages/com.atebits.Tweetie2.ipa \
          -o packages/NeoFreeBird-trollstore.tipa \
          --ignore-encrypted \
          -uwf "$BHT_DYLIB" "$FLEX_DYLIB" \
          "layout/Library/Application Support/BHT/BHTwitter.bundle" || \
          die "IPA injection failed."
      else
        say "Skipping cyan step because it is not installed."
      fi
      say "NeoFreeBird has been successfully built. Enjoy!"
    else
      err "packages/com.atebits.Tweetie2.ipa not found."
    fi
    ;;
  rootfull)
    say "Preparing to compile NeoFreeBird. Argument added: --rootfull."
    run_timed "Clean build tree" clean_tree
    unset THEOS_PACKAGE_SCHEME || true
    run_make "Rootful package" package || die "An error occurred when building."
    validate_runtime_linkage "$(find_build_artifact BHTwitter.dylib)"
    say "NeoFreeBird has been successfully built. Enjoy!"
    ;;
  *)
    die "Unknown mode: $MODE"
    ;;
esac
