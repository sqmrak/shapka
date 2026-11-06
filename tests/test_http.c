#include "fp_http.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static fp_http_status parse(const char *input, int eof, fp_http_response *response, uint8_t *body, size_t capacity)
{
    return fp_http_parse_response((const uint8_t *)input, strlen(input), eof, response, body, capacity);
}

int main(void)
{
    uint8_t body[32];
    fp_http_response response;
    assert(parse("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello", 0, &response, body, sizeof(body)) == FP_HTTP_OK);
    assert(response.status == 200 && response.body_len == 5 && !memcmp(body, "hello", 5));
    assert(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n", 0, &response, body, sizeof(body)) == FP_HTTP_OK);
    assert(response.body_len == 5 && !memcmp(body, "hello", 5));
    assert(parse("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhel", 1, &response, body, sizeof(body)) == FP_HTTP_INCOMPLETE);
    {
        /* a chunked reply cut anywhere before its last empty line is not an answer, a connection that ended must not pass as whole */
        const char *whole = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n";
        char cut[128];
        size_t head = strlen("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"), i;
        for (i = head; i < strlen(whole); i++) {
            memcpy(cut, whole, i);
            cut[i] = 0;
            assert(parse(cut, 1, &response, body, sizeof(body)) == FP_HTTP_INCOMPLETE);
        }
    }
    assert(parse("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n", 1, &response, body, sizeof(body)) == FP_HTTP_INVALID);
    assert(parse("HTTP/1.1 200 OK\r\nContent-Length: 33\r\n\r\n", 1, &response, body, sizeof(body)) == FP_HTTP_LIMIT);
    assert(parse("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhelloXX", 1, &response, body, sizeof(body)) == FP_HTTP_INVALID);
    assert(parse("HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n\r\n", 1, &response, body, sizeof(body)) == FP_HTTP_INVALID);
    assert(parse("<html>portal</html>\r\n\r\n", 1, &response, body, sizeof(body)) == FP_HTTP_INVALID);
    {
        const char *cut = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n8\r\nwor";
        assert(fp_http_parse_prefix((const uint8_t *)cut, strlen(cut), &response, body, sizeof(body)) == FP_HTTP_OK);
        assert(response.status == 200 && response.body_len == 8 && !memcmp(body, "hellowor", 8));
        cut = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n8\r\nwor";
        assert(fp_http_parse_prefix((const uint8_t *)cut, strlen(cut), &response, body, 6) == FP_HTTP_OK);
        assert(response.body_len == 6 && !memcmp(body, "hellow", 6));
        cut = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n";
        assert(fp_http_parse_prefix((const uint8_t *)cut, strlen(cut), &response, body, sizeof(body)) == FP_HTTP_OK && response.body_len == 5);
        cut = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhelloXX";
        assert(fp_http_parse_prefix((const uint8_t *)cut, strlen(cut), &response, body, sizeof(body)) == FP_HTTP_INVALID);
        cut = "HTTP/1.1 200 OK\r\nContent-Length: 50\r\n\r\nhel";
        assert(fp_http_parse_prefix((const uint8_t *)cut, strlen(cut), &response, body, sizeof(body)) == FP_HTTP_OK && response.body_len == 3);
        cut = "HTTP/1.1 200 OK\r\nContent-Len";
        assert(fp_http_parse_prefix((const uint8_t *)cut, strlen(cut), &response, body, sizeof(body)) == FP_HTTP_INCOMPLETE);
        cut = "HTTP/1.1 403 Forbidden\r\nContent-Length: 4\r\n\r\nnope";
        assert(fp_http_parse_prefix((const uint8_t *)cut, strlen(cut), &response, body, sizeof(body)) == FP_HTTP_OK && response.status == 403);
    }
    puts("http tests passed");
    return 0;
}
