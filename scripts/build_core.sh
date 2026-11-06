#!/usr/bin/env bash
set -euo pipefail

: "${FP_IOS_TC:?set FP_IOS_TC to the ios toolchain bin directory}"
: "${FP_IOS_SDK_V7:?set FP_IOS_SDK_V7 to a legacy iphoneos sdk}"
: "${FP_IOS_SDK_V64:?set FP_IOS_SDK_V64 to an arm64 iphoneos sdk}"
: "${FP_OPENSSL_V7:?set FP_OPENSSL_V7 to an armv7 openssl prefix}"
: "${FP_OPENSSL_V64:?set FP_OPENSSL_V64 to an arm64 openssl prefix}"
root="$(cd "$(dirname "$0")/.." && pwd)"
output="${FP_IOS_BUILD:-$root/build/ios-core}"
[[ "$output" = /* ]] || output="$root/$output"
for program in clang llvm-ar lipo; do
    [[ -x "$FP_IOS_TC/$program" ]] || { printf 'missing %s/%s\n' "$FP_IOS_TC" "$program" >&2; exit 1; }
done
[[ -f "$FP_IOS_SDK_V7/usr/include/stdlib.h" && -f "$FP_IOS_SDK_V64/usr/include/stdlib.h" ]] || { printf 'missing ios sdk headers\n' >&2; exit 1; }
mkdir -p "$output/armv7" "$output/arm64"
names=(fp_theme_settings fp_frame fp_document fp_compose fp_qms fp_session fp_tls fp_resolve fp_client fp_auth fp_text fp_forum fp_bbcode fp_guest fp_http fp_news_http fp_news_image fp_news_article fp_news_body fp_webp)
for name in "${names[@]}"; do
    "$FP_IOS_TC/clang" -target armv7-apple-ios5.0 -isysroot "$FP_IOS_SDK_V7" -I"$FP_OPENSSL_V7/include" -std=c99 -Wall -Wextra -Werror -O2 -I"$root/vendor/libwebp/src" -c "$root/core/$name.c" -o "$output/armv7/$name.o"
    "$FP_IOS_TC/clang" -target arm64-apple-ios7.0 -isysroot "$FP_IOS_SDK_V64" -I"$FP_OPENSSL_V64/include" -std=c99 -Wall -Wextra -Werror -O2 -I"$root/vendor/libwebp/src" -c "$root/core/$name.c" -o "$output/arm64/$name.o"
done
webp_sources=(dec/alpha_dec dec/buffer_dec dec/frame_dec dec/idec_dec dec/io_dec dec/quant_dec dec/tree_dec dec/vp8_dec dec/vp8l_dec dec/webp_dec dsp/alpha_processing dsp/cpu dsp/dec dsp/dec_clip_tables dsp/filters dsp/lossless dsp/rescaler dsp/upsampling dsp/yuv utils/bit_reader_utils utils/color_cache_utils utils/filters_utils utils/huffman_utils utils/palette utils/quant_levels_dec_utils utils/rescaler_utils utils/random_utils utils/thread_utils utils/utils)
webp_flags=(-std=c99 -O2 -DHAVE_CONFIG_H -w -I"$root/vendor/libwebp" -I"$root/vendor/libwebp/src")
webp_armv7=()
webp_arm64=()
# libwebp is vendored as is, so it builds without the project warning flags; ios before 14 cannot decode the webp pictures of 4pda
for name in "${webp_sources[@]}"; do
    object="$(echo "$name" | tr / _)"
    "$FP_IOS_TC/clang" -target armv7-apple-ios5.0 -isysroot "$FP_IOS_SDK_V7" "${webp_flags[@]}" -c "$root/vendor/libwebp/src/$name.c" -o "$output/armv7/webp_$object.o"
    "$FP_IOS_TC/clang" -target arm64-apple-ios7.0 -isysroot "$FP_IOS_SDK_V64" "${webp_flags[@]}" -c "$root/vendor/libwebp/src/$name.c" -o "$output/arm64/webp_$object.o"
    webp_armv7+=("$output/armv7/webp_$object.o")
    webp_arm64+=("$output/arm64/webp_$object.o")
done
rm -f "$output/armv7/libshapka.a" "$output/arm64/libshapka.a"
armv7_objects=()
arm64_objects=()
for name in "${names[@]}"; do
    armv7_objects+=("$output/armv7/$name.o")
    arm64_objects+=("$output/arm64/$name.o")
done
"$FP_IOS_TC/llvm-ar" rcs "$output/armv7/libshapka.a" "${armv7_objects[@]}" "${webp_armv7[@]}"
"$FP_IOS_TC/llvm-ar" rcs "$output/arm64/libshapka.a" "${arm64_objects[@]}" "${webp_arm64[@]}"
"$FP_IOS_TC/lipo" -create "$output/armv7/libshapka.a" "$output/arm64/libshapka.a" -output "$output/libshapka.a"
"$FP_IOS_TC/lipo" -info "$output/libshapka.a"
