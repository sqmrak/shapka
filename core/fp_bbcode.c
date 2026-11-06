#include "fp_bbcode.h"
#include <string.h>

typedef struct { const char *name; fp_bb_tag tag; int raw; } tag_info;

static const tag_info tags[] = {
    {"b", FP_BB_B, 0}, {"i", FP_BB_I, 0}, {"u", FP_BB_U, 0}, {"s", FP_BB_S, 0}, {"color", FP_BB_COLOR, 0},
    {"size", FP_BB_SIZE, 0}, {"url", FP_BB_URL, 0}, {"img", FP_BB_IMG, 1}, {"quote", FP_BB_QUOTE, 0},
    {"code", FP_BB_CODE, 1}, {"codebox", FP_BB_CODE, 1}, {"spoiler", FP_BB_SPOILER, 0}, {"hide", FP_BB_HIDE, 0},
    {"mod", FP_BB_MOD, 0}, {"ex", FP_BB_EX, 0}, {"cur", FP_BB_CUR, 0}, {"offtop", FP_BB_OFFTOP, 0},
    {"list", FP_BB_LIST, 0}, {"*", FP_BB_ITEM, 0}, {"center", FP_BB_CENTER, 0}, {"left", FP_BB_LEFT, 0},
    {"right", FP_BB_RIGHT, 0}, {"attachment", FP_BB_ATTACHMENT, 1}, {"sub", FP_BB_SUB, 0}, {"sup", FP_BB_SUP, 0},
    {"table", FP_BB_TABLE, 0}, {"tr", FP_BB_ROW, 0}, {"td", FP_BB_CELL, 0}, {"th", FP_BB_CELL, 0},
    {"break", FP_BB_BREAK, 0}, {"font", FP_BB_PLAIN, 0}, {"background", FP_BB_PLAIN, 0}, {"snapback", FP_BB_PLAIN, 0},
    {"mergetime", FP_BB_PLAIN, 0}, {"nobb", FP_BB_PLAIN, 0}, {"justify", FP_BB_PLAIN, 0}, {"email", FP_BB_PLAIN, 0},
};

static char lower(char c)
{
    return (c >= 'A' && c <= 'Z') ? (char)(c + 32) : c;
}

static int name_equals(const char *text, size_t length, const char *name)
{
    size_t i, n = strlen(name);
    if (n != length) return 0;
    for (i = 0; i < n; i++) if (lower(text[i]) != name[i]) return 0;
    return 1;
}

static const tag_info *find_tag(const char *name, size_t length)
{
    size_t i;
    for (i = 0; i < sizeof(tags) / sizeof(tags[0]); i++) if (name_equals(name, length, tags[i].name)) return &tags[i];
    return NULL;
}

typedef struct {
    const tag_info *info;
    int closed;
} frame;

typedef struct {
    const char *source;
    size_t length;
    fp_bb_node *nodes;
    size_t capacity, count;
} out;

static int emit(out *o, fp_bb_kind kind, fp_bb_tag tag, size_t start, size_t length)
{
    if (o->count >= o->capacity) return 0;
    o->nodes[o->count].kind = kind;
    o->nodes[o->count].tag = tag;
    o->nodes[o->count].start = start;
    o->nodes[o->count].length = length;
    o->count++;
    return 1;
}

static int is_name_char(char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '*';
}

static int attachment_reference(const char *text, size_t length)
{
    size_t i = 0;
    while (i < length && text[i] >= '0' && text[i] <= '9') i++;
    return i > 0 && i + 1 < length && text[i] == ':';
}

/* one tag at source[at] == '['; fills the tag, its argument and the position after the closing bracket */
typedef struct {
    int closing;
    const tag_info *info;
    size_t arg_start, arg_length, next;
} scanned;

