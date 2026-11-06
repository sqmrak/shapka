#define _POSIX_C_SOURCE 200809L
#include "fp_session.h"
#include "fp_frame.h"
#include "fp_document.h"
#include "fp_tls.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <netinet/in.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/rand.h>
#include <openssl/sha.h>
#include <openssl/evp.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <mach/mach_time.h>
#endif

#define FP_TOKEN_LIMIT 32768u
#define FP_CONTROL_LIMIT 64u

static uint64_t now_ms(void)
{
#ifdef __APPLE__
    mach_timebase_info_data_t info;
    uint64_t ticks = mach_absolute_time();
    if (mach_timebase_info(&info) != KERN_SUCCESS || info.denom == 0) return 0;
    return (ticks / info.denom) * info.numer / 1000000u;
#else
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
#endif
}

static fp_session_status transfer(fp_session *session, uint8_t *data, size_t length, int writing, uint64_t deadline)
{
    int fd = session->fd;
    short events = writing ? POLLOUT : POLLIN;
    size_t pos = 0;
    while (pos < length) {
        struct pollfd p;
        uint64_t now = now_ms();
        int wait, ready;
        ssize_t n;
        if (!now || now >= deadline) return FP_SESSION_TIMEOUT;
        wait = deadline - now > INT_MAX ? INT_MAX : (int)(deadline - now);
        p.fd = fd; p.events = events; p.revents = 0;
        ready = (events == POLLIN && session->tls && SSL_pending((SSL *)session->tls) > 0) ? 1 : poll(&p, 1, wait);
        if (ready < 0 && errno == EINTR) continue;
        if (ready == 0) return FP_SESSION_TIMEOUT;
        if (ready < 0 || (p.revents & (POLLERR | POLLNVAL))) return FP_SESSION_IO;
        if (session->tls) {
            int ssl_result = writing ? SSL_write((SSL *)session->tls, data + pos, (int)(length - pos > INT_MAX ? INT_MAX : length - pos)) :
                                       SSL_read((SSL *)session->tls, data + pos, (int)(length - pos > INT_MAX ? INT_MAX : length - pos));
            if (ssl_result <= 0) {
                int error = SSL_get_error((SSL *)session->tls, ssl_result);
                if (error == SSL_ERROR_WANT_READ || error == SSL_ERROR_WANT_WRITE) {
                    events = error == SSL_ERROR_WANT_READ ? POLLIN : POLLOUT;
                    continue;
                }
                return error == SSL_ERROR_ZERO_RETURN ? FP_SESSION_EOF : FP_SESSION_IO;
            }
            n = ssl_result;
            events = writing ? POLLOUT : POLLIN;
        } else if (writing) {
#ifdef MSG_NOSIGNAL
            n = send(fd, data + pos, length - pos, MSG_NOSIGNAL);
#else
            n = send(fd, data + pos, length - pos, 0);
#endif
        } else n = recv(fd, data + pos, length - pos, 0);
        if (n == 0) return FP_SESSION_EOF;
        if (n < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (n < 0) return FP_SESSION_IO;
        pos += (size_t)n;
    }
    return FP_SESSION_OK;
}

fp_session_status fp_session_init(fp_session *session, int connected_fd)
{
    int flags;
    if (!session || connected_fd < 0) return FP_SESSION_ARGUMENT;
    session->fd = -1;
    session->next_id = 1;
    session->event = NULL;
    session->event_context = NULL;
    session->tls = NULL;
    session->tls_split = 0;
    session->tls_context = NULL;
#ifdef SO_NOSIGPIPE
    { int one = 1;
      if (setsockopt(connected_fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) != 0) return FP_SESSION_IO; }
#endif
    flags = fcntl(connected_fd, F_GETFL, 0);
    if (flags < 0 || fcntl(connected_fd, F_SETFL, flags | O_NONBLOCK) < 0) return FP_SESSION_IO;
    session->fd = connected_fd;
    return FP_SESSION_OK;
}

fp_session_status fp_session_connect_ipv4(fp_session *session, uint32_t address, uint16_t port, int timeout_ms)
{
    struct sockaddr_in destination;
    struct pollfd p;
    uint64_t deadline;
    int fd, flags, error, ready;
    socklen_t error_length = sizeof(error);
    if (!session || !address || !port || timeout_ms <= 0) return FP_SESSION_ARGUMENT;
    session->fd = -1;
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return FP_SESSION_IO;
    flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) { close(fd); return FP_SESSION_IO; }
    memset(&destination, 0, sizeof(destination));
    destination.sin_family = AF_INET;
    destination.sin_addr.s_addr = htonl(address);
    destination.sin_port = htons(port);
    deadline = now_ms() + (uint64_t)timeout_ms;
    if (connect(fd, (struct sockaddr *)&destination, sizeof(destination)) < 0) {
        if (errno != EINPROGRESS) { close(fd); return FP_SESSION_IO; }
        for (;;) {
            uint64_t now = now_ms();
            int wait;
            if (!now || now >= deadline) { close(fd); return FP_SESSION_TIMEOUT; }
            wait = deadline - now > INT_MAX ? INT_MAX : (int)(deadline - now);
            p.fd = fd; p.events = POLLOUT; p.revents = 0;
            ready = poll(&p, 1, wait);
            if (ready < 0 && errno == EINTR) continue;
            if (ready == 0) { close(fd); return FP_SESSION_TIMEOUT; }
            if (ready < 0 || (p.revents & POLLNVAL) || getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &error_length) < 0 || error) {
                close(fd); return FP_SESSION_IO;
            }
            break;
        }
    }
    if (fp_session_init(session, fd) != FP_SESSION_OK) { close(fd); return FP_SESSION_IO; }
    return FP_SESSION_OK;
}

