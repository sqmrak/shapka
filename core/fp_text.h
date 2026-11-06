#ifndef FP_TEXT_H
#define FP_TEXT_H

#include <stddef.h>
#include <stdint.h>

/* raw bytes of a document string between its quotes, still windows-1251 and escaped */
typedef struct {
    const uint8_t *data;
    size_t length;
} fp_span;

typedef enum { FP_TEXT_OK, FP_TEXT_INVALID, FP_TEXT_LIMIT } fp_text_status;

/* the worst case of fp_text_decode: one windows-1251 byte grows to three utf-8 bytes */
#define FP_TEXT_UTF8_BOUND(length) ((length) * 3u + 1u)

/* decodes escapes and windows-1251 into utf-8 with a terminating zero; output is cut at a character boundary
   and FP_TEXT_LIMIT is returned when the capacity is too small */
fp_text_status fp_text_decode(fp_span span, char *output, size_t capacity, size_t *written);

/* resolves html entities in utf-8 text, unknown entities stay as written; the output never exceeds the input */
size_t fp_text_unescape_entities(const char *input, size_t length, char *output, size_t capacity);

#endif
