#include "fp_forum.h"
#include "fp_document.h"
#include <stdlib.h>
#include <string.h>

typedef struct {
    const uint8_t *data;
    fp_document_token *tokens;
    size_t *ends;
    size_t count;
} doc;

static fp_forum_status doc_open(doc *d, const uint8_t *reply, size_t length)
{
    size_t capacity, i;
    fp_document_status status;
    memset(d, 0, sizeof(*d));
    if (!reply || !length) return FP_FORUM_INVALID;
    capacity = length < FP_FORUM_TOKEN_LIMIT ? length : FP_FORUM_TOKEN_LIMIT;
    d->tokens = (fp_document_token *)malloc(capacity * sizeof(*d->tokens));
    d->ends = (size_t *)malloc(capacity * sizeof(*d->ends));
    if (!d->tokens || !d->ends) {
        free(d->tokens); free(d->ends);
        memset(d, 0, sizeof(*d));
        return FP_FORUM_MEMORY;
    }
    status = fp_document_parse(reply, length, d->tokens, capacity, &d->count);
    if (status != FP_DOCUMENT_OK) {
        free(d->tokens); free(d->ends);
        memset(d, 0, sizeof(*d));
        return status == FP_DOCUMENT_LIMIT ? FP_FORUM_LIMIT : FP_FORUM_INVALID;
    }
    d->data = reply;
    for (i = 0; i < d->count; i++) d->ends[i] = i + 1;
    /* children follow their parent, so one backward pass makes every subtree end final */
    for (i = d->count; i-- > 1;) {
        size_t parent = d->tokens[i].parent;
        if (parent != FP_DOCUMENT_NO_PARENT && d->ends[i] > d->ends[parent]) d->ends[parent] = d->ends[i];
    }
    return FP_FORUM_OK;
}

static void doc_close(doc *d)
{
    free(d->tokens);
    free(d->ends);
    memset(d, 0, sizeof(*d));
}

static int is_array(const doc *d, size_t i)
{
    return i < d->count && d->tokens[i].type == FP_DOCUMENT_ARRAY;
}

/* index of the k-th child of an array token, or the token count when it is missing */
static size_t child(const doc *d, size_t array, size_t k)
{
    size_t c;
    if (!is_array(d, array) || k >= d->tokens[array].children) return d->count;
    c = array + 1;
    while (k--) c = d->ends[c];
    return c;
}

static size_t child_count(const doc *d, size_t array)
{
    return is_array(d, array) ? d->tokens[array].children : 0;
}

static int read_int(const doc *d, size_t i, int64_t *value)
{
    const fp_document_token *t;
    size_t k;
    int negative = 0;
    int64_t v = 0;
    if (i >= d->count || d->tokens[i].type != FP_DOCUMENT_INTEGER) return 0;
    t = &d->tokens[i];
    k = t->offset;
    if (d->data[k] == '-') { negative = 1; k++; }
    for (; k < t->offset + t->length; k++) {
        if (v > (INT64_MAX - 9) / 10) return 0;
        v = v * 10 + (d->data[k] - '0');
    }
    *value = negative ? -v : v;
    return 1;
}

static int read_i32(const doc *d, size_t i, int32_t *value)
{
    int64_t v;
    if (!read_int(d, i, &v) || v < INT32_MIN || v > INT32_MAX) return 0;
    *value = (int32_t)v;
    return 1;
}

static int read_span(const doc *d, size_t i, fp_span *span)
{
    const fp_document_token *t;
    if (i >= d->count || d->tokens[i].type != FP_DOCUMENT_STRING) return 0;
    t = &d->tokens[i];
    span->data = d->data + t->offset + 1;
    span->length = t->length - 2;
    return 1;
}

/* the reply must carry status zero; the first data element is at child 2 */
static fp_forum_status check_reply(const doc *d)
{
    int64_t status;
    if (!is_array(d, 0) || child_count(d, 0) < 3) return FP_FORUM_INVALID;
    if (!read_int(d, child(d, 0, 1), &status)) return FP_FORUM_INVALID;
    return status == 0 ? FP_FORUM_OK : FP_FORUM_SERVER;
}