static int scan_tag(const char *s, size_t length, size_t at, scanned *t)
{
    size_t i = at + 1, name_start, name_end, depth = 0, arg_start;
    int quoted = 0;
    memset(t, 0, sizeof(*t));
    if (i < length && s[i] == '/') { t->closing = 1; i++; }
    name_start = i;
    while (i < length && is_name_char(s[i]) && i - name_start < 16) i++;
    name_end = i;
    if (name_end == name_start) return 0;
    t->info = find_tag(s + name_start, name_end - name_start);
    if (!t->info) return 0;
    /* news text sometimes carries closing tags such as [/b/] */
    if (t->closing && i + 1 < length && s[i] == '/' && s[i + 1] == ']') { t->next = i + 2; return 1; }
    if (i < length && s[i] == ']') { t->next = i + 1; return 1; }
    if (t->closing || i >= length || (s[i] != '=' && s[i] != ' ')) return 0;
    i++;
    arg_start = i;
    /* the argument may hold quoted text and nested tags, as in [spoiler=[b]title[/b]] */
    for (; i < length && i - arg_start < 1024; i++) {
        char c = s[i];
        if (c == '"') quoted = !quoted;
        else if (quoted) continue;
        else if (c == '[') depth++;
        else if (c == ']') {
            if (!depth) break;
            depth--;
        }
    }
    if (i >= length || s[i] != ']') return 0;
    t->arg_start = arg_start;
    t->arg_length = i - arg_start;
    if (t->arg_length >= 2 && s[t->arg_start] == '"' && s[t->arg_start + t->arg_length - 1] == '"' &&
        memchr(s + t->arg_start + 1, '"', t->arg_length - 2) == NULL) {
        t->arg_start++;
        t->arg_length -= 2;
    }
    t->next = i + 1;
    return 1;
}

/* position of the literal closing tag of a raw tag, or length when it is missing */
static size_t find_raw_end(const char *s, size_t length, size_t from, const char *name)
{
    size_t i, n = strlen(name);
    for (i = from; i + n + 3 <= length; i++) {
        if (s[i] == '[' && s[i + 1] == '/' && name_equals(s + i + 2, n, name) && s[i + 2 + n] == ']') return i;
    }
    return length;
}

fp_bb_status fp_bb_parse(const char *source, size_t length, fp_bb_node *nodes, size_t capacity, size_t *count)
{
    out o;
    frame stack[FP_BB_DEPTH_LIMIT];
    size_t depth = 0, i = 0, text_start = 0;
    if (count) *count = 0;
    if (!source || !nodes || !count || length > FP_BB_SOURCE_LIMIT) return FP_BB_INVALID;
    o.source = source; o.length = length; o.nodes = nodes; o.capacity = capacity; o.count = 0;
#define FLUSH_TEXT(end) do { \
        if ((end) > text_start && !emit(&o, FP_BB_TEXT, FP_BB_TAG_NONE, text_start, (end) - text_start)) goto limit; \
        text_start = (end); \
    } while (0)
    while (i < length) {
        scanned t;
        if (source[i] != '[' || !scan_tag(source, length, i, &t)) { i++; continue; }
        if (!t.closing) {
            if (depth >= FP_BB_DEPTH_LIMIT && t.info->tag != FP_BB_ITEM && t.info->tag != FP_BB_BREAK) { i++; continue; }
            FLUSH_TEXT(i);
            if (t.info->tag == FP_BB_ITEM || t.info->tag == FP_BB_BREAK) {
                if (!emit(&o, FP_BB_OPEN, t.info->tag, t.arg_start, t.arg_length)) goto limit;
                i = text_start = t.next;
                continue;
            }
            if (t.info->tag == FP_BB_ATTACHMENT && attachment_reference(source + t.arg_start, t.arg_length)) {
                if (!emit(&o, FP_BB_OPEN, t.info->tag, t.arg_start, t.arg_length) ||
                    !emit(&o, FP_BB_CLOSE, t.info->tag, 0, 0)) goto limit;
                i = text_start = t.next;
                continue;
            }
            if (t.info->raw) {
                size_t end = find_raw_end(source, length, t.next, t.info->name);
                if (end == length) { i++; continue; }
                if (!emit(&o, FP_BB_OPEN, t.info->tag, t.arg_start, t.arg_length)) goto limit;
                if (end > t.next && !emit(&o, FP_BB_TEXT, FP_BB_TAG_NONE, t.next, end - t.next)) goto limit;
                if (!emit(&o, FP_BB_CLOSE, t.info->tag, 0, 0)) goto limit;
                i = text_start = end + strlen(t.info->name) + 3;
                continue;
            }
            if (!emit(&o, FP_BB_OPEN, t.info->tag, t.arg_start, t.arg_length)) goto limit;
            stack[depth].info = t.info;
            stack[depth].closed = 0;
            depth++;
            i = text_start = t.next;
        } else {
            size_t level = depth;
            while (level > 0 && stack[level - 1].info->tag != t.info->tag) level--;
            /* a closer without an opener is dropped: a mis-nested closer ends its parents too, and its own pair then shows up as literal [/b][/color] */
            if (level == 0 || t.info->tag == FP_BB_ITEM || t.info->tag == FP_BB_BREAK) {
                FLUSH_TEXT(i);
                i = text_start = t.next;
                continue;
            }
            FLUSH_TEXT(i);
            while (depth >= level) {
                if (!emit(&o, FP_BB_CLOSE, stack[depth - 1].info->tag, 0, 0)) goto limit;
                depth--;
            }
            i = text_start = t.next;
        }
    }
    FLUSH_TEXT(length);
    while (depth > 0) {
        if (!emit(&o, FP_BB_CLOSE, stack[depth - 1].info->tag, 0, 0)) goto limit;
        depth--;
    }
