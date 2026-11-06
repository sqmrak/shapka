#ifndef FP_WEBP_H
#define FP_WEBP_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
    FP_WEBP_OK = 0,
    FP_WEBP_ARGUMENT,
    FP_WEBP_NOT_WEBP,
    FP_WEBP_TOO_LARGE,
    FP_WEBP_MALFORMED,
    FP_WEBP_MEMORY
} fp_webp_status;

/* decodes straight to non-premultiplied rgba scaled so the longer side is at most max_edge; the caller frees *rgba */
fp_webp_status fp_webp_decode(const uint8_t *data, size_t length, int max_edge, uint8_t **rgba, int *width, int *height);

int fp_webp_is_webp(const uint8_t *data, size_t length);

#endif
