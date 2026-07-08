#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/build/ios/iphoneos/Runner.app}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build/ios/ipa}"
IPA_NAME="${IPA_NAME:-Runner-unsigned.ipa}"
BUILD_FIRST="${BUILD_FIRST:-0}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/package_unsigned_ipa.sh [--build] [--app PATH] [--out DIR] [--name FILE.ipa]

Options:
  --build        Run "flutter build ios --release --no-codesign" first.
  --app PATH     Path to Runner.app. Defaults to build/ios/iphoneos/Runner.app.
  --out DIR      Output directory. Defaults to build/ios/ipa.
  --name FILE    IPA filename. Defaults to Runner-unsigned.ipa.
  -h, --help     Show this help.

Environment overrides:
  APP_PATH, OUTPUT_DIR, IPA_NAME, BUILD_FIRST=1
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      BUILD_FIRST=1
      shift
      ;;
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --out)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --name)
      IPA_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$IPA_NAME" != *.ipa ]]; then
  IPA_NAME="$IPA_NAME.ipa"
fi

if [[ "$BUILD_FIRST" == "1" ]]; then
  (cd "$ROOT_DIR" && flutter build ios --release --no-codesign)
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Runner.app not found: $APP_PATH" >&2
  echo "Build it first with: flutter build ios --release --no-codesign" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

WORK_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/Runner.app"

IPA_PATH="$OUTPUT_DIR/$IPA_NAME"
rm -f "$IPA_PATH"

(cd "$WORK_DIR" && /usr/bin/zip -qry "$IPA_PATH" Payload)

echo "Unsigned IPA created:"
echo "$IPA_PATH"
