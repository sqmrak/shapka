#ifndef FP_FORUM_H
#define FP_FORUM_H

#include "fp_text.h"

/* typed views of the forum replies fi, fs and fr; every span points into the caller-owned reply, which must outlive the result */

#define FP_FORUM_TOKEN_LIMIT 32768u
#define FP_FORUM_CRUMB_LIMIT 16u
#define FP_FORUM_ENTRY_LIMIT 1024u
#define FP_FORUM_POST_LIMIT 128u
#define FP_FORUM_ATTACHMENT_LIMIT 1024u
#define FP_FAVORITES_LIMIT 1024u

typedef enum { FP_FORUM_OK = 0, FP_FORUM_INVALID, FP_FORUM_LIMIT, FP_FORUM_MEMORY, FP_FORUM_SERVER } fp_forum_status;

/* flags of forum index entries */
#define FP_FORUM_ENTRY_FAVORITE 8
#define FP_FORUM_ENTRY_CATEGORY 16
#define FP_FORUM_ENTRY_UNREAD 32

/* flags of topic entries */
#define FP_TOPIC_PINNED 1
#define FP_TOPIC_HIGHLIGHT 2
#define FP_TOPIC_CLOSED 4
#define FP_TOPIC_MOVED 16
#define FP_TOPIC_UNREAD 32

/* flags of posts: the first post of the topic repeats at the top of every page */
#define FP_POST_HEADER 2048

/* the vote word of a post: bit 0 the post carries a rating, bit 1 the member has voted, bit 2 the vote was a plus, the rest is the signed score */
#define FP_POST_VOTE_SHOWN 1
#define FP_POST_VOTE_DONE 2
#define FP_POST_VOTE_UP 4

/* the signed score of a vote word, rounded down like the shift of the original client */
int32_t fp_post_vote_score(int32_t vote_word);

/* kinds and flags of favorites entries: the list holds forums and topics, a pinned entry is listed first */
#define FP_FAVORITE_FORUM 0
#define FP_FAVORITE_TOPIC 1
#define FP_FAVORITE_PINNED 1

/* flags of a topic page */
#define FP_TOPIC_PAGE_FAVORITE 8
#define FP_TOPIC_PAGE_CAN_POST 64

typedef struct {
    int32_t id;
    fp_span title;
    int32_t flags;
    /* an external or search address, empty for a plain forum */
    fp_span url;
} fp_forum_entry;

typedef struct {
    int32_t kind;
    int32_t id;
    fp_span title;
} fp_forum_crumb;

typedef struct {
    int32_t id;
    fp_span title;
    fp_span description;
    int32_t flags;
    int64_t posts;
    int64_t date;
    int32_t last_user_id;
    fp_span last_user;
} fp_topic_entry;

typedef struct {
    int32_t id;
    /* 1 for an image, 0 for any other file */
    int32_t kind;
    fp_span name;
    int64_t size;
    fp_span url;
    int32_t width;
    int32_t height;
} fp_attachment;

typedef struct {
    int32_t id;
    int32_t flags;
    int32_t user_id;
    fp_span user_name;
    int32_t group;
    int64_t last_seen;
    int64_t reputation;
    int64_t date;
    fp_span body;
    fp_span avatar;
    fp_span signature;
    size_t attachment_first;
    size_t attachment_count;
    int64_t edit_date;
    fp_span editor;
    fp_span edit_reason;
    int32_t vote_word;
} fp_post;

typedef struct {
    fp_forum_entry *entries;
    size_t count;
} fp_forum_index;

typedef struct {
    int32_t kind;
    int32_t id;
    fp_span title;
    int32_t flags;
} fp_favorite_entry;

typedef struct {
    int64_t total;
    fp_favorite_entry *entries;
    size_t count;
} fp_favorites_page;

typedef struct {
    fp_forum_crumb crumbs[FP_FORUM_CRUMB_LIMIT];
    size_t crumb_count;
    int32_t id;
    fp_span title;
    int32_t flags;
    int64_t topic_total;
    fp_forum_entry *subforums;
    size_t subforum_count;
    fp_forum_entry *pinned;
    size_t pinned_count;
    fp_topic_entry *topics;
    size_t topic_count;
} fp_forum_page;

typedef struct {
    fp_forum_crumb crumbs[FP_FORUM_CRUMB_LIMIT];
    size_t crumb_count;
    int32_t id;
    fp_span title;
    fp_span description;
    int32_t flags;
    int64_t created;
    int32_t author_id;
    fp_span author;
    fp_span curator;
    int64_t post_total;
    fp_post *posts;
    size_t post_count;
    fp_attachment *attachments;
    size_t attachment_count;
} fp_topic_page;

/* a reply is the whole document [id, status, ...]; a nonzero status gives FP_FORUM_SERVER */
fp_forum_status fp_forum_parse_index(const uint8_t *reply, size_t length, fp_forum_index *index);
fp_forum_status fp_forum_parse_page(const uint8_t *reply, size_t length, fp_forum_page *page);
fp_forum_status fp_forum_parse_topic(const uint8_t *reply, size_t length, fp_topic_page *topic);
/* the reply of mf: total, then one entry per favorite of the requested window */
fp_forum_status fp_forum_parse_favorites(const uint8_t *reply, size_t length, fp_favorites_page *page);
/* the first data field of fa is the download url */
fp_forum_status fp_forum_parse_attachment_url(const uint8_t *reply, size_t length, fp_span *url);

#define FP_FORUM_VOTE_LIMIT 500u

typedef struct {
    int64_t time;
    int32_t member;
    fp_span name;
    /* +1 or -1 */
    int32_t value;
} fp_vote_entry;

typedef struct {
    fp_vote_entry *entries;
    size_t count;
} fp_vote_page;

/* the reply of fk with vote 0: the members who rated a post, each as [time, member id, name, vote]; names point into the reply */
fp_forum_status fp_forum_parse_votes(const uint8_t *reply, size_t length, fp_vote_page *page);
void fp_vote_page_free(fp_vote_page *page);

void fp_forum_index_free(fp_forum_index *index);
void fp_forum_page_free(fp_forum_page *page);
void fp_topic_page_free(fp_topic_page *topic);
void fp_favorites_page_free(fp_favorites_page *page);

#endif
