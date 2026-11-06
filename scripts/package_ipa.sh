#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="${FP_IOS_BUILD:-$root/build/ios-core}"
[[ "$output" = /* ]] || output="$root/$output"
app="$output/Shapka.app"
stage="$output/ipa-stage"
[[ -x "$app/Shapka" ]] || { printf 'missing executable, run make app\n' >&2; exit 1; }
rm -rf "$stage"
mkdir -p "$stage/Payload"
cp -R "$app" "$stage/Payload/"
find "$stage/Payload" -type d -exec chmod 755 {} +
find "$stage/Payload" -type f -exec chmod 644 {} +
chmod 755 "$stage/Payload/Shapka.app/Shapka"
rm -f "$output/Shapka-unsigned.ipa"
(cd "$stage" && zip -qrX "$output/Shapka-unsigned.ipa" Payload)
unzip -tq "$output/Shapka-unsigned.ipa"
rm -rf "$stage"
printf 'built unsigned ipa: %s\n' "$output/Shapka-unsigned.ipa"