#undef FLUSH_TEXT
    *count = o.count;
    return FP_BB_OK;
limit:
    *count = o.count;
    return FP_BB_LIMIT;
}

int fp_bb_attribute(const char *arg, size_t length, const char *name, size_t *start, size_t *value_length)
{
    size_t n = strlen(name), i = 0;
    while (i + n < length) {
        int boundary = i == 0 || arg[i - 1] == ' ';
        if (boundary && i + n < length && arg[i + n] == '=') {
            size_t k;
            for (k = 0; k < n && lower(arg[i + k]) == name[k]; k++) {}
            if (k == n) {
                size_t v = i + n + 1, e;
                if (v < length && arg[v] == '"') {
                    v++;
                    for (e = v; e < length && arg[e] != '"'; e++) {}
                } else {
                    for (e = v; e < length && arg[e] != ' '; e++) {}
                }
                *start = v;
                *value_length = e - v;
                return 1;
            }
        }
        i++;
    }
    return 0;
}

static const struct { const char *name; uint32_t rgb; } colors[] = {
    {"black", 0x000000}, {"white", 0xFFFFFF}, {"red", 0xFF0000}, {"green", 0x008000}, {"blue", 0x0000FF},
    {"yellow", 0xFFFF00}, {"orange", 0xFFA500}, {"purple", 0x800080}, {"gray", 0x808080}, {"grey", 0x808080},
    {"silver", 0xC0C0C0}, {"maroon", 0x800000}, {"olive", 0x808000}, {"lime", 0x00FF00}, {"aqua", 0x00FFFF},
    {"cyan", 0x00FFFF}, {"teal", 0x008080}, {"navy", 0x000080}, {"fuchsia", 0xFF00FF}, {"magenta", 0xFF00FF},
    {"pink", 0xFFC0CB}, {"brown", 0xA52A2A}, {"gold", 0xFFD700}, {"indigo", 0x4B0082}, {"violet", 0xEE82EE},
    {"royalblue", 0x4169E1}, {"limegreen", 0x32CD32}, {"darkred", 0x8B0000}, {"darkgreen", 0x006400},
    {"darkblue", 0x00008B}, {"darkorange", 0xFF8C00}, {"darkcyan", 0x008B8B}, {"darkgray", 0xA9A9A9},
    {"darkgrey", 0xA9A9A9}, {"lightgray", 0xD3D3D3}, {"lightgrey", 0xD3D3D3}, {"lightblue", 0xADD8E6},
    {"lightgreen", 0x90EE90}, {"skyblue", 0x87CEEB}, {"steelblue", 0x4682B4}, {"dodgerblue", 0x1E90FF},
    {"deepskyblue", 0x00BFFF}, {"slateblue", 0x6A5ACD}, {"slategray", 0x708090}, {"orangered", 0xFF4500},
    {"crimson", 0xDC143C}, {"firebrick", 0xB22222}, {"tomato", 0xFF6347}, {"coral", 0xFF7F50},
    {"seagreen", 0x2E8B57}, {"forestgreen", 0x228B22}, {"olivedrab", 0x6B8E23}, {"chocolate", 0xD2691E},
    {"sienna", 0xA0522D}, {"peru", 0xCD853F}, {"tan", 0xD2B48C}, {"khaki", 0xF0E68C}, {"salmon", 0xFA8072},
    {"orchid", 0xDA70D6}, {"plum", 0xDDA0DD}, {"hotpink", 0xFF69B4}, {"deeppink", 0xFF1493}, {"turquoise", 0x40E0D0},
    {"midnightblue", 0x191970}, {"mediumblue", 0x0000CD}, {"blueviolet", 0x8A2BE2}, {"darkviolet", 0x9400D3},
    {"darkmagenta", 0x8B008B}, {"mediumpurple", 0x9370DB}, {"springgreen", 0x00FF7F}, {"chartreuse", 0x7FFF00},
    {"greenyellow", 0xADFF2F}, {"yellowgreen", 0x9ACD32}, {"goldenrod", 0xDAA520}, {"darkkhaki", 0xBDB76B},
    {"beige", 0xF5F5DC}, {"ivory", 0xFFFFF0}, {"lavender", 0xE6E6FA}, {"snow", 0xFFFAFA}, {"cadetblue", 0x5F9EA0},
    {"darkslategray", 0x2F4F4F}, {"dimgray", 0x696969}, {"gainsboro", 0xDCDCDC},
};

