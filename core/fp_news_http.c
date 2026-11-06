#define _POSIX_C_SOURCE 200809L
#include "fp_news_http.h"
#include "fp_client.h"
#include "fp_http.h"
#include <errno.h>
#include <poll.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#ifdef __APPLE__
#include <mach/mach_time.h>
#endif
#include <openssl/ssl.h>

#define NEWS_TIMEOUT 20000

static uint64_t news_time(void)
{
#ifdef __APPLE__
    mach_timebase_info_data_t info;
    uint64_t ticks = mach_absolute_time();
    if (mach_timebase_info(&info) != KERN_SUCCESS || !info.denom) return 0;
    return (ticks / info.denom) * info.numer / 1000000u;
#else
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now)) return 0;
    return (uint64_t)now.tv_sec * 1000u + (uint64_t)now.tv_nsec / 1000000u;
#endif
}

/* with prefix set the connection is dropped once limit bytes are in, and the shorter body is the answer; a reply that ends before that must be complete */
static fp_session_status news_request(const char *roots_path, const char *path, size_t limit, int prefix, uint8_t **body, size_t *length, int *http_status)
{
    char request[4096];
    int request_length;
    fp_session session;
    fp_session_status status;
    fp_http_response parsed;
    uint8_t *raw = NULL, *output = NULL;
    size_t used = 0, sent = 0;
    uint64_t deadline, now;
    int eof = 0, cut = 0;
    if (body) *body = NULL;
    if (length) *length = 0;
    if (http_status) *http_status = 0;
    if (!roots_path || !path || path[0] != '/' || !body || !length || !http_status || !limit || limit > 2u * 1024u * 1024u) return FP_SESSION_ARGUMENT;
    for (const char *p = path; *p; p++) if ((unsigned char)*p <= 0x20 || (unsigned char)*p >= 0x7f || *p == '#') return FP_SESSION_ARGUMENT;
    request_length = snprintf(request, sizeof(request), "GET %s HTTP/1.1\r\nHost: 4pda.to\r\nUser-Agent: Mozilla/5.0 (iPad; CPU OS 9_3 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13E233 Safari/601.1\r\nAccept: */*\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n", path);
    if (request_length <= 0 || (size_t)request_length >= sizeof(request)) return FP_SESSION_ARGUMENT;
    memset(&session, 0, sizeof(session)); session.fd = -1;
    now = news_time();
    if (!now) return FP_SESSION_IO;
    deadline = now + NEWS_TIMEOUT;
    status = fp_client_connect_guest(&session, "4pda.to", 443, NEWS_TIMEOUT);
    if (status != FP_SESSION_OK) return status;
    now = news_time();
    if (!now || now >= deadline) { status = FP_SESSION_TIMEOUT; goto done; }
    status = fp_session_tls_connect(&session, "4pda.to", roots_path, (int)(deadline - now));
    if (status != FP_SESSION_OK) goto done;
    raw = malloc(limit + FP_HTTP_MAX_HEADERS);
    output = malloc(limit);
    if (!raw || !output) { status = FP_SESSION_MEMORY; goto done; }
    while (!eof) {
        SSL *ssl = (SSL *)session.tls;
        int writing = sent < (size_t)request_length, result, error;
        struct pollfd p;
        now = news_time();
        if (!now || now >= deadline) { status = FP_SESSION_TIMEOUT; goto done; }
        if (writing) result = SSL_write(ssl, request + sent, (int)((size_t)request_length - sent));
        else {
            if (prefix && used >= limit) { cut = 1; break; }
            if (used == limit + FP_HTTP_MAX_HEADERS) { status = FP_SESSION_LIMIT; goto done; }
            result = SSL_read(ssl, raw + used, (int)(limit + FP_HTTP_MAX_HEADERS - used));
        }
        if (result > 0) { if (writing) sent += (size_t)result; else used += (size_t)result; continue; }
        error = SSL_get_error(ssl, result);
        if (error == SSL_ERROR_ZERO_RETURN || (error == SSL_ERROR_SYSCALL && result == 0)) { eof = 1; break; }
        if (error != SSL_ERROR_WANT_READ && error != SSL_ERROR_WANT_WRITE) { status = FP_SESSION_IO; goto done; }
        p.fd = session.fd; p.events = error == SSL_ERROR_WANT_READ ? POLLIN : POLLOUT; p.revents = 0;
        do { result = poll(&p, 1, (int)(deadline - now)); } while (result < 0 && errno == EINTR);
        if (!result) { status = FP_SESSION_TIMEOUT; goto done; }
        if (result < 0 || (p.revents & POLLNVAL)) { status = FP_SESSION_IO; goto done; }
    }
    if (sent != (size_t)request_length) { status = FP_SESSION_EOF; goto done; }
    {
        /* a prefix parse accepts a half chunk, so only a connection that was cut by the limit may use it; one that ended by itself must be whole */
        fp_http_status parsed_status = cut ? fp_http_parse_prefix(raw, used, &parsed, output, limit) : fp_http_parse_response(raw, used, eof, &parsed, output, limit);
        if (parsed_status != FP_HTTP_OK) { status = parsed_status == FP_HTTP_LIMIT ? FP_SESSION_LIMIT : parsed_status == FP_HTTP_INCOMPLETE ? FP_SESSION_EOF : FP_SESSION_PROTOCOL; goto done; }
    }
    *http_status = parsed.status;
    *body = output; output = NULL;
    *length = parsed.body_len;
    status = FP_SESSION_OK;
done:
    free(raw); free(output); fp_session_close(&session);
    return status;
}

fp_session_status fp_news_get(const char *roots_path, const char *path, size_t limit, uint8_t **body, size_t *length, int *http_status)
{
    return news_request(roots_path, path, limit, 0, body, length, http_status);
}

fp_session_status fp_news_get_head(const char *roots_path, const char *path, size_t limit, uint8_t **body, size_t *length, int *http_status)
{
    return news_request(roots_path, path, limit, 1, body, length, http_status);
}

