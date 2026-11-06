#include "fp_news_body.h"
#include "fp_bbcode.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static int add(fp_article *article, fp_article_kind kind, const char *text, size_t length, unsigned width, unsigned height)
{
    fp_article_block *block;
    if (!length) return 1;
    if (article->count >= FP_ARTICLE_BLOCK_MAX || length + 1 > FP_ARTICLE_TEXT_MAX - article->text_length) return 0;
    block = &article->blocks[article->count++];
    block->kind = (uint8_t)kind;
    block->offset = (uint32_t)article->text_length;
    block->length = (uint32_t)length;
    block->width = (uint16_t)width;
    block->height = (uint16_t)height;
    memcpy(article->text + article->text_length, text, length);
    article->text_length += length;
    article->text[article->text_length++] = 0;
    return 1;
}

static int flush(fp_article *article, char *text, size_t *used)
{
    size_t start = 0, end = *used;
    while (start < end && (text[start] == ' ' || text[start] == '\r' || text[start] == '\n' || text[start] == '\t')) start++;
    while (end > start && (text[end - 1] == ' ' || text[end - 1] == '\r' || text[end - 1] == '\n' || text[end - 1] == '\t')) end--;
    *used = 0;
    return add(article, FP_ARTICLE_PARAGRAPH, text + start, end - start, 0, 0);
}

static size_t youtube_tag(const char *text, size_t length, char *url, size_t capacity)
{
    static const char prefix[] = "[youtube=";
    size_t i, end;
    if (length < sizeof(prefix) - 1 + 11 + 1 || memcmp(text, prefix, sizeof(prefix) - 1)) return 0;
    for (i = 0; i < 11; i++) {
        char c = text[sizeof(prefix) - 1 + i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '_')) return 0;
    }
    end = sizeof(prefix) - 1 + 11;
    if (text[end] != ':' && text[end] != ']') return 0;
    while (end < length && end < 128 && text[end] != ']') {
        if (text[end] != ':' && (text[end] < '0' || text[end] > '9')) return 0;
        end++;
    }
    if (end >= length || end >= 128 || text[end] != ']') return 0;
    if (snprintf(url, capacity, "https://www.youtube.com/watch?v=%.*s", 11, text + sizeof(prefix) - 1) >= (int)capacity) return 0;
    return end + 1;
}

fp_article_status fp_news_body_parse(const char *source, size_t length, const fp_news_attachment *attachments, size_t attachment_count, fp_article *article)
{
    fp_bb_node *nodes = NULL;
    char *text = NULL;
    size_t count = 0, used = 0, i;
    int incomplete = 0;
    fp_article_status result = FP_ARTICLE_ARGUMENT;
    if (!article) return FP_ARTICLE_ARGUMENT;
    memset(article, 0, sizeof(*article));
    if (!source || !length || length > FP_BB_SOURCE_LIMIT || attachment_count > 256 || (attachment_count && !attachments)) return FP_ARTICLE_ARGUMENT;
    nodes = malloc((length + 33u) * sizeof(*nodes));
    text = malloc(length + 1);
    article->text = malloc(FP_ARTICLE_TEXT_MAX);
    if (!nodes || !text || !article->text) { result = FP_ARTICLE_MEMORY; goto done; }
    if (fp_bb_parse(source, length, nodes, length + 33u, &count) != FP_BB_OK) { result = FP_ARTICLE_ARGUMENT; goto done; }
    for (i = 0; i < count; i++) {
        fp_bb_node node = nodes[i];
        if (node.kind == FP_BB_TEXT) {
            size_t j;
            for (j = 0; j < node.length; j++) {
                char c = source[node.start + j];
                char url[64];
                size_t tag_length = c == '[' ? youtube_tag(source + node.start + j, node.length - j, url, sizeof(url)) : 0;
                if (tag_length) {
                    if (!flush(article, text, &used) || !add(article, FP_ARTICLE_VIDEO, url, strlen(url), 0, 0)) { result = FP_ARTICLE_PARTIAL; goto done; }
                    j += tag_length - 1;
                    continue;
                }
                if (c == '\n' && used && text[used - 1] == '\n') {
                    if (!flush(article, text, &used)) { result = FP_ARTICLE_PARTIAL; goto done; }
                } else text[used++] = c;
            }
        } else if (node.kind == FP_BB_OPEN && node.tag == FP_BB_ATTACHMENT) {
            size_t j = 0, k;
            int32_t id = 0;
            if (!flush(article, text, &used)) { result = FP_ARTICLE_PARTIAL; goto done; }
            while (j < node.length && source[node.start + j] >= '0' && source[node.start + j] <= '9') {
                int digit = source[node.start + j++] - '0';
                if (id > (INT32_MAX - digit) / 10) { id = 0; break; }
                id = id * 10 + digit;
            }
            for (k = 0; id && k < attachment_count; k++) {
                if (attachments[k].id == id && attachments[k].url) {
                    size_t n = strlen(attachments[k].url);
                    if (n > FP_ARTICLE_URL_MAX || !add(article, FP_ARTICLE_IMAGE, attachments[k].url, n, attachments[k].width, attachments[k].height)) { result = FP_ARTICLE_PARTIAL; goto done; }
                    break;
                }
            }
            if (!id || k == attachment_count) incomplete = 1;
        } else if (node.kind == FP_BB_OPEN && (node.tag == FP_BB_BREAK || node.tag == FP_BB_ITEM)) text[used++] = '\n';
    }
    if (!flush(article, text, &used)) result = FP_ARTICLE_PARTIAL;
    else result = article->count ? (incomplete ? FP_ARTICLE_PARTIAL : FP_ARTICLE_OK) : FP_ARTICLE_NOTFOUND;
done:
    free(nodes);
    free(text);
    if (result != FP_ARTICLE_OK && result != FP_ARTICLE_PARTIAL) fp_article_free(article);
    return result;
}