fp_forum_status fp_forum_parse_attachment_url(const uint8_t *reply, size_t length, fp_span *url)
{
    doc d;
    fp_forum_status status;
    if (!url) return FP_FORUM_INVALID;
    memset(url, 0, sizeof(*url));
    status = doc_open(&d, reply, length);
    if (status != FP_FORUM_OK) return status;
    status = check_reply(&d);
    if (status == FP_FORUM_OK && (!read_span(&d, child(&d, 0, 2), url) || !url->length))
        status = FP_FORUM_INVALID;
    doc_close(&d);
    return status;
}

int32_t fp_post_vote_score(int32_t vote_word)
{
    int64_t w = vote_word;
    return (int32_t)(w >= 0 ? w / 8 : -((-w + 7) / 8));
}

fp_forum_status fp_forum_parse_votes(const uint8_t *reply, size_t length, fp_vote_page *page)
{
    doc d;
    fp_forum_status status;
    size_t list, count, i;
    if (!page) return FP_FORUM_INVALID;
    memset(page, 0, sizeof(*page));
    status = doc_open(&d, reply, length);
    if (status != FP_FORUM_OK) return status;
    status = check_reply(&d);
    if (status != FP_FORUM_OK) goto done;
    list = child(&d, 0, 2);
    if (!is_array(&d, list)) { status = FP_FORUM_INVALID; goto done; }
    count = child_count(&d, list);
    if (count > FP_FORUM_VOTE_LIMIT) { status = FP_FORUM_LIMIT; goto done; }
    if (!count) goto done;
    page->entries = (fp_vote_entry *)calloc(count, sizeof(*page->entries));
    if (!page->entries) { status = FP_FORUM_MEMORY; goto done; }
    for (i = 0; i < count; i++) {
        size_t item = child(&d, list, i);
        fp_vote_entry *e = &page->entries[i];
        int32_t vote = 0;
        if (child_count(&d, item) < 4 || !read_int(&d, child(&d, item, 0), &e->time) || !read_i32(&d, child(&d, item, 1), &e->member) ||
            !read_span(&d, child(&d, item, 2), &e->name) || !read_i32(&d, child(&d, item, 3), &vote)) { status = FP_FORUM_INVALID; goto done; }
        e->value = vote > 0 ? 1 : -1;
    }
    page->count = count;
done:
    if (status != FP_FORUM_OK) fp_vote_page_free(page);
    doc_close(&d);
    return status;
}

void fp_vote_page_free(fp_vote_page *page)
{
    if (!page) return;
    free(page->entries);
    memset(page, 0, sizeof(*page));
}

static fp_forum_status read_entry(const doc *d, size_t item, int with_flags, fp_forum_entry *entry)
{
    size_t n = child_count(d, item);
    memset(entry, 0, sizeof(*entry));
    if (!is_array(d, item) || n < 2) return FP_FORUM_INVALID;
    if (!read_i32(d, child(d, item, 0), &entry->id) || !read_span(d, child(d, item, 1), &entry->title)) return FP_FORUM_INVALID;
    if (with_flags) {
        if (n < 3 || !read_i32(d, child(d, item, 2), &entry->flags)) return FP_FORUM_INVALID;
        if (n > 3 && !read_span(d, child(d, item, 3), &entry->url)) return FP_FORUM_INVALID;
    }
    return FP_FORUM_OK;
}

static fp_forum_status read_entries(const doc *d, size_t array, int with_flags, fp_forum_entry **out, size_t *count)
{
    size_t n = child_count(d, array), i;
    fp_forum_entry *items;
    *out = NULL;
    *count = 0;
    if (!is_array(d, array)) return FP_FORUM_INVALID;
    if (n > FP_FORUM_ENTRY_LIMIT) return FP_FORUM_LIMIT;
    if (!n) return FP_FORUM_OK;
    items = (fp_forum_entry *)calloc(n, sizeof(*items));
    if (!items) return FP_FORUM_MEMORY;
    for (i = 0; i < n; i++) {
        fp_forum_status status = read_entry(d, child(d, array, i), with_flags, &items[i]);
        if (status != FP_FORUM_OK) { free(items); return status; }
    }
    *out = items;
    *count = n;
    return FP_FORUM_OK;
}

