#ifndef FP_NEWS_ARTICLE_H
#define FP_NEWS_ARTICLE_H

#include <stddef.h>
#include <stdint.h>

/* the body of a news page of 4pda.to as a flat list of blocks, read from the utf-8 text of the page; everything outside the article (the menu, the comments, the
   advertisements, the lists of other news) is left out */

#define FP_ARTICLE_BLOCK_MAX 600u
#define FP_ARTICLE_TEXT_MAX (256u * 1024u)
#define FP_ARTICLE_URL_MAX 512u

typedef enum {
    FP_ARTICLE_PARAGRAPH = 0,
    FP_ARTICLE_HEADING,
    FP_ARTICLE_ITEM,
    FP_ARTICLE_QUOTE,
    /* text is the address of the picture, width and height are the sizes the page gives or zero */
    FP_ARTICLE_IMAGE,
    /* text is the address of the video page */
    FP_ARTICLE_VIDEO
} fp_article_kind;

typedef enum {
    FP_ARTICLE_OK = 0,
    FP_ARTICLE_ARGUMENT,
    FP_ARTICLE_MEMORY,
    /* the page has no article block */
    FP_ARTICLE_NOTFOUND,
    /* the page ends, or a bound is reached, before the article does; the blocks read so far are valid */
    FP_ARTICLE_PARTIAL
} fp_article_status;

typedef struct {
    uint8_t kind;
    uint16_t width, height;
    uint32_t offset, length;
} fp_article_block;

typedef struct {
    fp_article_block blocks[FP_ARTICLE_BLOCK_MAX];
    size_t count;
    char *text;
    size_t text_length;
} fp_article;

/* OK and PARTIAL fill article, which the caller frees with fp_article_free; the other statuses leave it empty */
fp_article_status fp_article_parse(const uint8_t *html, size_t length, fp_article *article);
void fp_article_free(fp_article *article);

/* the text of a block, zero terminated, valid until the article is freed */
const char *fp_article_text(const fp_article *article, size_t block);

#endif
