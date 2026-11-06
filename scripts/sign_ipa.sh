#!/usr/bin/env bash
set -euo pipefail

: "${FP_IOS_TC:?set FP_IOS_TC to the ios toolchain bin directory}"
root="$(cd "$(dirname "$0")/.." && pwd)"
output="${FP_IOS_BUILD:-$root/build/ios-core}"
[[ "$output" = /* ]] || output="$root/$output"
version="${FP_VERSION:-v1.0.0-stable}"
entitlements="$root/packaging/entitlements.plist"
app="$output/Shapka.app"
stage="$output/signed-stage"
ipa="$output/Shapka-$version.ipa"
[[ -x "$FP_IOS_TC/ldid" ]] || { printf 'missing %s/ldid\n' "$FP_IOS_TC" >&2; exit 1; }
[[ -x "$app/Shapka" ]] || { printf 'missing executable, run make ipa first\n' >&2; exit 1; }
[[ -f "$entitlements" ]] || { printf 'missing %s\n' "$entitlements" >&2; exit 1; }
plist_version="$(grep -a -A1 CFBundleShortVersionString "$root/packaging/Info.plist" | sed -n 's|.*<string>\(.*\)</string>.*|\1|p')"
[[ "v$plist_version" = "${version%%-*}" ]] || { printf 'Info.plist says %s, the name says %s\n' "$plist_version" "$version" >&2; exit 1; }
rm -rf "$stage"
mkdir -p "$stage/Payload"
cp -R "$app" "$stage/Payload/"
find "$stage/Payload" -type d -exec chmod 755 {} +
find "$stage/Payload" -type f -exec chmod 644 {} +
# the keychain needs application-identifier and keychain-access-groups on ios 6, or every write fails with -25308
"$FP_IOS_TC/ldid" -S"$entitlements" "$stage/Payload/Shapka.app/Shapka"
chmod 755 "$stage/Payload/Shapka.app/Shapka"
rm -f "$ipa"
(cd "$stage" && zip -qrX "$ipa" Payload)
unzip -tq "$ipa"
rm -rf "$stage"
printf 'built signed ipa: %s\n' "$ipa"