int fp_bb_color(const char *arg, size_t length, uint32_t *rgb)
{
    size_t i;
    if (!arg || !rgb || !length || length > 32) return 0;
    if (arg[0] == '#' || (length == 6 || length == 3)) {
        uint32_t v = 0;
        size_t start = arg[0] == '#' ? 1 : 0, digits = length - start;
        int ok = digits == 3 || digits == 6;
        for (i = start; ok && i < length; i++) {
            char c = lower(arg[i]);
            int d = (c >= '0' && c <= '9') ? c - '0' : (c >= 'a' && c <= 'f') ? c - 'a' + 10 : -1;
            if (d < 0) ok = 0;
            else v = (v << 4) | (uint32_t)d;
        }
        if (ok) {
            if (digits == 3) v = ((v & 0xF00) << 12) | ((v & 0xF00) << 8) | ((v & 0x0F0) << 8) | ((v & 0x0F0) << 4) | ((v & 0x00F) << 4) | (v & 0x00F);
            *rgb = v;
            return 1;
        }
        if (arg[0] == '#') return 0;
    }
    for (i = 0; i < sizeof(colors) / sizeof(colors[0]); i++) {
        if (name_equals(arg, length, colors[i].name)) { *rgb = colors[i].rgb; return 1; }
    }
    return 0;
}

size_t fp_bb_strip(const char *source, size_t length, char *output, size_t capacity)
{
    size_t i = 0, pos = 0;
    if (!output || !capacity) return 0;
    while (i < length && pos + 1 < capacity) {
        scanned t;
        if (source[i] == '[' && scan_tag(source, length, i, &t)) { i = t.next; continue; }
        output[pos++] = source[i++];
    }
    output[pos] = 0;
    return pos;
}
