#include "fp_webp.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static uint8_t *slurp(const char *path, size_t *length)
{
    FILE *f = fopen(path, "rb");
    uint8_t *data;
    long size;
    assert(f && !fseek(f, 0, SEEK_END));
    size = ftell(f);
    assert(size > 0 && !fseek(f, 0, SEEK_SET));
    data = malloc((size_t)size);
    assert(data && fread(data, 1, (size_t)size, f) == (size_t)size);
    fclose(f);
    *length = (size_t)size;
    return data;
}
int main(void)
{
    size_t length;
    uint8_t *data = slurp("tests/fixtures/news_image.webp", &length), *rgba = NULL;
    int w = -1, h = -1, nonzero = 0;
    assert(fp_webp_is_webp(data, length));
    assert(fp_webp_decode(data, length, 1024, &rgba, &w, &h) == FP_WEBP_OK);
    assert(w == 480 && h == 320 && rgba);
    for (size_t i = 0; i < (size_t)w * (size_t)h * 4u; i++) nonzero |= rgba[i] != 0;
    assert(nonzero);
    free(rgba);
    assert(fp_webp_decode(data, length, 240, &rgba, &w, &h) == FP_WEBP_OK);
    assert(w == 240 && h == 160);
    free(rgba);
    assert(fp_webp_decode(data, length, 100, &rgba, &w, &h) == FP_WEBP_OK);
    assert(w == 100 && h == 67);
    free(rgba);
    assert(fp_webp_decode(data, length / 2, 1024, &rgba, &w, &h) == FP_WEBP_MALFORMED && !rgba && !w && !h);
    assert(fp_webp_decode(data, 8, 1024, &rgba, &w, &h) == FP_WEBP_NOT_WEBP);
    assert(fp_webp_decode((const uint8_t *)"\xff\xd8\xff\xe0 jpeg header", 18, 1024, &rgba, &w, &h) == FP_WEBP_NOT_WEBP);
    assert(fp_webp_decode(data, length, 0, &rgba, &w, &h) == FP_WEBP_ARGUMENT);
    assert(fp_webp_decode(NULL, 0, 10, &rgba, &w, &h) == FP_WEBP_ARGUMENT);
    free(data);
    puts("webp tests passed");
    return 0;
}
