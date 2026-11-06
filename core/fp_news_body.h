#ifndef FP_NEWS_BODY_H
#define FP_NEWS_BODY_H
#include "fp_news_article.h"

typedef struct {
    int32_t id;
    const char *url;
    uint16_t width, height;
} fp_news_attachment;

/* reads the bbcode of an sa reply and resolves its numbered pictures */
fp_article_status fp_news_body_parse(const char *source, size_t length, const fp_news_attachment *attachments, size_t attachment_count, fp_article *article);
#endif
