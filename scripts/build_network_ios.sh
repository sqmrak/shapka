#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$root/scripts/build_core.sh"
output="${FP_IOS_BUILD:-$root/build/ios-core}"
[[ "$output" = /* ]] || output="$root/$output"
for name in FPNetwork FPAccountStore FPDownload; do
    "$FP_IOS_TC/clang" -target armv7-apple-ios5.0 -isysroot "$FP_IOS_SDK_V7" -std=gnu99 -fno-objc-arc -fblocks -Wall -Wextra -Werror -O2 -I"$root/core" -I"$root/app/net" -c "$root/app/net/$name.m" -o "$output/armv7/$name.o"
    "$FP_IOS_TC/clang" -target arm64-apple-ios7.0 -isysroot "$FP_IOS_SDK_V64" -std=gnu99 -fno-objc-arc -fblocks -Wall -Wextra -Werror -O2 -I"$root/core" -I"$root/app/net" -c "$root/app/net/$name.m" -o "$output/arm64/$name.o"
done
rm -f "$output/armv7/libshapka-network.a" "$output/arm64/libshapka-network.a"
"$FP_IOS_TC/llvm-ar" rcs "$output/armv7/libshapka-network.a" "$output/armv7/FPNetwork.o" "$output/armv7/FPAccountStore.o" "$output/armv7/FPDownload.o"
"$FP_IOS_TC/llvm-ar" rcs "$output/arm64/libshapka-network.a" "$output/arm64/FPNetwork.o" "$output/arm64/FPAccountStore.o" "$output/arm64/FPDownload.o"
"$FP_IOS_TC/lipo" -create "$output/armv7/libshapka-network.a" "$output/arm64/libshapka-network.a" -output "$output/libshapka-network.a"
"$FP_IOS_TC/lipo" -info "$output/libshapka-network.a"
