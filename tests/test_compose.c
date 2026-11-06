#include "fp_compose.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    uint8_t out[256];
    size_t n, i;
    static const uint8_t body[] = {'a', '"', '\n', 0xcf};
    static const char reply[] = "[42,0,0,\"a\\\"\\u000a\xcf\",[]]";
    static const char message[] = "[0,\"a\\\"\\u000a\xcf\",[],17,\"topic\"]";
    assert(fp_compose_reply(42, body, sizeof(body), out, sizeof(out), &n) == FP_DOCUMENT_OK);
    assert(n == sizeof(reply) - 1 && memcmp(out, reply, n) == 0);
    for (i = 0; i < sizeof(reply) - 1; i++) {
        n = 123;
        assert(fp_compose_reply(42, body, sizeof(body), out, i, &n) == FP_DOCUMENT_LIMIT && n == 0);
    }
    assert(fp_compose_message(17, body, sizeof(body), (const uint8_t *)"topic", 5, out, sizeof(out), &n) == FP_DOCUMENT_OK);
    assert(n == sizeof(message) - 1 && memcmp(out, message, n) == 0);
    for (i = 0; i < sizeof(message) - 1; i++) {
        n = 123;
        assert(fp_compose_message(17, body, sizeof(body), (const uint8_t *)"topic", 5, out, i, &n) == FP_DOCUMENT_LIMIT && n == 0);
    }
    assert(fp_compose_message(0, body, sizeof(body), (const uint8_t *)"topic", 5, out, sizeof(out), &n) == FP_DOCUMENT_INVALID);
    assert(fp_compose_reply(42, body, 0, out, sizeof(out), &n) == FP_DOCUMENT_INVALID);
    assert(fp_compose_qms_reply(17, (const uint8_t *)"hi", 2, out, sizeof(out), &n) == FP_DOCUMENT_OK);
    assert(n == strlen("[17,\"hi\",[]]") && memcmp(out, "[17,\"hi\",[]]", n) == 0);
    for (i = 0; i < n; i++) {
        size_t written = 123;
        assert(fp_compose_qms_reply(17, (const uint8_t *)"hi", 2, out, i, &written) == FP_DOCUMENT_LIMIT && written == 0);
    }
    assert(fp_compose_post_vote(9427530, 2, out, sizeof(out), &n) == FP_DOCUMENT_OK && n == strlen("[9427530,2]") && !memcmp(out, "[9427530,2]", n));
    assert(fp_compose_post_vote(5, 0, out, sizeof(out), &n) == FP_DOCUMENT_OK && !memcmp(out, "[5,0]", n));
    assert(fp_compose_post_vote(5, 3, out, sizeof(out), &n) == FP_DOCUMENT_INVALID && n == 0);
    assert(fp_compose_post_vote(0, 1, out, sizeof(out), &n) == FP_DOCUMENT_INVALID);
    for (i = 0; i < strlen("[5,1]"); i++) assert(fp_compose_post_vote(5, 1, out, i, &n) == FP_DOCUMENT_LIMIT && n == 0);
    assert(fp_compose_karma(17, 1, 99, body, sizeof(body), out, sizeof(out), &n) == FP_DOCUMENT_OK);
    assert(n == strlen("[17,1,99,\"a\\\"\\u000a\xcf\"]") && !memcmp(out, "[17,1,99,\"a\\\"\\u000a\xcf\"]", n));
    assert(fp_compose_karma(17, 0, 99, (const uint8_t *)"x", 1, out, sizeof(out), &n) == FP_DOCUMENT_OK && !memcmp(out, "[17,0,99,\"x\"]", n));
    assert(fp_compose_karma(17, 1, 99, (const uint8_t *)"x", 0, out, sizeof(out), &n) == FP_DOCUMENT_INVALID);
    assert(fp_compose_karma(0, 1, 99, (const uint8_t *)"x", 1, out, sizeof(out), &n) == FP_DOCUMENT_INVALID);
    assert(fp_compose_karma(17, 1, 0, (const uint8_t *)"x", 1, out, sizeof(out), &n) == FP_DOCUMENT_INVALID);
    for (i = 0; i < strlen("[17,1,99,\"x\"]"); i++) assert(fp_compose_karma(17, 1, 99, (const uint8_t *)"x", 1, out, i, &n) == FP_DOCUMENT_LIMIT && n == 0);
    assert(!fp_compose_karma_refusal(3) && !fp_compose_karma_refusal(14) && fp_compose_karma_refusal(4) && fp_compose_karma_refusal(13));
    assert(strstr(fp_compose_karma_refusal(5), "самому себе"));
    puts("compose tests passed");
    return 0;
}