static int header_has_token(const char *value, const char *token)
{
    size_t token_length = strlen(token);
    while (*value) {
        const char *start, *end;
        while (*value == ' ' || *value == '\t' || *value == ',') value++;
        start = value;
        while (*value && *value != ',') value++;
        end = value;
        while (end > start && (end[-1] == ' ' || end[-1] == '\t')) end--;
        if ((size_t)(end - start) == token_length && strncasecmp(start, token, token_length) == 0) return 1;
    }
    return 0;
}

fp_session_status fp_session_tls_connect(fp_session *session, const char *hostname, const char *roots_path, int timeout_ms)
{
    SSL_CTX *ctx;
    SSL *ssl;
    BIO *bio;
    uint64_t deadline;
    int result;
    const char *p;
    fp_session_status status = FP_SESSION_SECURITY;
    if (!session || session->fd < 0 || session->tls || !hostname || !roots_path || timeout_ms <= 0) return FP_SESSION_ARGUMENT;
    if (!*hostname || strlen(hostname) > 253) return FP_SESSION_ARGUMENT;
    for (p = hostname; *p; p++) {
        if (!isalnum((unsigned char)*p) && *p != '.' && *p != '-') return FP_SESSION_ARGUMENT;
    }
    ctx = SSL_CTX_new(TLS_client_method());
    if (!ctx) return FP_SESSION_SECURITY;
    session->tls_context = ctx;
    SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
    if (!SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION) || SSL_CTX_load_verify_locations(ctx, roots_path, NULL) != 1) goto fail;
    ssl = SSL_new(ctx);
    if (!ssl) goto fail;
    session->tls = ssl;
    bio = fp_tls_bio(session->fd, session->tls_split);
    if (!bio) goto fail;
    SSL_set_bio(ssl, bio, bio);
    if (SSL_set_tlsext_host_name(ssl, hostname) != 1 || SSL_set1_host(ssl, hostname) != 1) goto fail;
    deadline = now_ms() + (uint64_t)timeout_ms;
    for (;;) {
        struct pollfd p;
        uint64_t now;
        int error, wait;
        result = SSL_connect(ssl);
        if (result == 1) break;
        error = SSL_get_error(ssl, result);
        if (error != SSL_ERROR_WANT_READ && error != SSL_ERROR_WANT_WRITE) goto fail;
        now = now_ms();
        if (!now || now >= deadline) { status = FP_SESSION_TIMEOUT; goto fail; }
        wait = deadline - now > INT_MAX ? INT_MAX : (int)(deadline - now);
        p.fd = session->fd; p.events = error == SSL_ERROR_WANT_READ ? POLLIN : POLLOUT; p.revents = 0;
        result = poll(&p, 1, wait);
        if (result < 0 && errno == EINTR) continue;
        if (!result) { status = FP_SESSION_TIMEOUT; goto fail; }
        if (result < 0 || (p.revents & (POLLERR | POLLNVAL))) { status = FP_SESSION_IO; goto fail; }
    }
    if (SSL_get_verify_result(ssl) != X509_V_OK) goto fail;
    return FP_SESSION_OK;
