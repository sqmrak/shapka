#ifndef FP_DOCUMENT_H
#define FP_DOCUMENT_H

#include <stddef.h>
#include <stdint.h>

#define FP_DOCUMENT_DEPTH_LIMIT 32u
#define FP_DOCUMENT_NO_PARENT ((size_t)-1)

typedef enum { FP_DOCUMENT_ARRAY, FP_DOCUMENT_INTEGER, FP_DOCUMENT_STRING } fp_document_type;
typedef enum { FP_DOCUMENT_OK, FP_DOCUMENT_INVALID, FP_DOCUMENT_LIMIT } fp_document_status;

typedef struct {
    fp_document_type type;
    size_t offset;
    size_t length;
    size_t parent;
    size_t children;
} fp_document_token;

/* offsets point into the caller-owned windows-1251 input, strings include their quotes */
fp_document_status fp_document_parse(const uint8_t *data, size_t length,
                                     fp_document_token *tokens, size_t capacity, size_t *count);

/* escapes a windows-1251 byte string, including surrounding quotes */
fp_document_status fp_document_quote(const uint8_t *input, size_t length,
                                     uint8_t *output, size_t capacity, size_t *written);

#endif
