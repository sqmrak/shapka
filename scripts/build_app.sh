#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
: "${FP_IOS_TC:?set FP_IOS_TC to the ios toolchain bin directory}"
: "${FP_IOS_SDK_V7:?set FP_IOS_SDK_V7 to a legacy iphoneos sdk}"
: "${FP_IOS_SDK_V64:?set FP_IOS_SDK_V64 to an arm64 iphoneos sdk}"
: "${FP_OPENSSL_V7:?set FP_OPENSSL_V7 to an armv7 openssl prefix}"
: "${FP_OPENSSL_V64:?set FP_OPENSSL_V64 to an arm64 openssl prefix}"
output="${FP_IOS_BUILD:-$root/build/ios-core}"
[[ "$output" = /* ]] || output="$root/$output"
app="$output/Shapka.app"
bash "$root/scripts/build_network_ios.sh"
sources=("$root"/app/ui/*.m "$root"/app/model/*.m "$root/app/net/FPApi.m" "$root/app/lifecycle/main.m")
flags=(-std=gnu99 -fno-objc-arc -fblocks -Wall -Wextra -Werror -O2 -I"$root/core" -I"$root/app/net" -I"$root/app/ui" -I"$root/app/model")
for arch in armv7 arm64; do
    if [[ "$arch" == armv7 ]]; then target=armv7-apple-ios5.0; sdk="$FP_IOS_SDK_V7"; ssl="$FP_OPENSSL_V7"; else target=arm64-apple-ios7.0; sdk="$FP_IOS_SDK_V64"; ssl="$FP_OPENSSL_V64"; fi
    [[ -f "$ssl/lib/libssl.a" && -f "$ssl/lib/libcrypto.a" ]] || { printf 'missing openssl libraries in %s\n' "$ssl" >&2; exit 1; }
    objects=()
    rm -rf "$output/$arch/app"
    mkdir -p "$output/$arch/app"
    for source in "${sources[@]}"; do
        object="$output/$arch/app/$(basename "${source%.m}").o"
        "$FP_IOS_TC/clang" -target "$target" -isysroot "$sdk" "${flags[@]}" -c "$source" -o "$object"
        objects+=("$object")
    done
    "$FP_IOS_TC/clang" -B"$FP_IOS_TC" -target "$target" -isysroot "$sdk" "${objects[@]}" -Wl,-all_load "$output/$arch/libshapka-network.a" "$output/$arch/libshapka.a" -Wl,-noall_load "$ssl/lib/libssl.a" "$ssl/lib/libcrypto.a" -framework UIKit -framework Foundation -framework CoreFoundation -framework CoreGraphics -framework CoreText -framework QuartzCore -framework ImageIO -framework Security -lz -o "$output/$arch/Shapka"
done
rm -rf "$app"
mkdir -p "$app"
"$FP_IOS_TC/lipo" -create "$output/armv7/Shapka" "$output/arm64/Shapka" -output "$app/Shapka"
cp "$root/packaging/Info.plist" "$app/Info.plist"
cp "$root/resources/icons/"*.png "$root/resources/ui-icons/"*.png "$root/resources/launch/"*.png "$root/resources/trust/roots.pem" "$root/resources/fonts/"* "$app/"
chmod 755 "$app/Shapka"
"$FP_IOS_TC/lipo" -info "$app/Shapka"