static fp_forum_status read_crumbs(const doc *d, size_t array, fp_forum_crumb *crumbs, size_t *count)
{
    size_t n = child_count(d, array), i;
    *count = 0;
    if (!is_array(d, array)) return FP_FORUM_INVALID;
    if (n > FP_FORUM_CRUMB_LIMIT) n = FP_FORUM_CRUMB_LIMIT;
    for (i = 0; i < n; i++) {
        size_t item = child(d, array, i);
        if (child_count(d, item) < 3 || !read_i32(d, child(d, item, 0), &crumbs[i].kind) ||
            !read_i32(d, child(d, item, 1), &crumbs[i].id) || !read_span(d, child(d, item, 2), &crumbs[i].title)) return FP_FORUM_INVALID;
    }
    *count = n;
    return FP_FORUM_OK;
}

fp_forum_status fp_forum_parse_index(const uint8_t *reply, size_t length, fp_forum_index *index)
{
    doc d;
    fp_forum_status status;
    if (!index) return FP_FORUM_INVALID;
    memset(index, 0, sizeof(*index));
    status = doc_open(&d, reply, length);
    if (status != FP_FORUM_OK) return status;
    status = check_reply(&d);
    if (status == FP_FORUM_OK) status = read_entries(&d, child(&d, 0, 2), 1, &index->entries, &index->count);
    doc_close(&d);
    return status;
}

/* entry of mf: kind, id, title, (unused), flags, then fields of the row the client draws; only these are read */
static fp_forum_status read_favorite(const doc *d, size_t item, fp_favorite_entry *entry)
{
    memset(entry, 0, sizeof(*entry));
    if (child_count(d, item) < 5) return FP_FORUM_INVALID;
    if (!read_i32(d, child(d, item, 0), &entry->kind) || !read_i32(d, child(d, item, 1), &entry->id) ||
        !read_span(d, child(d, item, 2), &entry->title) || !read_i32(d, child(d, item, 4), &entry->flags)) return FP_FORUM_INVALID;
    return FP_FORUM_OK;
}

fp_forum_status fp_forum_parse_favorites(const uint8_t *reply, size_t length, fp_favorites_page *page)
{
    doc d;
    fp_forum_status status;
    size_t list, n, i;
    if (!page) return FP_FORUM_INVALID;
    memset(page, 0, sizeof(*page));
    status = doc_open(&d, reply, length);
    if (status != FP_FORUM_OK) return status;
    status = check_reply(&d);
    if (status != FP_FORUM_OK) goto done;
    list = child(&d, 0, 3);
    if (child_count(&d, 0) < 4 || !read_int(&d, child(&d, 0, 2), &page->total) || page->total < 0 || !is_array(&d, list)) { status = FP_FORUM_INVALID; goto done; }
    n = child_count(&d, list);
    if (n > FP_FAVORITES_LIMIT) { status = FP_FORUM_LIMIT; goto done; }
    if (n) {
        page->entries = (fp_favorite_entry *)calloc(n, sizeof(*page->entries));
        if (!page->entries) { status = FP_FORUM_MEMORY; goto done; }
        for (i = 0; i < n; i++) {
            status = read_favorite(&d, child(&d, list, i), &page->entries[i]);
            if (status != FP_FORUM_OK) goto done;
        }
    }
    page->count = n;
done:
    doc_close(&d);
    if (status != FP_FORUM_OK) fp_favorites_page_free(page);
    return status;
}

void fp_favorites_page_free(fp_favorites_page *page)
{
    if (!page) return;
    free(page->entries);
    memset(page, 0, sizeof(*page));
}

static fp_forum_status read_topic_entry(const doc *d, size_t item, fp_topic_entry *topic)
{
    memset(topic, 0, sizeof(*topic));
    if (child_count(d, item) < 8) return FP_FORUM_INVALID;
    if (!read_i32(d, child(d, item, 0), &topic->id) || !read_span(d, child(d, item, 1), &topic->title) ||
        !read_span(d, child(d, item, 2), &topic->description) || !read_i32(d, child(d, item, 3), &topic->flags) ||
        !read_int(d, child(d, item, 4), &topic->posts) || !read_int(d, child(d, item, 5), &topic->date) ||
        !read_i32(d, child(d, item, 6), &topic->last_user_id) || !read_span(d, child(d, item, 7), &topic->last_user)) return FP_FORUM_INVALID;
    return FP_FORUM_OK;
}

