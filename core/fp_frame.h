#ifndef FP_FRAME_H
#define FP_FRAME_H

#include <stddef.h>
#include <stdint.h>

#define FP_FRAME_LIMIT (8u * 1024u * 1024u)

typedef enum {
    FP_FRAME_OK = 0,
    FP_FRAME_INCOMPLETE,
    FP_FRAME_INVALID,
    FP_FRAME_LIMIT_EXCEEDED,
    FP_FRAME_COMPRESSION_ERROR
} fp_frame_status;

typedef struct {
    uint8_t opcode;
    int final;
    int compressed;
    const uint8_t *payload;
    size_t payload_length;
    size_t consumed;
} fp_frame;

fp_frame_status fp_frame_read(const uint8_t *data, size_t length, fp_frame *frame);
fp_frame_status fp_frame_encode(const uint8_t *payload, size_t length, uint8_t opcode,
                                int final, uint8_t *output, size_t capacity, size_t *written);
fp_frame_status fp_frame_inflate(const fp_frame *frame, uint8_t *output, size_t capacity,
                                 size_t *written);

#endif
