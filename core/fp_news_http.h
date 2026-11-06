#ifndef FP_NEWS_HTTP_H
#define FP_NEWS_HTTP_H
#include <stddef.h>
#include <stdint.h>
#include "fp_session.h"

/* fetches a bounded path on 4pda.to using verified tls */
fp_session_status fp_news_get(const char *roots_path, const char *path, size_t limit, uint8_t **body, size_t *length, int *http_status);

/* the same, but only the first limit bytes of the body: the connection is closed after them, which is all an article needs to give its og:image */
fp_session_status fp_news_get_head(const char *roots_path, const char *path, size_t limit, uint8_t **body, size_t *length, int *http_status);

#endif
