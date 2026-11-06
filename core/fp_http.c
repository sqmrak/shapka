#include "fp_http.h"

#include <string.h>

static int is_token_char(uint8_t c) {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) return 1;
    return c && strchr("!#$%&'*+-.^_`|~", c) != NULL;
}

static int iequal(const uint8_t *a, size_t alen, const char *b) {
    size_t i;
    if (alen != strlen(b)) return 0;
    for (i = 0; i < alen; ++i) {
        uint8_t x = a[i], y = (uint8_t)b[i];
        if (x >= 'A' && x <= 'Z') x = (uint8_t)(x + 32);
        if (y >= 'A' && y <= 'Z') y = (uint8_t)(y + 32);
        if (x != y) return 0;
    }
    return 1;
}

/* the position of the CRLF that ends the line starting at from, or len when there is none */
static size_t find_crlf(const uint8_t *data, size_t len, size_t from) {
    size_t i;
    for (i = from; i + 1 < len; ++i) {
        if (data[i] == '\r' && data[i + 1] == '\n') return i;
    }
    return len;
}

static int hex_digit(uint8_t c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static fp_http_status decode_chunked(const uint8_t *data, size_t len, int eof, uint8_t *body, size_t cap, size_t *body_len) {
    size_t pos = 0, out = 0;
    for (;;) {
        size_t line_end = find_crlf(data, len, pos), size = 0, digits = 0;
        if (line_end >= len) return len - pos > 64 ? FP_HTTP_INVALID : FP_HTTP_INCOMPLETE;
        while (pos + digits < line_end && hex_digit(data[pos + digits]) >= 0) {
            size = size << 4 | (size_t)hex_digit(data[pos + digits]);
            if (++digits > 8) return FP_HTTP_INVALID;
        }
        if (digits == 0) return FP_HTTP_INVALID;
        /* chunk extensions are allowed and ignored, nothing else may follow the size */
        if (pos + digits < line_end && data[pos + digits] != ';') return FP_HTTP_INVALID;
        pos = line_end + 2;
        if (size == 0) {
            /* trailers, then the empty line */
            for (;;) {
                size_t end = find_crlf(data, len, pos);
                if (end >= len) return FP_HTTP_INCOMPLETE;
                if (end == pos) {
                    *body_len = out;
                    return FP_HTTP_OK;
                }
                pos = end + 2;
            }
        }
        if (size > cap - out) return FP_HTTP_LIMIT;
        if (len - pos < size + 2) return FP_HTTP_INCOMPLETE;
        memcpy(body + out, data + pos, size);
        out += size;
        pos += size;
        if (data[pos] != '\r' || data[pos + 1] != '\n') return FP_HTTP_INVALID;
        pos += 2;
    }
    (void)eof;
}

fp_http_status fp_http_parse_head(const uint8_t *data, size_t len, int eof, fp_http_head *out) {
    size_t pos, line_end;
    int status, i;
    if (out) memset(out, 0, sizeof(*out));
    if (!data || !out) return FP_HTTP_ARGUMENT;
    line_end = find_crlf(data, len, 0);
    if (line_end >= len) return len > 512 ? FP_HTTP_INVALID : (eof ? FP_HTTP_INVALID : FP_HTTP_INCOMPLETE);
    if (line_end < 12 || memcmp(data, "HTTP/1.", 7) != 0 || (data[7] != '0' && data[7] != '1') || data[8] != ' ') return FP_HTTP_INVALID;
    status = 0;
    for (i = 9; i < 12; ++i) {
        if (data[i] < '0' || data[i] > '9') return FP_HTTP_INVALID;
        status = status * 10 + (data[i] - '0');
    }
    if (status < 100 || status > 599 || (line_end > 12 && data[12] != ' ')) return FP_HTTP_INVALID;
    /* the feed request does not expect an interim response */
    if (status < 200) return FP_HTTP_INVALID;
    pos = line_end + 2;
    for (;;) {
        size_t end = find_crlf(data, len, pos), colon, name_len, vstart, vend;
        if (pos > FP_HTTP_MAX_HEADERS) return FP_HTTP_LIMIT;
        if (end >= len) return eof ? FP_HTTP_INVALID : FP_HTTP_INCOMPLETE;
        if (end == pos) {
            out->body_start = pos + 2;
            break;
        }
        for (colon = pos; colon < end && data[colon] != ':'; ++colon) {
            if (!is_token_char(data[colon])) return FP_HTTP_INVALID;
        }
        if (colon == pos || colon >= end) return FP_HTTP_INVALID;
        name_len = colon - pos;
        vstart = colon + 1;
        while (vstart < end && (data[vstart] == ' ' || data[vstart] == '\t')) ++vstart;
        vend = end;
        while (vend > vstart && (data[vend - 1] == ' ' || data[vend - 1] == '\t')) --vend;
        if (iequal(data + pos, name_len, "content-length")) {
            size_t k, value = 0;
            if (vend == vstart || vend - vstart > 9) return FP_HTTP_INVALID;
            for (k = vstart; k < vend; ++k) {
                if (data[k] < '0' || data[k] > '9') return FP_HTTP_INVALID;
                value = value * 10 + (size_t)(data[k] - '0');
            }
            if (out->has_length && value != out->content_length) return FP_HTTP_INVALID;
            out->has_length = 1;
            out->content_length = value;
        } else if (iequal(data + pos, name_len, "transfer-encoding")) {
            if (!iequal(data + vstart, vend - vstart, "chunked")) return FP_HTTP_INVALID;
            out->chunked = 1;
        } else if (iequal(data + pos, name_len, "content-encoding")) {
            if (!iequal(data + vstart, vend - vstart, "identity")) return FP_HTTP_INVALID;
        } else if (iequal(data + pos, name_len, "location")) {
            size_t k;
            if (vend - vstart >= sizeof(out->location)) return FP_HTTP_LIMIT;
            for (k = vstart; k < vend; ++k) {
                if (data[k] < 0x21 || data[k] > 0x7E) return FP_HTTP_INVALID;
            }
            memcpy(out->location, data + vstart, vend - vstart);
            out->location[vend - vstart] = 0;
        }
        pos = end + 2;
    }
    if (out->chunked && out->has_length) return FP_HTTP_INVALID;
    out->status = status;
    return FP_HTTP_OK;
}

fp_http_status fp_http_parse_response(const uint8_t *data, size_t len, int eof, fp_http_response *out, uint8_t *body, size_t cap) {
    fp_http_head head;
    fp_http_status parsed;
    if (out) memset(out, 0, sizeof(*out));
    if (!data || !out || (cap && !body)) return FP_HTTP_ARGUMENT;
    parsed = fp_http_parse_head(data, len, eof, &head);
    if (parsed != FP_HTTP_OK) return parsed;
    out->status = head.status;
    if (head.status == 204 || head.status == 304) return FP_HTTP_OK;
    if (head.chunked) return decode_chunked(data + head.body_start, len - head.body_start, eof, body, cap, &out->body_len);
    if (head.has_length) {
        if (head.content_length > cap) return FP_HTTP_LIMIT;
        if (len - head.body_start < head.content_length) return FP_HTTP_INCOMPLETE;
        memcpy(body, data + head.body_start, head.content_length);
        out->body_len = head.content_length;
        return FP_HTTP_OK;
    }
    /* no framing: the body runs to the end of the connection */
    if (!eof) return FP_HTTP_INCOMPLETE;
    if (len - head.body_start > cap) return FP_HTTP_LIMIT;
    memcpy(body, data + head.body_start, len - head.body_start);
    out->body_len = len - head.body_start;
    return FP_HTTP_OK;
}

fp_http_status fp_http_parse_prefix(const uint8_t *data, size_t len, fp_http_response *out, uint8_t *body, size_t cap) {
    fp_http_head head;
    fp_http_status parsed;
    const uint8_t *in;
    size_t avail, pos = 0, used = 0;
    if (out) memset(out, 0, sizeof(*out));
    if (!data || !out || (cap && !body)) return FP_HTTP_ARGUMENT;
    parsed = fp_http_parse_head(data, len, 0, &head);
    if (parsed != FP_HTTP_OK) return parsed;
    out->status = head.status;
    in = data + head.body_start;
    avail = len - head.body_start;
    if (head.status == 204 || head.status == 304) return FP_HTTP_OK;
    if (!head.chunked) {
        used = avail;
        if (head.has_length && head.content_length < used) used = head.content_length;
        if (used > cap) used = cap;
        memcpy(body, in, used);
        out->body_len = used;
        return FP_HTTP_OK;
    }
    while (used < cap) {
        size_t line_end = find_crlf(in, avail, pos), size = 0, digits = 0, take;
        if (line_end >= avail) return avail - pos > 64 ? FP_HTTP_INVALID : (out->body_len = used, FP_HTTP_OK);
        while (pos + digits < line_end && hex_digit(in[pos + digits]) >= 0) {
            size = size << 4 | (size_t)hex_digit(in[pos + digits]);
            if (++digits > 8) return FP_HTTP_INVALID;
        }
        if (digits == 0 || (pos + digits < line_end && in[pos + digits] != ';')) return FP_HTTP_INVALID;
        pos = line_end + 2;
        if (size == 0) break;
        take = avail - pos < size ? avail - pos : size;
        if (take > cap - used) take = cap - used;
        memcpy(body + used, in + pos, take);
        used += take;
        /* a chunk that is not whole ends what arrived */
        if (take < size || avail - pos < size + 2) break;
        pos += size;
        if (in[pos] != '\r' || in[pos + 1] != '\n') return FP_HTTP_INVALID;
        pos += 2;
    }
    out->body_len = used;
    return FP_HTTP_OK;
}
