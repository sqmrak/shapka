#include "fp_news_image.h"
#include <string.h>
#include <ctype.h>

static int match(const uint8_t *bytes, size_t n, const char *word)
{
    size_t i;
    if (strlen(word) != n) return 0;
    for (i = 0; i < n; i++) if (tolower(bytes[i]) != (unsigned char)word[i]) return 0;
    return 1;
}

int fp_news_image_url(const uint8_t *data, size_t length, char *output, size_t capacity)
{
    size_t i;
    if (output && capacity) output[0] = 0;
    if (!data || !output || !capacity) return 0;
    for (i = 0; i + 5 < length; i++) {
        size_t p, stop, content_start = 0, content_length = 0;
        int og = 0;
        if (data[i] != '<' || !match(data + i + 1, 4, "meta") || !isspace(data[i + 5])) continue;
        stop = i + 5;
        while (stop < length && data[stop] != '>' && stop - i < 4096) stop++;
        if (stop == length || data[stop] != '>') continue;
        p = i + 5;
        while (p < stop) {
            size_t name, n, value, v;
            while (p < stop && (isspace(data[p]) || data[p] == '/')) p++;
            name = p;
            while (p < stop && (isalnum(data[p]) || data[p] == '-' || data[p] == ':')) p++;
            n = p - name;
            if (!n) { p++; continue; }
            while (p < stop && isspace(data[p])) p++;
            if (p >= stop || data[p] != '=') continue;
            p++;
            while (p < stop && isspace(data[p])) p++;
            if (p >= stop) break;
            if (data[p] == '\'' || data[p] == '"') {
                uint8_t quote = data[p++]; value = p;
                while (p < stop && data[p] != quote) p++;
                v = p - value;
                if (p == stop) break;
                p++;
            } else {
                value = p;
                while (p < stop && !isspace(data[p]) && data[p] != '>') p++;
                v = p - value;
            }
            if ((match(data + name, n, "property") || match(data + name, n, "name")) && match(data + value, v, "og:image")) og = 1;
            if (match(data + name, n, "content")) { content_start = value; content_length = v; }
        }
        if (og && content_length && content_length < capacity) {
            memcpy(output, data + content_start, content_length); output[content_length] = 0; return 1;
        }
        i = stop;
    }
    return 0;
}
