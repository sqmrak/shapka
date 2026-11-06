#include "fp_frame.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    const uint8_t doc[] = "[1,\"ah\",\"1.9.43\"]";
    uint8_t encoded[1024], decoded[1024];
    size_t n, out, i;
    fp_frame frame;
    assert(fp_frame_encode(doc, sizeof(doc) - 1, 1, 1, encoded, sizeof(encoded), &n) == FP_FRAME_OK);
    for (i = 0; i < n; ++i) assert(fp_frame_read(encoded, i, &frame) == FP_FRAME_INCOMPLETE);
    assert(fp_frame_read(encoded, n, &frame) == FP_FRAME_OK);
    assert(frame.final && frame.opcode == 1 && frame.compressed && frame.consumed == n);
    assert(fp_frame_inflate(&frame, decoded, sizeof(decoded), &out) == FP_FRAME_OK);
    assert(out == sizeof(doc) - 1 && memcmp(doc, decoded, out) == 0);
    encoded[1] |= 0x80;
    assert(fp_frame_read(encoded, n, &frame) == FP_FRAME_INVALID);
    encoded[1] &= 0x7f;
    assert(fp_frame_read(encoded, n, &frame) == FP_FRAME_OK);
    encoded[2]++;
    assert(fp_frame_inflate(&frame, decoded, sizeof(decoded), &out) == FP_FRAME_COMPRESSION_ERROR);
    assert(out == 0);
    { const uint8_t bytes[] = {0x89, 0x01, 0x42};
      assert(fp_frame_read(bytes, sizeof(bytes), &frame) == FP_FRAME_OK);
      assert(frame.opcode == 9 && frame.payload_length == 1); }
    { const uint8_t bytes[] = {0x09, 0x00};
      assert(fp_frame_read(bytes, sizeof(bytes), &frame) == FP_FRAME_INVALID); }
    { const uint8_t bytes[] = {0x81, 126, 0, 1, 0};
      assert(fp_frame_read(bytes, sizeof(bytes), &frame) == FP_FRAME_INVALID); }
    { const uint8_t bytes[] = {0xc2, 44, 0x26, 0, 0, 0, 0x8a, 0x36, 0xd2, 0x31, 0xd0, 0x89, 0x8e, 0x36, 0xb2, 0x34, 0xd5, 0x51, 0x72, 0x2c, 0x28, 0xc8, 0x49, 0x55, 0xd2, 0x31, 0x34, 0x8b, 0xd5, 0x89, 0x36, 0x34, 0xb6, 0xd4, 0x51, 0xca, 0xf4, 0x0f, 0x56, 0xd2, 0x31, 0x88, 0x8d, 0x8d, 0x05, 0x00};
      const char *expected = "[2,0,[[295,\"Apple\",16],[139,\"iOS\",0]]]";
      assert(fp_frame_read(bytes, sizeof(bytes), &frame) == FP_FRAME_OK);
      assert(fp_frame_inflate(&frame, decoded, sizeof(decoded), &out) == FP_FRAME_OK);
      assert(out == strlen(expected) && memcmp(decoded, expected, out) == 0);
      for (i = 4; i < frame.payload_length; i++) {
          fp_frame truncated = frame;
          truncated.payload_length = i;
          assert(fp_frame_inflate(&truncated, decoded, sizeof(decoded), &out) != FP_FRAME_OK);
      } }
    puts("frame tests passed");
    return 0;
}
