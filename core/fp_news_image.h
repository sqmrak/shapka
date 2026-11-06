#ifndef FP_NEWS_IMAGE_H
#define FP_NEWS_IMAGE_H
#include <stddef.h>
#include <stdint.h>
/* extracts the first og:image content from a bounded html document */
int fp_news_image_url(const uint8_t *data, size_t length, char *output, size_t capacity);
#endif