fail:
    fp_session_close(session);
    return status;
}

fp_session_status fp_session_start_tls(fp_session *session, const char *hostname,
                                       const char *roots_path, int timeout_ms)
{
    uint64_t deadline;
    uint8_t nonce[16], digest[SHA_DIGEST_LENGTH];
    char key[25], accept[29], material[128], request[1024], headers[8193];
    size_t length = 0;
    int n, accept_seen = 0, protocol_seen = 0, upgrade_seen = 0, connection_seen = 0;
    char *line, *next;
    fp_session_status status;
    if (timeout_ms <= 0) return FP_SESSION_ARGUMENT;
    deadline = now_ms() + (uint64_t)timeout_ms;
    status = fp_session_tls_connect(session, hostname, roots_path, timeout_ms);
    if (status != FP_SESSION_OK) return status;
    status = FP_SESSION_SECURITY;
    if (RAND_bytes(nonce, sizeof(nonce)) != 1) { status = FP_SESSION_SECURITY; goto fail; }
    EVP_EncodeBlock((unsigned char *)key, nonce, sizeof(nonce));
    n = snprintf(material, sizeof(material), "%s258EAFA5-E914-47DA-95CA-C5AB0DC85B11", key);
    if (n <= 0 || (size_t)n >= sizeof(material) || !SHA1((const unsigned char *)material, (size_t)n, digest)) goto fail;
    EVP_EncodeBlock((unsigned char *)accept, digest, sizeof(digest));
    n = snprintf(request, sizeof(request), "GET /ws/ HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Protocol: app\r\nSec-WebSocket-Version: 13\r\n\r\n", hostname, key);
    if (n <= 0 || (size_t)n >= sizeof(request)) goto fail;
    status = transfer(session, (uint8_t *)request, (size_t)n, 1, deadline);
    if (status != FP_SESSION_OK) goto fail;
    while (length < sizeof(headers) - 1) {
        status = transfer(session, (uint8_t *)headers + length, 1, 0, deadline);
        if (status != FP_SESSION_OK) goto fail;
        if (!headers[length] || ((unsigned char)headers[length] < 0x20 && headers[length] != '\r' && headers[length] != '\n' && headers[length] != '\t')) {
            status = FP_SESSION_PROTOCOL; goto fail;
        }
        length++;
        if (length >= 4 && memcmp(headers + length - 4, "\r\n\r\n", 4) == 0) break;
    }
    status = FP_SESSION_PROTOCOL;
    if (length < 4 || memcmp(headers + length - 4, "\r\n\r\n", 4)) goto fail;
    headers[length] = 0;
    line = headers;
    next = strstr(line, "\r\n");
    if (!next) goto fail;
    *next = 0;
    if (strncmp(line, "HTTP/1.1 101", 12) || (line[12] && line[12] != ' ')) goto fail;
    line = next + 2;
    while (*line) {
        char *colon, *value, *end;
        next = strstr(line, "\r\n");
        if (!next) goto fail;
        if (next == line) break;
        *next = 0;
        colon = strchr(line, ':');
        if (!colon) goto fail;
        *colon = 0; value = colon + 1;
        while (*value == ' ' || *value == '\t') value++;
        end = value + strlen(value);
        while (end > value && (end[-1] == ' ' || end[-1] == '\t')) *--end = 0;
        if (!strcasecmp(line, "Sec-WebSocket-Accept")) {
            if (accept_seen++ || strcmp(value, accept)) goto fail;
        } else if (!strcasecmp(line, "Sec-WebSocket-Protocol")) {
            if (protocol_seen++ || strcmp(value, "app")) goto fail;
        } else if (!strcasecmp(line, "Upgrade")) {
            if (upgrade_seen++ || !header_has_token(value, "websocket")) goto fail;
        } else if (!strcasecmp(line, "Connection")) {
            if (connection_seen++ || !header_has_token(value, "upgrade")) goto fail;
        }
        line = next + 2;
    }
    /* the cloudflare front of appbk.4pda.to drops the subprotocol line of the answer; a server that names one must still name the one that was offered */
    if (accept_seen != 1 || upgrade_seen != 1 || connection_seen != 1) goto fail;
    return FP_SESSION_OK;
fail:
    fp_session_close(session);
    return status;
}