fp_forum_status fp_forum_parse_page(const uint8_t *reply, size_t length, fp_forum_page *page)
{
    doc d;
    fp_forum_status status;
    size_t topics, n, i;
    fp_topic_entry *items = NULL;
    if (!page) return FP_FORUM_INVALID;
    memset(page, 0, sizeof(*page));
    status = doc_open(&d, reply, length);
    if (status != FP_FORUM_OK) return status;
    status = check_reply(&d);
    if (status != FP_FORUM_OK) goto done;
    /* data starts at child 2: crumbs, id, title, flags, rules, pinned, subforums, total, topics */
    if (child_count(&d, 0) < 11 ||
        !read_i32(&d, child(&d, 0, 3), &page->id) || !read_span(&d, child(&d, 0, 4), &page->title) ||
        !read_i32(&d, child(&d, 0, 5), &page->flags) || !read_int(&d, child(&d, 0, 9), &page->topic_total)) { status = FP_FORUM_INVALID; goto done; }
    status = read_crumbs(&d, child(&d, 0, 2), page->crumbs, &page->crumb_count);
    if (status != FP_FORUM_OK) goto done;
    status = read_entries(&d, child(&d, 0, 7), 0, &page->pinned, &page->pinned_count);
    if (status != FP_FORUM_OK) goto done;
    status = read_entries(&d, child(&d, 0, 8), 1, &page->subforums, &page->subforum_count);
    if (status != FP_FORUM_OK) goto done;
    topics = child(&d, 0, 10);
    n = child_count(&d, topics);
    if (!is_array(&d, topics)) { status = FP_FORUM_INVALID; goto done; }
    if (n > FP_FORUM_ENTRY_LIMIT) { status = FP_FORUM_LIMIT; goto done; }
    if (n) {
        items = (fp_topic_entry *)calloc(n, sizeof(*items));
        if (!items) { status = FP_FORUM_MEMORY; goto done; }
        for (i = 0; i < n; i++) {
            status = read_topic_entry(&d, child(&d, topics, i), &items[i]);
            if (status != FP_FORUM_OK) goto done;
        }
    }
    page->topics = items;
    page->topic_count = n;
    items = NULL;
done:
    free(items);
    doc_close(&d);
    if (status != FP_FORUM_OK) fp_forum_page_free(page);
    return status;
}

void fp_forum_index_free(fp_forum_index *index)
{
    if (!index) return;
    free(index->entries);
    memset(index, 0, sizeof(*index));
}

void fp_forum_page_free(fp_forum_page *page)
{
    if (!page) return;
    free(page->subforums);
    free(page->pinned);
    free(page->topics);
    memset(page, 0, sizeof(*page));
}

static fp_forum_status read_attachment(const doc *d, size_t item, fp_attachment *a)
{
    size_t n = child_count(d, item);
    memset(a, 0, sizeof(*a));
    if (n < 4) return FP_FORUM_INVALID;
    if (!read_i32(d, child(d, item, 0), &a->id) || !read_i32(d, child(d, item, 1), &a->kind) ||
        !read_span(d, child(d, item, 2), &a->name) || !read_int(d, child(d, item, 3), &a->size)) return FP_FORUM_INVALID;
    if (n >= 7) {
        if (!read_span(d, child(d, item, 4), &a->url) || !read_i32(d, child(d, item, 5), &a->width) ||
            !read_i32(d, child(d, item, 6), &a->height)) return FP_FORUM_INVALID;
    }
    return FP_FORUM_OK;
}

