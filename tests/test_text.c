#include "fp_text.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static fp_text_status decode(const uint8_t *s, size_t n, char *out, size_t cap, size_t *w)
{
    fp_span span;
    span.data = s;
    span.length = n;
    return fp_text_decode(span, out, cap, w);
}

#define DECODE(literal, out, cap, w) decode((const uint8_t *)(literal), sizeof(literal) - 1, out, cap, w)

int main(void)
{
    char out[64];
    size_t w;
    /* windows-1251 "Привет" */
    const uint8_t privet[] = {0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2};
    const uint8_t edge[] = {0x80, 0xA8, 0xB8, 0xC0, 0xFF, 0x98};

    assert(decode(privet, sizeof(privet), out, sizeof(out), &w) == FP_TEXT_OK);
    assert(w == 12 && strcmp(out, "\xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82") == 0);
    assert(decode(edge, sizeof(edge), out, sizeof(out), &w) == FP_TEXT_OK);
    assert(strcmp(out, "\xD0\x82\xD0\x81\xD1\x91\xD0\x90\xD1\x8F\xEF\xBF\xBD") == 0);

    assert(DECODE("a\\n\\\"b\\\\\\t", out, sizeof(out), &w) == FP_TEXT_OK && strcmp(out, "a\n\"b\\\t") == 0);
    assert(DECODE("\\u0401\\u20ac", out, sizeof(out), &w) == FP_TEXT_OK && strcmp(out, "\xD0\x81\xE2\x82\xAC") == 0);
    /* a surrogate pair is one astral character, a lone surrogate becomes the replacement character */
    assert(DECODE("\\ud83d\\ude00", out, sizeof(out), &w) == FP_TEXT_OK && strcmp(out, "\xF0\x9F\x98\x80") == 0);
    assert(DECODE("\\ud83dx", out, sizeof(out), &w) == FP_TEXT_OK && strcmp(out, "\xEF\xBF\xBD" "x") == 0);
    assert(DECODE("\\ude00", out, sizeof(out), &w) == FP_TEXT_OK && strcmp(out, "\xEF\xBF\xBD") == 0);

    assert(DECODE("abc\\", out, sizeof(out), &w) == FP_TEXT_INVALID);
    assert(DECODE("\\u12", out, sizeof(out), &w) == FP_TEXT_INVALID);
    assert(DECODE("\\u12zz", out, sizeof(out), &w) == FP_TEXT_INVALID);
    assert(DECODE("\\q", out, sizeof(out), &w) == FP_TEXT_INVALID);

    /* a cut never splits a character and the output stays terminated */
    assert(decode(privet, sizeof(privet), out, 6, &w) == FP_TEXT_LIMIT && w == 4 && out[4] == 0);
    assert(decode(privet, sizeof(privet), out, 1, &w) == FP_TEXT_LIMIT && w == 0 && out[0] == 0);
    assert(DECODE("", out, sizeof(out), &w) == FP_TEXT_OK && w == 0 && out[0] == 0);
    assert(decode(privet, sizeof(privet), NULL, 8, &w) == FP_TEXT_INVALID);

    w = fp_text_unescape_entities("a &amp; b &lt;&gt; &#039;x&#039; &#x41; &quot;", strlen("a &amp; b &lt;&gt; &#039;x&#039; &#x41; &quot;"), out, sizeof(out));
    assert(strcmp(out, "a & b <> 'x' A \"") == 0 && w == strlen(out));
    w = fp_text_unescape_entities("&#91;b&#93; &unknown; &#; &#xZZ; &#1114112; &#55296; &amp", strlen("&#91;b&#93; &unknown; &#; &#xZZ; &#1114112; &#55296; &amp"), out, sizeof(out));
    assert(strcmp(out, "[b] &unknown; &#; &#xZZ; &#1114112; &#55296; &amp") == 0);
    w = fp_text_unescape_entities("&#128512;", strlen("&#128512;"), out, sizeof(out));
    assert(strcmp(out, "\xF0\x9F\x98\x80") == 0);
    w = fp_text_unescape_entities("&amp;&amp;&amp;", strlen("&amp;&amp;&amp;"), out, 3);
    assert(w == 2 && strcmp(out, "&&") == 0);
    puts("text tests passed");
    return 0;
}