void fp_session_close(fp_session *session)
{
    if (!session) return;
    if (session->tls) { SSL_free((SSL *)session->tls); session->tls = NULL; }
    if (session->tls_context) { SSL_CTX_free((SSL_CTX *)session->tls_context); session->tls_context = NULL; }
    if (session->fd >= 0) { close(session->fd); session->fd = -1; }
}

void fp_session_set_event_handler(fp_session *session, fp_session_event_fn event, void *context)
{
    if (session) { session->event = event; session->event_context = context; }
}

static void erase_bytes(void *memory, size_t length)
{
    volatile uint8_t *p = memory;
    while (length--) *p++ = 0;
}

void fp_reply_clear(fp_reply *reply)
{
    if (reply) { if (reply->data) erase_bytes(reply->data, reply->length); free(reply->data); memset(reply, 0, sizeof(*reply)); }
}

static int token_number(const uint8_t *data, const fp_document_token *token, int32_t *out)
{
    char buf[16], *end;
    long value;
    if (token->type != FP_DOCUMENT_INTEGER || !token->length || token->length >= sizeof(buf)) return 0;
    memcpy(buf, data + token->offset, token->length); buf[token->length] = 0;
    errno = 0; value = strtol(buf, &end, 10);
    if (errno || *end || value < INT32_MIN || value > INT32_MAX) return 0;
    *out = (int32_t)value;
    return 1;
}

static fp_session_status read_frame(fp_session *s, uint64_t deadline, uint8_t **bytes, size_t *length)
{
    uint8_t head[10];
    size_t h = 2, n, i;
    uint64_t payload;
    fp_session_status status;
    *bytes = NULL; *length = 0;
    status = transfer(s, head, 2, 0, deadline);
    if (status != FP_SESSION_OK) return status;
    if (head[1] & 0x80) return FP_SESSION_PROTOCOL;
    payload = head[1] & 0x7f;
    if (payload == 126 || payload == 127) {
        h = payload == 126 ? 4 : 10;
        status = transfer(s, head + 2, h - 2, 0, deadline);
        if (status != FP_SESSION_OK) return status;
        payload = 0;
        for (i = 2; i < h; i++) payload = (payload << 8) | head[i];
    }
    if (payload > FP_FRAME_LIMIT) return FP_SESSION_LIMIT;
    n = h + (size_t)payload;
    *bytes = malloc(n);
    if (!*bytes) return FP_SESSION_MEMORY;
    memcpy(*bytes, head, h);
    status = transfer(s, *bytes + h, (size_t)payload, 0, deadline);
    if (status != FP_SESSION_OK) { free(*bytes); *bytes = NULL; return status; }
    *length = n;
    return FP_SESSION_OK;
}

fp_session_status fp_session_wait_event(fp_session *session, int timeout_ms)
{
    uint64_t deadline;
    unsigned controls = 0;
    fp_session_status status;
    fp_document_token *tokens;
    if (!session || timeout_ms <= 0 || !session->event) return FP_SESSION_ARGUMENT;
    if (session->fd < 0) return FP_SESSION_CLOSED;
    tokens = calloc(FP_TOKEN_LIMIT, sizeof(*tokens));
    if (!tokens) return FP_SESSION_MEMORY;
    deadline = now_ms() + (uint64_t)timeout_ms;
    for (;;) {
        uint8_t *raw = NULL, *output = NULL;
        size_t raw_length, output_length, count;
        int32_t id, code;
        fp_frame frame;
        status = read_frame(session, deadline, &raw, &raw_length);
        if (status != FP_SESSION_OK) break;
        if (fp_frame_read(raw, raw_length, &frame) != FP_FRAME_OK || !frame.final) {
            free(raw); status = FP_SESSION_PROTOCOL; break;
        }
        if (frame.opcode >= 8) {
            if (++controls > FP_CONTROL_LIMIT) { free(raw); status = FP_SESSION_LIMIT; break; }
            if (frame.opcode == 8) { free(raw); status = FP_SESSION_EOF; break; }
            if (frame.opcode == 9) {
                raw[0] = 0x8a;
                status = transfer(session, raw, raw_length, 1, deadline);
                free(raw);
                if (status != FP_SESSION_OK) break;
            } else free(raw);
            status = FP_SESSION_OK;
            break;
        }
        if (frame.opcode != 1 && frame.opcode != 2) { free(raw); status = FP_SESSION_PROTOCOL; break; }
        if (frame.compressed) {
            uint32_t size;
            if (frame.payload_length < 4) { free(raw); status = FP_SESSION_PROTOCOL; break; }
            size = (uint32_t)frame.payload[0] | ((uint32_t)frame.payload[1] << 8) |
                   ((uint32_t)frame.payload[2] << 16) | ((uint32_t)frame.payload[3] << 24);
            if (size > FP_FRAME_LIMIT) { free(raw); status = FP_SESSION_LIMIT; break; }
            output = malloc((size_t)size + 1);
            if (!output) { free(raw); status = FP_SESSION_MEMORY; break; }
            if (fp_frame_inflate(&frame, output, (size_t)size + 1, &output_length) != FP_FRAME_OK) {
                free(output); free(raw); status = FP_SESSION_PROTOCOL; break;
            }
        } else {
            output_length = frame.payload_length;
            output = malloc(output_length + 1);
            if (!output) { free(raw); status = FP_SESSION_MEMORY; break; }
            memcpy(output, frame.payload, output_length);
        }
        free(raw);
        if (fp_document_parse(output, output_length, tokens, FP_TOKEN_LIMIT, &count) != FP_DOCUMENT_OK ||
            count < 3 || tokens[0].children < 2 || tokens[1].parent != 0 || tokens[2].parent != 0 ||
            !token_number(output, &tokens[1], &id) || !token_number(output, &tokens[2], &code) ||
            id != 30309 || code != 0) {
            free(output); status = FP_SESSION_PROTOCOL; break;
        }
        session->event(session->event_context, output, output_length);
        free(output);
        status = FP_SESSION_OK;
        break;
    }
    free(tokens);
    if (status != FP_SESSION_OK) fp_session_close(session);
    return status;
}

