#include "fp_webp.h"
#include <stdlib.h>
#include <string.h>
#include "webp/decode.h"

#define WEBP_INPUT_LIMIT (4u * 1024u * 1024u)
#define WEBP_SOURCE_PIXELS (24u * 1000u * 1000u)

int fp_webp_is_webp(const uint8_t *data, size_t length)
{
    return data && length >= 12 && !memcmp(data, "RIFF", 4) && !memcmp(data + 8, "WEBP", 4);
}

fp_webp_status fp_webp_decode(const uint8_t *data, size_t length, int max_edge, uint8_t **rgba, int *width, int *height)
{
    int source_width = 0, source_height = 0, out_width, out_height;
    size_t stride, bytes;
    uint8_t *pixels;
    WebPDecoderConfig config;
    if (rgba) *rgba = NULL;
    if (width) *width = 0;
    if (height) *height = 0;
    if (!data || !rgba || !width || !height || max_edge < 1 || max_edge > 4096) return FP_WEBP_ARGUMENT;
    if (!fp_webp_is_webp(data, length)) return FP_WEBP_NOT_WEBP;
    if (length > WEBP_INPUT_LIMIT) return FP_WEBP_TOO_LARGE;
    if (!WebPGetInfo(data, length, &source_width, &source_height) || source_width < 1 || source_height < 1) return FP_WEBP_MALFORMED;
    if ((size_t)source_width > WEBP_SOURCE_PIXELS / (size_t)source_height) return FP_WEBP_TOO_LARGE;
    out_width = source_width;
    out_height = source_height;
    if (source_width > max_edge || source_height > max_edge) {
        if (source_width >= source_height) {
            out_width = max_edge;
            out_height = (int)(((int64_t)source_height * max_edge + source_width / 2) / source_width);
        } else {
            out_height = max_edge;
            out_width = (int)(((int64_t)source_width * max_edge + source_height / 2) / source_height);
        }
        if (out_width < 1) out_width = 1;
        if (out_height < 1) out_height = 1;
    }
    stride = (size_t)out_width * 4u;
    bytes = stride * (size_t)out_height;
    pixels = malloc(bytes);
    if (!pixels) return FP_WEBP_MEMORY;
    if (!WebPInitDecoderConfig(&config)) { free(pixels); return FP_WEBP_MALFORMED; }
    config.output.colorspace = MODE_RGBA;
    config.output.u.RGBA.rgba = pixels;
    config.output.u.RGBA.stride = (int)stride;
    config.output.u.RGBA.size = bytes;
    config.output.is_external_memory = 1;
    config.options.use_scaling = out_width != source_width || out_height != source_height;
    config.options.scaled_width = out_width;
    config.options.scaled_height = out_height;
    if (WebPDecode(data, length, &config) != VP8_STATUS_OK) {
        WebPFreeDecBuffer(&config.output);
        free(pixels);
        return FP_WEBP_MALFORMED;
    }
    WebPFreeDecBuffer(&config.output);
    *rgba = pixels;
    *width = out_width;
    *height = out_height;
    return FP_WEBP_OK;
}
