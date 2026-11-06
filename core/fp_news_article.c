#include "fp_news_article.h"
#include "fp_text.h"
#include "fp_bbcode.h"
#include <stdlib.h>
#include <string.h>

#define TAG_MAX 8192u
#define ATTR_MAX 1024u
#define LINE_MARK '\001'

typedef struct {
    const uint8_t *html;
    size_t length, pos, end;
    fp_article *article;
    size_t text_cap;
    /* the text being collected, entities not yet resolved, runs of white space already one space and a line break already LINE_MARK */
    char *raw;
    size_t raw_length;
    int collecting;
    fp_article_kind kind;
    int quote_depth;
    int skip_div_depth;
    int partial;
} reader;

typedef struct {
    char name[16];
    int closing;
    size_t end;     /* the offset of the byte after the closing > */
    const uint8_t *attrs;
    size_t attrs_length;
} tag;

static int lower(int c) { return c >= 'A' && c <= 'Z' ? c + 32 : c; }

static int is_space(int c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f'; }

/* the tag at html[pos] == '<'; 0 when it does not close within the bound */
static int read_tag(const reader *r, size_t pos, tag *t)
{
    size_t i = pos + 1, n = 0, stop = r->end < pos + TAG_MAX ? r->end : pos + TAG_MAX;
    int quote = 0;
    memset(t, 0, sizeof(*t));
    if (i < stop && r->html[i] == '/') { t->closing = 1; i++; }
    while (i < stop && ((r->html[i] >= 'a' && r->html[i] <= 'z') || (r->html[i] >= 'A' && r->html[i] <= 'Z') || (r->html[i] >= '0' && r->html[i] <= '9'))) {
        if (n + 1 < sizeof(t->name)) t->name[n++] = (char)lower(r->html[i]);
        i++;
    }
    t->name[n] = 0;
    t->attrs = r->html + i;
    while (i < stop) {
        uint8_t c = r->html[i];
        if (quote) { if (c == quote) quote = 0; }
        else if (c == '"' || c == '\'') quote = c;
        else if (c == '>') break;
        i++;
    }
    if (i >= stop || r->html[i] != '>') return 0;
    t->attrs_length = (size_t)(r->html + i - t->attrs);
    t->end = i + 1;
    return n > 0;
}

static int name_is(const uint8_t *bytes, size_t length, const char *name)
{
    size_t i;
    if (strlen(name) != length) return 0;
    for (i = 0; i < length; i++) if (lower(bytes[i]) != name[i]) return 0;
    return 1;
}

/* the value of an attribute, copied into out (zero terminated); 0 when it is missing or does not fit; an attribute without a value reads as empty */
static int attribute(const tag *t, const char *name, char *out, size_t cap)
{
    size_t i = 0;
    while (i < t->attrs_length) {
        size_t start, n, vstart = 0, vend = 0;
        int quote = 0, has_value = 0;
        while (i < t->attrs_length && (is_space(t->attrs[i]) || t->attrs[i] == '/')) i++;
        start = i;
        while (i < t->attrs_length && !is_space(t->attrs[i]) && t->attrs[i] != '=' && t->attrs[i] != '/') i++;
        n = i - start;
        if (n == 0) { i++; continue; }
        while (i < t->attrs_length && is_space(t->attrs[i])) i++;
        if (i < t->attrs_length && t->attrs[i] == '=') {
            has_value = 1;
            i++;
            while (i < t->attrs_length && is_space(t->attrs[i])) i++;
            if (i < t->attrs_length && (t->attrs[i] == '"' || t->attrs[i] == '\'')) quote = t->attrs[i++];
            vstart = i;
            while (i < t->attrs_length && (quote ? t->attrs[i] != quote : !is_space(t->attrs[i]))) i++;
            vend = i;
            if (quote && i < t->attrs_length) i++;
        }
        if (!name_is(t->attrs + start, n, name)) continue;
        if (!has_value) vstart = vend = 0;
        if (vend - vstart >= cap) return 0;
        memcpy(out, t->attrs + vstart, vend - vstart);
        out[vend - vstart] = 0;
        return 1;
    }
    return 0;
}

static int has_class(const tag *t, const char *word)
{
    char value[ATTR_MAX];
    size_t len = strlen(word);
    const char *p;
    if (!attribute(t, "class", value, sizeof(value))) return 0;
    for (p = value; (p = strstr(p, word)) != NULL; p += len) {
        int before = p == value || p[-1] == ' ';
        int after = p[len] == 0 || p[len] == ' ';
        if (before && after) return 1;
    }
    return 0;
}

static int has_class_prefix(const tag *t, const char *prefix)
{
    char value[ATTR_MAX];
    return attribute(t, "class", value, sizeof(value)) && strstr(value, prefix) != NULL;
}

static int block_room(reader *r, size_t text_bytes)
{
    if (r->article->count >= FP_ARTICLE_BLOCK_MAX || r->article->text_length + text_bytes + 1 > r->text_cap) { r->partial = 1; return 0; }
    return 1;
}

static void add_block(reader *r, fp_article_kind kind, const char *text, size_t length, unsigned width, unsigned height)
{
    fp_article_block *b;
    if (!block_room(r, length)) return;
    b = &r->article->blocks[r->article->count++];
    b->kind = (uint8_t)kind;
    b->width = (uint16_t)(width > 65535u ? 0 : width);
    b->height = (uint16_t)(height > 65535u ? 0 : height);
    b->offset = (uint32_t)r->article->text_length;
    b->length = (uint32_t)length;
    memcpy(r->article->text + r->article->text_length, text, length);
    r->article->text_length += length;
    r->article->text[r->article->text_length++] = 0;
}

/* a no-break space is a space, and the spaces around a line break and at the ends of the text go */
static size_t tidy(char *text, size_t length)
{
    size_t in = 0, out = 0;
    while (in < length) {
        if ((uint8_t)text[in] == 0xC2 && in + 1 < length && (uint8_t)text[in + 1] == 0xA0) { text[out++] = ' '; in += 2; }
        else text[out++] = text[in++];
    }
    length = out;
    in = out = 0;
    while (in < length) {
        char c = text[in++];
        if (c == ' ' && (out == 0 || text[out - 1] == ' ' || text[out - 1] == '\n')) continue;
        if (c == LINE_MARK) {
            while (out > 0 && text[out - 1] == ' ') out--;
            if (out == 0 || text[out - 1] == '\n') continue;
            text[out++] = '\n';
            continue;
        }
        text[out++] = c;
    }
    while (out > 0 && (text[out - 1] == ' ' || text[out - 1] == '\n')) out--;
    text[out] = 0;
    return out;
}

static void flush_text(reader *r)
{
    char *decoded;
    size_t n;
    if (!r->collecting) return;
    r->collecting = 0;
    if (r->raw_length == 0) return;
    decoded = (char *)malloc(r->raw_length + 1);
    if (!decoded) { r->partial = 1; r->raw_length = 0; return; }
    n = fp_text_unescape_entities(r->raw, r->raw_length, decoded, r->raw_length + 1);
    r->raw_length = 0;
    n = fp_bb_strip(decoded, n, decoded, n + 1);
    n = tidy(decoded, n);
    if (n > 0) add_block(r, r->kind, decoded, n, 0, 0);
    free(decoded);
}

static void start_text(reader *r, fp_article_kind kind)
{
    flush_text(r);
    r->collecting = 1;
    r->kind = kind;
    r->raw_length = 0;
}

static void add_raw(reader *r, const char *bytes, size_t n)
{
    size_t i;
    if (!r->collecting) return;
    for (i = 0; i < n; i++) {
        char c = bytes[i];
        if (r->raw_length + 1 >= r->text_cap) { r->partial = 1; return; }
        if (is_space((uint8_t)c)) {
            if (r->raw_length && r->raw[r->raw_length - 1] == ' ') continue;
            c = ' ';
        }
        r->raw[r->raw_length++] = c;
    }
}

static void add_image(reader *r, const tag *t)
{
    char src[FP_ARTICLE_URL_MAX], size[16];
    unsigned width = 0, height = 0;
    char url[FP_ARTICLE_URL_MAX + 8];
    if (!attribute(t, "src", src, sizeof(src)) || !src[0]) return;
    if (attribute(t, "width", size, sizeof(size))) width = (unsigned)strtoul(size, NULL, 10);
    if (attribute(t, "height", size, sizeof(size))) height = (unsigned)strtoul(size, NULL, 10);
    /* the small pictures are the emoticons of the text, not the pictures of the story */
    if ((width && width < 64) || (height && height < 64)) return;
    if (src[0] == '/' && src[1] == '/') { strcpy(url, "https:"); strcat(url, src); }
    else strcpy(url, src);
    flush_text(r);
    add_block(r, FP_ARTICLE_IMAGE, url, strlen(url), width, height);
}

static void add_video(reader *r, const tag *t)
{
    char href[FP_ARTICLE_URL_MAX];
    if (!attribute(t, "href", href, sizeof(href))) return;
    if (strncmp(href, "https://www.youtube.com/watch?v=", 32) != 0 && strncmp(href, "https://youtu.be/", 17) != 0) return;
    flush_text(r);
    add_block(r, FP_ARTICLE_VIDEO, href, strlen(href), 0, 0);
}

/* the contents of a script, a style or a drawing are skipped as a whole */
static size_t skip_until_close(const reader *r, size_t from, const char *name)
{
    size_t i = from, n = strlen(name);
    while (i + n + 3 <= r->end) {
        if (r->html[i] == '<' && r->html[i + 1] == '/') {
            size_t k;
            for (k = 0; k < n && lower(r->html[i + 2 + k]) == name[k]; k++);
            if (k == n) return i;
        }
        i++;
    }
    return r->end;
}

static void handle_tag(reader *r, const tag *t)
{
    const char *n = t->name;
    if (r->skip_div_depth) {
        if (strcmp(n, "div") == 0) r->skip_div_depth += t->closing ? -1 : 1;
        return;
    }
    if (strcmp(n, "div") == 0 && !t->closing && (has_class_prefix(t, "article-gallery-previews") || has_class_prefix(t, "article-gallery-arrow"))) {
        flush_text(r);
        r->skip_div_depth = 1;
        return;
    }
    if (strcmp(n, "p") == 0) {
        if (t->closing) flush_text(r);
        else start_text(r, r->quote_depth ? FP_ARTICLE_QUOTE : FP_ARTICLE_PARAGRAPH);
    } else if (n[0] == 'h' && n[1] >= '2' && n[1] <= '4' && n[2] == 0) {
        if (t->closing) flush_text(r);
        else start_text(r, FP_ARTICLE_HEADING);
    } else if (strcmp(n, "li") == 0) {
        if (t->closing) flush_text(r);
        else start_text(r, FP_ARTICLE_ITEM);
    } else if (strcmp(n, "dt") == 0) {
        if (t->closing) flush_text(r);
        else start_text(r, FP_ARTICLE_HEADING);
    } else if (strcmp(n, "dd") == 0) {
        if (t->closing) flush_text(r);
        else start_text(r, r->quote_depth ? FP_ARTICLE_QUOTE : FP_ARTICLE_PARAGRAPH);
    } else if (strcmp(n, "blockquote") == 0) {
        if (t->closing) { flush_text(r); if (r->quote_depth) r->quote_depth--; }
        else { start_text(r, FP_ARTICLE_QUOTE); r->quote_depth++; }
    } else if (strcmp(n, "br") == 0) {
        char mark = LINE_MARK;
        add_raw(r, &mark, 1);
    } else if (strcmp(n, "img") == 0 && !t->closing) {
        add_image(r, t);
    } else if (strcmp(n, "a") == 0 && !t->closing && has_class(t, "yt-p-overlay")) {
        add_video(r, t);
    }
}

fp_article_status fp_article_parse(const uint8_t *html, size_t length, fp_article *article)
{
    static const char start_marker[] = "<div class=\"article\">";
    static const char end_marker[] = "<div class=\"article-footer\"";
    reader r;
    size_t i, found = (size_t)-1, footer = (size_t)-1;
    fp_article_status status;
    if (article) memset(article, 0, sizeof(*article));
    if (!html || !article) return FP_ARTICLE_ARGUMENT;
    for (i = 0; i + sizeof(start_marker) - 1 <= length; i++) {
        if (html[i] == '<' && memcmp(html + i, start_marker, sizeof(start_marker) - 1) == 0) { found = i; break; }
    }
    if (found == (size_t)-1) return FP_ARTICLE_NOTFOUND;
    for (i = found; i + sizeof(end_marker) - 1 <= length; i++) {
        if (html[i] == '<' && memcmp(html + i, end_marker, sizeof(end_marker) - 1) == 0) { footer = i; break; }
    }
    memset(&r, 0, sizeof(r));
    r.html = html;
    r.length = length;
    r.pos = found + sizeof(start_marker) - 1;
    r.end = footer == (size_t)-1 ? length : footer;
    r.article = article;
    r.text_cap = FP_ARTICLE_TEXT_MAX;
    article->text = (char *)malloc(r.text_cap);
    r.raw = (char *)malloc(r.text_cap);
    if (!article->text || !r.raw) { free(article->text); free(r.raw); memset(article, 0, sizeof(*article)); return FP_ARTICLE_MEMORY; }
    r.partial = footer == (size_t)-1;
    while (r.pos < r.end) {
        if (html[r.pos] == '<') {
            tag t;
            if (r.pos + 3 < r.end && memcmp(html + r.pos, "<!--", 4) == 0) {
                size_t k = r.pos + 4;
                while (k + 2 < r.end && memcmp(html + k, "-->", 3) != 0) k++;
                r.pos = k + 3 > r.end ? r.end : k + 3;
                continue;
            }
            if (!read_tag(&r, r.pos, &t)) { add_raw(&r, "<", 1); r.pos++; continue; }
            r.pos = t.end;
            if (!t.closing && (strcmp(t.name, "script") == 0 || strcmp(t.name, "style") == 0 || strcmp(t.name, "svg") == 0 || strcmp(t.name, "iframe") == 0)) {
                r.pos = skip_until_close(&r, r.pos, t.name);
                continue;
            }
            handle_tag(&r, &t);
        } else if (r.skip_div_depth) {
            r.pos++;
        } else {
            size_t k = r.pos;
            while (k < r.end && html[k] != '<') k++;
            add_raw(&r, (const char *)html + r.pos, k - r.pos);
            r.pos = k;
        }
    }
    flush_text(&r);
    free(r.raw);
    status = r.partial ? FP_ARTICLE_PARTIAL : FP_ARTICLE_OK;
    if (article->count == 0) { fp_article_free(article); return FP_ARTICLE_NOTFOUND; }
    return status;
}

void fp_article_free(fp_article *article)
{
    if (!article) return;
    free(article->text);
    memset(article, 0, sizeof(*article));
}

const char *fp_article_text(const fp_article *article, size_t block)
{
    if (!article || block >= article->count) return "";
    return article->text + article->blocks[block].offset;
}