int fp_session_has_buffered(const fp_session *session)
{
    return session && session->tls && SSL_pending((SSL *)session->tls) > 0;
}

int fp_session_read_ready(const fp_session *session)
{
    struct pollfd descriptor;
    int result;
    if (!session || session->fd < 0) return 0;
    if (fp_session_has_buffered(session)) return 1;
    descriptor.fd = session->fd;
    descriptor.events = POLLIN;
    descriptor.revents = 0;
    do { result = poll(&descriptor, 1, 0); } while (result < 0 && errno == EINTR);
    /* errors and hangups must be read so the session can report the failure */
    return result < 0 || (result > 0 && (descriptor.revents & (POLLIN | POLLHUP | POLLERR | POLLNVAL)));
}

fp_session_status fp_session_request(fp_session *session, const char operation[2],
                                     const uint8_t *arguments, size_t arguments_length,
                                     int timeout_ms, fp_reply *reply)
{
    fp_document_token *tokens = NULL;
    size_t count, payload_length = 0, frame_length = 0, prefix_length;
    uint8_t *payload = NULL, *frame_bytes = NULL;
    char prefix[32];
    uint32_t id;
    int32_t response_id, response_status;
    int prefix_size;
    uint64_t deadline;
    unsigned controls = 0;
    fp_session_status result = FP_SESSION_ARGUMENT;
    if (reply) memset(reply, 0, sizeof(*reply));
    if (!session || !reply || !operation || !arguments || arguments_length < 2 || timeout_ms <= 0) return result;
    if (session->fd < 0) return FP_SESSION_CLOSED;
    if (operation[0] < 'a' || operation[0] > 'z' || operation[1] < 'a' || operation[1] > 'z') return result;
    if (arguments_length > FP_FRAME_LIMIT - 32) return FP_SESSION_LIMIT;
    tokens = calloc(FP_TOKEN_LIMIT, sizeof(*tokens));
    if (!tokens) return FP_SESSION_MEMORY;
    if (fp_document_parse(arguments, arguments_length, tokens, FP_TOKEN_LIMIT, &count) != FP_DOCUMENT_OK) goto done;
    id = session->next_id;
    session->next_id = id == 0x0fffffffu ? 1 : id + 1;
    if (session->next_id == 30309u) session->next_id++;
    prefix_size = snprintf(prefix, sizeof(prefix), "[%u,\"%c%c\"", id, operation[0], operation[1]);
    if (prefix_size < 0 || (size_t)prefix_size >= sizeof(prefix)) goto done;
    prefix_length = (size_t)prefix_size;
    payload_length = prefix_length + arguments_length - 1 + (count > 1 ? 1 : 0);
    payload = malloc(payload_length);
    frame_bytes = malloc(payload_length + payload_length / 100 + 128);
    if (!payload || !frame_bytes) { result = FP_SESSION_MEMORY; goto done; }
    memcpy(payload, prefix, prefix_length);
    if (count > 1) payload[prefix_length++] = ',';
    memcpy(payload + prefix_length, arguments + 1, arguments_length - 1);
    if (fp_frame_encode(payload, payload_length, 1, 1, frame_bytes,
                        payload_length + payload_length / 100 + 128, &frame_length) != FP_FRAME_OK) {
        result = FP_SESSION_LIMIT; goto done;
    }
    deadline = now_ms() + (uint64_t)timeout_ms;
    result = transfer(session, frame_bytes, frame_length, 1, deadline);
    erase_bytes(frame_bytes, frame_length);
    free(frame_bytes); frame_bytes = NULL;
    if (result != FP_SESSION_OK) goto broken;
    for (;;) {
        fp_frame frame;
        size_t raw_length, output_length;
        uint8_t *raw = NULL, *output = NULL;
        result = read_frame(session, deadline, &raw, &raw_length);
        if (result != FP_SESSION_OK) goto broken;
        if (fp_frame_read(raw, raw_length, &frame) != FP_FRAME_OK || !frame.final) {
            free(raw); result = FP_SESSION_PROTOCOL; goto broken;
        }
        if (frame.opcode >= 8) {
            if (++controls > FP_CONTROL_LIMIT) { free(raw); result = FP_SESSION_LIMIT; goto broken; }
            if (frame.opcode == 8) { free(raw); result = FP_SESSION_EOF; goto broken; }
            if (frame.opcode == 9) {
                raw[0] = 0x8a;
                result = transfer(session, raw, raw_length, 1, deadline);
                free(raw);
                if (result != FP_SESSION_OK) goto broken;
            } else free(raw);
            continue;
        }
        if (frame.opcode != 1 && frame.opcode != 2) { free(raw); result = FP_SESSION_PROTOCOL; goto broken; }
        if (frame.compressed) {
            uint32_t size;
            if (frame.payload_length < 4) { free(raw); result = FP_SESSION_PROTOCOL; goto broken; }
            size = (uint32_t)frame.payload[0] | ((uint32_t)frame.payload[1] << 8) |
                   ((uint32_t)frame.payload[2] << 16) | ((uint32_t)frame.payload[3] << 24);
            if (size > FP_FRAME_LIMIT) { free(raw); result = FP_SESSION_LIMIT; goto broken; }
            output = malloc((size_t)size + 1);
            if (!output) { free(raw); result = FP_SESSION_MEMORY; goto broken; }
            if (fp_frame_inflate(&frame, output, (size_t)size + 1, &output_length) != FP_FRAME_OK) {
                free(output); free(raw); result = FP_SESSION_PROTOCOL; goto broken;
            }
        } else {
            output_length = frame.payload_length;
            output = malloc(output_length + 1);
            if (!output) { free(raw); result = FP_SESSION_MEMORY; goto broken; }
            memcpy(output, frame.payload, output_length);
        }
        free(raw);
        if (fp_document_parse(output, output_length, tokens, FP_TOKEN_LIMIT, &count) != FP_DOCUMENT_OK ||
            count < 3 || tokens[0].children < 2 || tokens[1].parent != 0 || tokens[2].parent != 0 ||
            !token_number(output, &tokens[1], &response_id) || !token_number(output, &tokens[2], &response_status)) {
            free(output); result = FP_SESSION_PROTOCOL; goto broken;
        }
        if (response_id == 30309 && response_status == 0) {
            if (!session->event || ++controls > FP_CONTROL_LIMIT) {
                free(output); result = FP_SESSION_PROTOCOL; goto broken;
            }
            session->event(session->event_context, output, output_length);
            free(output);
            continue;
        }
        if (((uint32_t)response_id & 0x0fffffffu) != id && response_id != 0) {
            free(output); result = FP_SESSION_PROTOCOL; goto broken;
        }
        output[output_length] = 0;
        reply->data = output; reply->length = output_length; reply->status = response_status;
        result = FP_SESSION_OK;
        goto done;
    }
broken:
    fp_session_close(session);
done:
    free(tokens);
    if (payload) erase_bytes(payload, payload_length);
    if (frame_bytes) erase_bytes(frame_bytes, frame_length);
    free(payload); free(frame_bytes);
    return result;
}
