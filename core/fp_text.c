#include "fp_text.h"
#include <string.h>

static const uint16_t cp1251_high[64] = {
    0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, 0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F,
    0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0xFFFD, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
    0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, 0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
    0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7, 0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
};

static size_t utf8_encode(uint32_t cp, char out[4])
{
    if (cp < 0x80) { out[0] = (char)cp; return 1; }
    if (cp < 0x800) { out[0] = (char)(0xC0 | (cp >> 6)); out[1] = (char)(0x80 | (cp & 0x3F)); return 2; }
    if (cp < 0x10000) {
        out[0] = (char)(0xE0 | (cp >> 12)); out[1] = (char)(0x80 | ((cp >> 6) & 0x3F)); out[2] = (char)(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = (char)(0xF0 | (cp >> 18)); out[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    out[2] = (char)(0x80 | ((cp >> 6) & 0x3F)); out[3] = (char)(0x80 | (cp & 0x3F));
    return 4;
}

static int hex_value(uint8_t c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static int read_hex4(const uint8_t *p, size_t left, uint32_t *value)
{
    uint32_t v = 0;
    size_t i;
    if (left < 4) return 0;
    for (i = 0; i < 4; i++) {
        int d = hex_value(p[i]);
        if (d < 0) return 0;
        v = (v << 4) | (uint32_t)d;
    }
    *value = v;
    return 1;
}

fp_text_status fp_text_decode(fp_span span, char *output, size_t capacity, size_t *written)
{
    size_t i = 0, pos = 0;
    fp_text_status status = FP_TEXT_OK;
    if (written) *written = 0;
    if (!output || !capacity || !written || (!span.data && span.length)) return FP_TEXT_INVALID;
    while (i < span.length) {
        uint32_t cp;
        char encoded[4];
        size_t n;
        uint8_t c = span.data[i++];
        if (c == '\\') {
            if (i >= span.length) return FP_TEXT_INVALID;
            c = span.data[i++];
            switch (c) {
            case 'n': cp = '\n'; break;
            case 'r': cp = '\r'; break;
            case 't': cp = '\t'; break;
            case 'b': cp = '\b'; break;
            case 'f': cp = '\f'; break;
            case '"': case '\\': cp = c; break;
            case 'u':
                if (!read_hex4(span.data + i, span.length - i, &cp)) return FP_TEXT_INVALID;
                i += 4;
                if (cp >= 0xD800 && cp <= 0xDBFF) {
                    uint32_t low;
                    if (i + 6 <= span.length && span.data[i] == '\\' && span.data[i + 1] == 'u' &&
                        read_hex4(span.data + i + 2, span.length - i - 2, &low) && low >= 0xDC00 && low <= 0xDFFF) {
                        cp = 0x10000u + ((cp - 0xD800u) << 10) + (low - 0xDC00u);
                        i += 6;
                    } else cp = 0xFFFD;
                } else if (cp >= 0xDC00 && cp <= 0xDFFF) cp = 0xFFFD;
                break;
            default: return FP_TEXT_INVALID;
            }
        } else if (c < 0x80) cp = c;
        else if (c >= 0xC0) cp = 0x0410u + (uint32_t)(c - 0xC0);
        else cp = cp1251_high[c - 0x80];
        n = utf8_encode(cp, encoded);
        if (n > capacity - 1 - pos) { status = FP_TEXT_LIMIT; break; }
        memcpy(output + pos, encoded, n);
        pos += n;
    }
    output[pos] = 0;
    *written = pos;
    return status;
}

static int entity_codepoint(const char *name, size_t length, uint32_t *cp)
{
    static const struct { const char *name; uint32_t cp; } named[] = {
        {"amp", '&'}, {"lt", '<'}, {"gt", '>'}, {"quot", '"'}, {"apos", '\''}, {"nbsp", 0x00A0},
        {"laquo", 0x00AB}, {"raquo", 0x00BB}, {"mdash", 0x2014}, {"ndash", 0x2013}, {"hellip", 0x2026},
        {"ldquo", 0x201C}, {"rdquo", 0x201D}, {"lsquo", 0x2018}, {"rsquo", 0x2019}, {"bull", 0x2022}, {"middot", 0x00B7},
        {"deg", 0x00B0}, {"copy", 0x00A9}, {"reg", 0x00AE}, {"trade", 0x2122}, {"euro", 0x20AC}, {"times", 0x00D7}, {"plusmn", 0x00B1},
    };
    size_t i;
    if (length >= 2 && name[0] == '#') {
        uint32_t v = 0;
        size_t start = 1;
        unsigned base = 10;
        if (name[1] == 'x' || name[1] == 'X') { base = 16; start = 2; }
        if (start >= length) return 0;
        for (i = start; i < length; i++) {
            int d = hex_value((uint8_t)name[i]);
            if (d < 0 || (unsigned)d >= base) return 0;
            v = v * base + (uint32_t)d;
            if (v > 0x10FFFF) return 0;
        }
        if (!v || (v >= 0xD800 && v <= 0xDFFF)) return 0;
        *cp = v;
        return 1;
    }
    for (i = 0; i < sizeof(named) / sizeof(named[0]); i++) {
        if (strlen(named[i].name) == length && memcmp(named[i].name, name, length) == 0) { *cp = named[i].cp; return 1; }
    }
    return 0;
}

size_t fp_text_unescape_entities(const char *input, size_t length, char *output, size_t capacity)
{
    size_t i = 0, pos = 0;
    if (!output || !capacity) return 0;
    while (i < length && pos + 1 < capacity) {
        if (input[i] == '&') {
            size_t end = i + 1;
            uint32_t cp;
            while (end < length && end - i <= 10 && input[end] != ';' && input[end] != '&' && input[end] != ' ') end++;
            if (end < length && input[end] == ';' && entity_codepoint(input + i + 1, end - i - 1, &cp)) {
                char encoded[4];
                size_t n = utf8_encode(cp, encoded);
                if (n > capacity - 1 - pos) break;
                memcpy(output + pos, encoded, n);
                pos += n;
                i = end + 1;
                continue;
            }
        }
        output[pos++] = input[i++];
    }
    output[pos] = 0;
    return pos;
}