static fp_forum_status read_post(const doc *d, size_t item, fp_post *p, fp_attachment *attachments, size_t *attachment_used)
{
    size_t n = child_count(d, item), files, i, count;
    int32_t group = 0;
    memset(p, 0, sizeof(*p));
    if (n < 13) return FP_FORUM_INVALID;
    if (!read_i32(d, child(d, item, 0), &p->id) || !read_i32(d, child(d, item, 1), &p->flags) ||
        !read_i32(d, child(d, item, 2), &p->user_id) || !read_span(d, child(d, item, 3), &p->user_name) ||
        !read_i32(d, child(d, item, 4), &group) || !read_int(d, child(d, item, 5), &p->last_seen) ||
        !read_int(d, child(d, item, 6), &p->reputation) || !read_int(d, child(d, item, 7), &p->date) ||
        !read_span(d, child(d, item, 8), &p->body) || !read_span(d, child(d, item, 9), &p->avatar) ||
        !read_span(d, child(d, item, 10), &p->signature)) return FP_FORUM_INVALID;
    p->group = group;
    if (!read_i32(d, child(d, item, 12), &p->vote_word)) return FP_FORUM_INVALID;
    files = child(d, item, 11);
    if (!is_array(d, files)) return FP_FORUM_INVALID;
    count = child_count(d, files);
    if (count > FP_FORUM_ATTACHMENT_LIMIT - *attachment_used) return FP_FORUM_LIMIT;
    p->attachment_first = *attachment_used;
    for (i = 0; i < count; i++) {
        fp_forum_status status = read_attachment(d, child(d, files, i), &attachments[*attachment_used + i]);
        if (status != FP_FORUM_OK) return status;
    }
    p->attachment_count = count;
    *attachment_used += count;
    /* the edit trail is optional: date, editor name, reason, editor id */
    if (n >= 16 && child(d, item, 13) < d->count && d->tokens[child(d, item, 13)].type == FP_DOCUMENT_INTEGER) {
        if (!read_int(d, child(d, item, 13), &p->edit_date) || !read_span(d, child(d, item, 14), &p->editor) ||
            !read_span(d, child(d, item, 15), &p->edit_reason)) return FP_FORUM_INVALID;
    }
    return FP_FORUM_OK;
}

fp_forum_status fp_forum_parse_topic(const uint8_t *reply, size_t length, fp_topic_page *topic)
{
    doc d;
    fp_forum_status status;
    size_t posts, n, i, used = 0;
    if (!topic) return FP_FORUM_INVALID;
    memset(topic, 0, sizeof(*topic));
    status = doc_open(&d, reply, length);
    if (status != FP_FORUM_OK) return status;
    status = check_reply(&d);
    if (status != FP_FORUM_OK) goto done;
    /* data: crumbs, id, title, description, flags, created, author id, author, ?, curator, poll, total, posts */
    if (child_count(&d, 0) < 14 ||
        !read_i32(&d, child(&d, 0, 3), &topic->id) || !read_span(&d, child(&d, 0, 4), &topic->title) ||
        !read_span(&d, child(&d, 0, 5), &topic->description) || !read_i32(&d, child(&d, 0, 6), &topic->flags) ||
        !read_int(&d, child(&d, 0, 7), &topic->created) || !read_i32(&d, child(&d, 0, 8), &topic->author_id) ||
        !read_span(&d, child(&d, 0, 9), &topic->author) || !read_span(&d, child(&d, 0, 11), &topic->curator) ||
        !read_int(&d, child(&d, 0, 13), &topic->post_total)) { status = FP_FORUM_INVALID; goto done; }
    status = read_crumbs(&d, child(&d, 0, 2), topic->crumbs, &topic->crumb_count);
    if (status != FP_FORUM_OK) goto done;
    posts = child(&d, 0, 14);
    if (!is_array(&d, posts)) { status = FP_FORUM_INVALID; goto done; }
    n = child_count(&d, posts);
    if (n > FP_FORUM_POST_LIMIT) { status = FP_FORUM_LIMIT; goto done; }
    if (n) {
        topic->posts = (fp_post *)calloc(n, sizeof(*topic->posts));
        topic->attachments = (fp_attachment *)calloc(FP_FORUM_ATTACHMENT_LIMIT, sizeof(*topic->attachments));
        if (!topic->posts || !topic->attachments) { status = FP_FORUM_MEMORY; goto done; }
        for (i = 0; i < n; i++) {
            status = read_post(&d, child(&d, posts, i), &topic->posts[i], topic->attachments, &used);
            if (status != FP_FORUM_OK) goto done;
        }
    }
    topic->post_count = n;
    topic->attachment_count = used;
done:
    doc_close(&d);
    if (status != FP_FORUM_OK) fp_topic_page_free(topic);
    return status;
}

void fp_topic_page_free(fp_topic_page *topic)
{
    if (!topic) return;
    free(topic->posts);
    free(topic->attachments);
    memset(topic, 0, sizeof(*topic));
}
