#include "fp_forum.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t *load(const char *name, size_t *length)
{
    char path[256];
    FILE *file;
    uint8_t *data;
    long size;
    snprintf(path, sizeof(path), "tests/fixtures/%s", name);
    file = fopen(path, "rb");
    assert(file);
    assert(fseek(file, 0, SEEK_END) == 0);
    size = ftell(file);
    assert(size > 0 && fseek(file, 0, SEEK_SET) == 0);
    data = (uint8_t *)malloc((size_t)size);
    assert(data && fread(data, 1, (size_t)size, file) == (size_t)size);
    fclose(file);
    *length = (size_t)size;
    return data;
}

static int span_is(fp_span s, const char *expected)
{
    char out[256];
    size_t w;
    return fp_text_decode(s, out, sizeof(out), &w) == FP_TEXT_OK && strcmp(out, expected) == 0;
}

int main(void)
{
    size_t length, i;
    uint8_t *reply;
    fp_forum_index index;
    fp_forum_page page;
    fp_topic_page topic;
    size_t categories = 0;

    reply = load("index.reply", &length);
    assert(fp_forum_parse_index(reply, length, &index) == FP_FORUM_OK);
    assert(index.count > 10 && index.entries[0].id == 200 && (index.entries[0].flags & FP_FORUM_ENTRY_CATEGORY));
    assert(span_is(index.entries[0].title, "Административный") && span_is(index.entries[1].title, "4PDA - работа сайта"));
    for (i = 0; i < index.count; i++) if (index.entries[i].flags & FP_FORUM_ENTRY_CATEGORY) categories++;
    assert(categories >= 3);
    fp_forum_index_free(&index);
    assert(index.entries == NULL && index.count == 0);
    /* every truncation of a real reply is rejected without a crash */
    for (i = 0; i < length; i += 7) {
        assert(fp_forum_parse_index(reply, i, &index) != FP_FORUM_OK);
        assert(index.entries == NULL);
    }
    free(reply);

    reply = load("forum.reply", &length);
    assert(fp_forum_parse_page(reply, length, &page) == FP_FORUM_OK);
    assert(page.id == 139 && span_is(page.title, "iOS - Устройства") && page.crumb_count == 1 && page.crumbs[0].id == 295);
    assert(page.pinned_count == 3 && page.pinned[0].id == 238 && span_is(page.pinned[0].title, "Правила разделов Apple"));
    assert(page.subforum_count == 7 && page.subforums[0].id == 197 && page.subforums[3].url.length > 0 && page.subforums[0].url.length == 0);
    assert(page.topic_total == 83 && page.topic_count == 30);
    assert(page.topics[0].id == 272100 && span_is(page.topics[0].title, "iPhone 4S (2011) - Обсуждение"));
    assert(span_is(page.topics[0].last_user, "ffrosty") && page.topics[0].posts == 18000 && page.topics[0].date > 1700000000);
    assert(page.topics[0].flags & FP_TOPIC_UNREAD);
    fp_forum_page_free(&page);
    for (i = 0; i < length; i += 11) {
        assert(fp_forum_parse_page(reply, i, &page) != FP_FORUM_OK);
        assert(page.topics == NULL && page.subforums == NULL && page.pinned == NULL);
    }
    free(reply);

    reply = load("topic.reply", &length);
    assert(fp_forum_parse_topic(reply, length, &topic) == FP_FORUM_OK);
    assert(topic.id == 272100 && span_is(topic.title, "iPhone 4S (2011) - Обсуждение") && topic.crumb_count == 2);
    assert(span_is(topic.author, "Spangron") && topic.post_total == 17999 && topic.post_count == 3);
    assert(topic.posts[0].id == 9276375 && span_is(topic.posts[0].user_name, "Spangron") && topic.posts[0].user_id == 977453);
    assert(topic.posts[0].group == 8 && topic.posts[0].date == 1317824992 && topic.posts[0].body.length > 1000);
    assert(topic.posts[0].attachment_count == 9 && topic.posts[0].attachment_first == 0);
    assert(topic.attachments[0].id == 2407907 && topic.attachments[0].kind == 1 && topic.attachments[0].width == 500 && topic.attachments[0].height == 374);
    assert(span_is(topic.attachments[0].name, "85385313_1_644x461_iphone-4s-sankt-peterburg_rev001.jpg"));
    assert(topic.attachments[8].kind == 0 && topic.attachments[8].url.length == 0 && topic.attachments[8].size == 3694862);
    assert(topic.posts[0].edit_date == 1685447825 && span_is(topic.posts[0].editor, "КараванН"));
    assert((topic.posts[0].flags & FP_POST_HEADER) && !(topic.posts[1].flags & FP_POST_HEADER));
    assert(topic.posts[1].attachment_count == 0 && topic.posts[1].attachment_first == 9);
    fp_topic_page_free(&topic);
    for (i = 0; i < length; i += 97) {
        assert(fp_forum_parse_topic(reply, i, &topic) != FP_FORUM_OK);
        assert(topic.posts == NULL && topic.attachments == NULL);
    }
    free(reply);

    /* a nonzero status is a server answer, not a malformed document */
    assert(fp_forum_parse_page((const uint8_t *)"[2,4,\"denied\"]", 14, &page) == FP_FORUM_SERVER);
    assert(fp_forum_parse_topic((const uint8_t *)"[2,4,\"denied\"]", 14, &topic) == FP_FORUM_SERVER);
    assert(fp_forum_parse_index((const uint8_t *)"[2,0,[]]", 8, &index) == FP_FORUM_OK && index.count == 0 && index.entries == NULL);
    assert(fp_forum_parse_index((const uint8_t *)"[2,0,[[1,2]]]", 13, &index) == FP_FORUM_INVALID);
    assert(fp_forum_parse_index((const uint8_t *)"[2,0,[[1,\"a\",\"b\"]]]", 19, &index) == FP_FORUM_INVALID);
    assert(fp_forum_parse_index(NULL, 0, &index) == FP_FORUM_INVALID);
    /* the layout comes from the favorites screen of the original client (kind, id, title, ?, flags, last poster, date);
       no signed in reply has been captured, so the bytes are written by hand */
    {
        static const char favorites[] = "[2,0,3,[[0,139,\"iOS - Устройства\",0,1],[1,272100,\"iPhone 4S (2011) - Обсуждение\",0,0,0,0,0,\"ffrosty\",1700000000],[1,5,\"\",0,1]]]";
        fp_favorites_page fav;
        assert(fp_forum_parse_favorites((const uint8_t *)favorites, sizeof(favorites) - 1, &fav) == FP_FORUM_OK);
        assert(fav.total == 3 && fav.count == 3 && fav.entries[0].kind == FP_FAVORITE_FORUM && fav.entries[0].id == 139);
        assert(fav.entries[0].flags == FP_FAVORITE_PINNED && fav.entries[1].kind == FP_FAVORITE_TOPIC && fav.entries[1].id == 272100);
        assert(fav.entries[1].flags == 0 && fav.entries[2].title.length == 0);
        fp_favorites_page_free(&fav);
        assert(fav.entries == NULL && fav.count == 0);
        for (i = 0; i < sizeof(favorites) - 1; i++) {
            assert(fp_forum_parse_favorites((const uint8_t *)favorites, i, &fav) != FP_FORUM_OK);
            assert(fav.entries == NULL);
        }
        assert(fp_forum_parse_favorites((const uint8_t *)"[2,0,0,[]]", 10, &fav) == FP_FORUM_OK && fav.count == 0 && fav.entries == NULL);
        assert(fp_forum_parse_favorites((const uint8_t *)"[2,4,\"denied\"]", 14, &fav) == FP_FORUM_SERVER);
        assert(fp_forum_parse_favorites((const uint8_t *)"[2,0,-1,[]]", 11, &fav) == FP_FORUM_INVALID);
        assert(fp_forum_parse_favorites((const uint8_t *)"[2,0,1,[[1,2,\"a\"]]]", 20, &fav) == FP_FORUM_INVALID);
        assert(fp_forum_parse_favorites((const uint8_t *)"[2,0,1,[[1,2,3,0,0]]]", 21, &fav) == FP_FORUM_INVALID);
        assert(fp_forum_parse_favorites(NULL, 0, &fav) == FP_FORUM_INVALID);
    }
    {
        static const char reply[] = "[7,0,\"https://example.test/file\"]";
        fp_span url;
        assert(fp_forum_parse_attachment_url((const uint8_t *)reply, sizeof(reply) - 1, &url) == FP_FORUM_OK);
        assert(url.length == strlen("https://example.test/file"));
        assert(fp_forum_parse_attachment_url((const uint8_t *)"[7,0,1]", 7, &url) == FP_FORUM_INVALID);
        assert(fp_forum_parse_attachment_url((const uint8_t *)"[7,0,\"\"]", 8, &url) == FP_FORUM_INVALID);
        assert(fp_forum_parse_attachment_url((const uint8_t *)"[7,4,\"x\"]", 9, &url) == FP_FORUM_SERVER);
    }
    {
        static const char reply[] = "[9,0,[[1445000000,17,\"Ann\",1],[1445000100,18,\"Bob\",-1],[1445000200,19,\"Cy\",0]]]";
        fp_vote_page votes;
        assert(fp_forum_parse_votes((const uint8_t *)reply, sizeof(reply) - 1, &votes) == FP_FORUM_OK && votes.count == 3);
        assert(votes.entries[0].member == 17 && votes.entries[0].value == 1 && votes.entries[0].time == 1445000000 && span_is(votes.entries[0].name, "Ann"));
        assert(votes.entries[1].value == -1 && votes.entries[2].value == -1);
        fp_vote_page_free(&votes);
        assert(votes.entries == NULL && votes.count == 0);
        for (i = 0; i < sizeof(reply) - 1; i++) {
            assert(fp_forum_parse_votes((const uint8_t *)reply, i, &votes) != FP_FORUM_OK);
            assert(votes.entries == NULL && votes.count == 0);
        }
        assert(fp_forum_parse_votes((const uint8_t *)"[9,0,[]]", 8, &votes) == FP_FORUM_OK && votes.count == 0 && votes.entries == NULL);
        assert(fp_forum_parse_votes((const uint8_t *)"[9,4,[]]", 8, &votes) == FP_FORUM_SERVER);
        assert(fp_forum_parse_votes((const uint8_t *)"[9,0,[[1,2,\"a\"]]]", 18, &votes) == FP_FORUM_INVALID && votes.entries == NULL);
        assert(fp_forum_parse_votes((const uint8_t *)"[9,0,[[1,2,3,4]]]", 17, &votes) == FP_FORUM_INVALID);
        assert(fp_forum_parse_votes((const uint8_t *)"[9,0,5]", 7, &votes) == FP_FORUM_INVALID);
        assert(fp_forum_parse_votes(NULL, 0, &votes) == FP_FORUM_INVALID);
    }
    {
        /* a guest sees no vote word, and the score of a word is its upper bits rounded down */
        fp_topic_page page;
        size_t k;
        reply = load("topic.reply", &length);
        assert(fp_forum_parse_topic(reply, length, &page) == FP_FORUM_OK);
        for (k = 0; k < page.post_count; k++) assert(page.posts[k].vote_word == 0);
        fp_topic_page_free(&page);
        free(reply);
        assert(fp_post_vote_score(47) == 5 && fp_post_vote_score(1) == 0 && fp_post_vote_score(-23) == -3 && fp_post_vote_score(-8) == -1 && fp_post_vote_score(-1) == -1);
        assert(fp_post_vote_score(INT32_MIN) == -268435456);
    }
    puts("forum tests passed");
    return 0;
}
