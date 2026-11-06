#include "fp_document.h"
#include <string.h>

typedef struct {
    const uint8_t *data;
    size_t length, pos, count, capacity;
    fp_document_token *tokens;
} parser;

static void spaces(parser *p)
{
    while (p->pos < p->length && p->data[p->pos] == ' ') p->pos++;
}

static int hex_digit(uint8_t c)
{
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

static fp_document_status value(parser *p, size_t parent, unsigned depth)
{
    size_t index, start;
    uint8_t c;
    fp_document_status result;
    if (depth > FP_DOCUMENT_DEPTH_LIMIT || p->count >= p->capacity) return FP_DOCUMENT_LIMIT;
    if (p->pos >= p->length) return FP_DOCUMENT_INVALID;
    start = p->pos;
    index = p->count++;
    memset(&p->tokens[index], 0, sizeof(p->tokens[index]));
    p->tokens[index].offset = start;
    p->tokens[index].parent = parent;
    c = p->data[p->pos++];
    if (c == '[') {
        p->tokens[index].type = FP_DOCUMENT_ARRAY;
        spaces(p);
        if (p->pos < p->length && p->data[p->pos] == ']') p->pos++;
        else for (;;) {
            result = value(p, index, depth + 1);
            if (result != FP_DOCUMENT_OK) return result;
            p->tokens[index].children++;
            spaces(p);
            if (p->pos >= p->length) return FP_DOCUMENT_INVALID;
            c = p->data[p->pos++];
            if (c == ']') break;
            if (c != ',') return FP_DOCUMENT_INVALID;
            spaces(p);
        }
    } else if (c == '"') {
        p->tokens[index].type = FP_DOCUMENT_STRING;
        for (;;) {
            unsigned i;
            if (p->pos >= p->length) return FP_DOCUMENT_INVALID;
            c = p->data[p->pos++];
            if (c == '"') break;
            if (c < 0x20) return FP_DOCUMENT_INVALID;
            if (c != '\\') continue;
            if (p->pos >= p->length) return FP_DOCUMENT_INVALID;
            c = p->data[p->pos++];
            if (c == 'u') {
                for (i = 0; i < 4; i++) {
                    if (p->pos >= p->length || !hex_digit(p->data[p->pos++])) return FP_DOCUMENT_INVALID;
                }
            } else if (c != '"' && c != '\\' && c != 'n' && c != 'r' && c != 't' && c != 'b' && c != 'f') return FP_DOCUMENT_INVALID;
        }
    } else {
        p->tokens[index].type = FP_DOCUMENT_INTEGER;
        if (c == '-') {
            if (p->pos >= p->length) return FP_DOCUMENT_INVALID;
            c = p->data[p->pos++];
        }
        if (c < '0' || c > '9') return FP_DOCUMENT_INVALID;
        while (p->pos < p->length && p->data[p->pos] >= '0' && p->data[p->pos] <= '9') p->pos++;
    }
    p->tokens[index].length = p->pos - start;
    return FP_DOCUMENT_OK;
}

fp_document_status fp_document_parse(const uint8_t *data, size_t length,
                                     fp_document_token *tokens, size_t capacity, size_t *count)
{
    parser p;
    fp_document_status result;
    if (count) *count = 0;
    if (!data || !tokens || !count || !capacity || !length || data[0] != '[') return FP_DOCUMENT_INVALID;
    memset(&p, 0, sizeof(p));
    p.data = data; p.length = length; p.tokens = tokens; p.capacity = capacity;
    result = value(&p, FP_DOCUMENT_NO_PARENT, 0);
    if (result != FP_DOCUMENT_OK) return result;
    spaces(&p);
    if (p.pos != length) return FP_DOCUMENT_INVALID;
    *count = p.count;
    return FP_DOCUMENT_OK;
}

fp_document_status fp_document_quote(const uint8_t *input, size_t length,
                                     uint8_t *output, size_t capacity, size_t *written)
{
    static const char hex[] = "0123456789abcdef";
    size_t i, pos = 0;
    if (written) *written = 0;
    if (!written || !output || (!input && length)) return FP_DOCUMENT_INVALID;
    if (capacity < 2) return FP_DOCUMENT_LIMIT;
    output[pos++] = '"';
    for (i = 0; i < length; i++) {
        uint8_t c = input[i];
        size_t need = c < 0x20 ? 6 : (c == '"' || c == '\\') ? 2 : 1;
        if (need > capacity - pos || capacity - pos - need < 1) return FP_DOCUMENT_LIMIT;
        if (c < 0x20) {
            output[pos++] = '\\'; output[pos++] = 'u'; output[pos++] = '0'; output[pos++] = '0';
            output[pos++] = (uint8_t)hex[c >> 4]; output[pos++] = (uint8_t)hex[c & 15];
        } else {
            if (c == '"' || c == '\\') output[pos++] = '\\';
            output[pos++] = c;
        }
    }
    output[pos++] = '"';
    *written = pos;
    return FP_DOCUMENT_OK;
}
