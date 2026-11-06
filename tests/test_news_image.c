#include "fp_news_image.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static int image(const char *input, char *out, size_t capacity) { return fp_news_image_url((const uint8_t *)input, strlen(input), out, capacity); }
int main(void)
{
    char out[128];
    assert(image("<meta property=\"og:image\" content=\"https://4pda.to/s/a.jpg\">", out, sizeof(out)));
    assert(!strcmp(out, "https://4pda.to/s/a.jpg"));
    assert(image("<META content='https://4pda.to/s/b.png' PROPERTY='OG:IMAGE'/>", out, sizeof(out)));
    assert(!strcmp(out, "https://4pda.to/s/b.png"));
    assert(!image("<meta name='twitter:image' content='x'>", out, sizeof(out)));
    assert(!image("<meta property='og:image' content='long'>", out, 4));
    assert(!image("<meta property='og:image' content='broken", out, sizeof(out)));
    puts("news image tests passed");
    return 0;
}
