#!/usr/bin/env bash
# one archive for ios 5 through 16: the payload sits in /var/jb, which rootless jailbreaks
# register directly and rootful ones copy into /Applications from postinst
set -euo pipefail

: "${FP_IOS_TC:?set FP_IOS_TC to the ios toolchain bin directory}"
root="$(cd "$(dirname "$0")/.." && pwd)"
output="${FP_IOS_BUILD:-$root/build/ios-core}"
[[ "$output" = /* ]] || output="$root/$output"
control="$root/packaging/deb/control"
entitlements="$root/packaging/entitlements.plist"
app="$output/Shapka.app"
stage="$output/deb-stage"
version="$(awk -F': ' '$1 == "Version" { print $2; exit }' "$control")"
arch="$(awk -F': ' '$1 == "Architecture" { print $2; exit }' "$control")"
[[ "$version" =~ ^[0-9][0-9A-Za-z.+:~-]*$ ]] || { printf 'invalid package version: %s\n' "${version:-<empty>}" >&2; exit 1; }
[[ "$arch" = all ]] || { printf 'the universal package must use Architecture: all\n' >&2; exit 1; }
plist_version="$(grep -a -A1 CFBundleShortVersionString "$root/packaging/Info.plist" | sed -n 's|.*<string>\(.*\)</string>.*|\1|p')"
[[ "${version%%-*}" = "$plist_version" ]] || { printf 'Info.plist says %s, the control file says %s\n' "$plist_version" "$version" >&2; exit 1; }
[[ -x "$FP_IOS_TC/ldid" ]] || { printf 'missing %s/ldid\n' "$FP_IOS_TC" >&2; exit 1; }
[[ -x "$app/Shapka" ]] || { printf 'missing executable, run make app\n' >&2; exit 1; }
[[ -f "$entitlements" ]] || { printf 'missing %s\n' "$entitlements" >&2; exit 1; }

# a stale stage would ship files of an older layout inside the new package
rm -rf "$stage"
payload="$stage/var/jb/Applications"
mkdir -p "$payload" "$stage/DEBIAN"
cp -R "$app" "$payload/"
cp "$control" "$stage/DEBIAN/control"
cp "$root/packaging/deb/postinst" "$root/packaging/deb/postrm" "$stage/DEBIAN/"
find "$payload" -type d -exec chmod 755 {} +
find "$payload" -type f -exec chmod 644 {} +
# the keychain needs application-identifier and keychain-access-groups on ios 6, or every write fails with -25308
"$FP_IOS_TC/ldid" -S"$entitlements" "$payload/Shapka.app/Shapka"
chmod 755 "$payload/Shapka.app/Shapka" "$stage/DEBIAN/postinst" "$stage/DEBIAN/postrm"

deb="$output/shapka_$version.deb"
rm -f "$deb"
# gzip members, because dpkg on ios 5 cannot read zstd or xz
dpkg-deb -Zgzip --build --root-owner-group "$stage" "$deb" >/dev/null
rm -rf "$stage"
printf 'built deb: %s\n' "$deb"
