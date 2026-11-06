#include "fp_frame.h"

#include <limits.h>
#include <string.h>
#include <stdlib.h>
#include <zlib.h>

static void clear_buffer(uint8_t *buffer, size_t length)
{
    volatile uint8_t *p = buffer;
    while (length--) *p++ = 0;
}

fp_frame_status fp_frame_read(const uint8_t *data, size_t length, fp_frame *frame)
{
    uint64_t payload_length;
    size_t header = 2;
    unsigned i;
    if (!frame) return FP_FRAME_INVALID;
    memset(frame, 0, sizeof(*frame));
    if (!data && length) return FP_FRAME_INVALID;
    if (length < 2) return FP_FRAME_INCOMPLETE;
    if ((data[0] & 0x30) || (data[1] & 0x80)) return FP_FRAME_INVALID;
    frame->opcode = data[0] & 0x0f;
    frame->final = (data[0] & 0x80) != 0;
    frame->compressed = (data[0] & 0x40) != 0;
    if (frame->opcode != 0 && frame->opcode != 1 && frame->opcode != 2 &&
        frame->opcode != 8 && frame->opcode != 9 && frame->opcode != 10) return FP_FRAME_INVALID;
    payload_length = data[1] & 0x7f;
    if (payload_length == 126) {
        if (length < 4) return FP_FRAME_INCOMPLETE;
        payload_length = ((uint64_t)data[2] << 8) | data[3];
        if (payload_length < 126) return FP_FRAME_INVALID;
        header = 4;
    } else if (payload_length == 127) {
        if (length < 10) return FP_FRAME_INCOMPLETE;
        if (data[2] & 0x80) return FP_FRAME_INVALID;
        payload_length = 0;
        for (i = 2; i < 10; i++) payload_length = (payload_length << 8) | data[i];
        if (payload_length < 65536) return FP_FRAME_INVALID;
        header = 10;
    }
    if (payload_length > FP_FRAME_LIMIT) return FP_FRAME_LIMIT_EXCEEDED;
    if (frame->opcode >= 8 && (!frame->final || frame->compressed || payload_length > 125)) return FP_FRAME_INVALID;
    if (length - header < payload_length) return FP_FRAME_INCOMPLETE;
    frame->payload = data + header;
    frame->payload_length = (size_t)payload_length;
    frame->consumed = header + (size_t)payload_length;
    return FP_FRAME_OK;
}

fp_frame_status fp_frame_encode(const uint8_t *payload, size_t length, uint8_t opcode,
                                int final, uint8_t *output, size_t capacity, size_t *written)
{
    z_stream stream;
    uint8_t *compressed;
    uLong bound;
    size_t body, header, i;
    int result;
    if (written) *written = 0;
    if (!written || !output || (!payload && length) || (opcode != 0 && opcode != 1)) return FP_FRAME_INVALID;
    if (length > FP_FRAME_LIMIT) return FP_FRAME_LIMIT_EXCEEDED;
    bound = compressBound((uLong)length);
    compressed = (uint8_t *)malloc((size_t)bound);
    if (!compressed) return FP_FRAME_LIMIT_EXCEEDED;
    memset(&stream, 0, sizeof(stream));
    if (deflateInit2(&stream, 6, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY) != Z_OK) { clear_buffer(compressed, (size_t)bound); free(compressed); return FP_FRAME_COMPRESSION_ERROR; }
    stream.next_in = (Bytef *)payload;
    stream.avail_in = (uInt)length;
    stream.next_out = compressed;
    stream.avail_out = (uInt)bound;
    result = deflate(&stream, Z_FINISH);
    body = stream.total_out;
    deflateEnd(&stream);
    if (result != Z_STREAM_END) { clear_buffer(compressed, (size_t)bound); free(compressed); return FP_FRAME_COMPRESSION_ERROR; }
    body += 4;
    header = body <= 125 ? 2 : body <= 65535 ? 4 : 10;
    if (body > FP_FRAME_LIMIT || capacity < header + body) { clear_buffer(compressed, (size_t)bound); free(compressed); return FP_FRAME_LIMIT_EXCEEDED; }
    output[0] = (uint8_t)(opcode | 0x40 | (final ? 0x80 : 0));
    if (header == 2) output[1] = (uint8_t)body;
    else if (header == 4) { output[1] = 126; output[2] = (uint8_t)(body >> 8); output[3] = (uint8_t)body; }
    else { output[1] = 127; for (i = 0; i < 8; i++) output[2 + i] = (uint8_t)((uint64_t)body >> (56 - i * 8)); }
    for (i = 0; i < 4; i++) output[header + i] = (uint8_t)(length >> (i * 8));
    memcpy(output + header + 4, compressed, body - 4);
    clear_buffer(compressed, (size_t)bound); free(compressed);
    *written = header + body;
    return FP_FRAME_OK;
}

fp_frame_status fp_frame_inflate(const fp_frame *frame, uint8_t *output, size_t capacity, size_t *written)
{
    z_stream stream;
    uint32_t expected;
    int result, complete = 0;
    if (written) *written = 0;
    if (!frame || !written || !output || !frame->compressed || !frame->payload || frame->payload_length < 4) return FP_FRAME_INVALID;
    expected = (uint32_t)frame->payload[0] | ((uint32_t)frame->payload[1] << 8) |
               ((uint32_t)frame->payload[2] << 16) | ((uint32_t)frame->payload[3] << 24);
    if (expected > FP_FRAME_LIMIT || expected > capacity || capacity > UINT_MAX) return FP_FRAME_LIMIT_EXCEEDED;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, -15) != Z_OK) return FP_FRAME_COMPRESSION_ERROR;
    stream.next_in = (Bytef *)(frame->payload + 4);
    stream.avail_in = (uInt)(frame->payload_length - 4);
    stream.next_out = output;
    stream.avail_out = (uInt)capacity;
    result = inflate(&stream, Z_SYNC_FLUSH);
    if (result == Z_STREAM_END) complete = 1;
    if (result == Z_OK && stream.avail_in == 0) {
        static const uint8_t tail[] = {0x00, 0x00, 0xff, 0xff};
        uint8_t extra;
        stream.next_in = (Bytef *)tail;
        stream.avail_in = sizeof(tail);
        if (stream.avail_out == 0) {
            stream.next_out = &extra;
            stream.avail_out = 1;
        }
        result = inflate(&stream, Z_SYNC_FLUSH);
        complete = result == Z_OK && (stream.data_type & 128) != 0;
    }
    *written = stream.total_out;
    if (!complete || *written != expected || stream.avail_in != 0) {
        *written = 0;
        inflateEnd(&stream);
        return FP_FRAME_COMPRESSION_ERROR;
    }
    inflateEnd(&stream);
    return FP_FRAME_OK;
}
