#include "fp_bbcode.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static size_t parse(const char *s, fp_bb_node *nodes, size_t capacity, fp_bb_status *status)
{
    size_t count;
    *status = fp_bb_parse(s, strlen(s), nodes, capacity, &count);
    return count;
}

static int text_is(const char *s, const fp_bb_node *n, const char *expected)
{
    return n->kind == FP_BB_TEXT && n->length == strlen(expected) && memcmp(s + n->start, expected, n->length) == 0;
}

static int arg_is(const char *s, const fp_bb_node *n, const char *expected)
{
    return n->kind == FP_BB_OPEN && n->length == strlen(expected) && memcmp(s + n->start, expected, n->length) == 0;
}

int main(void)
{
    fp_bb_node n[128];
    fp_bb_status status;
    size_t count, start, length, i;
    uint32_t rgb;
    char text[128];
    const char *s;

    s = "Новость [color=red]текст[/color] и [/color] [unknown]";
    fp_bb_strip(s, strlen(s), text, sizeof(text));
    assert(strcmp(text, "Новость текст и  [unknown]") == 0);

    s = "a [b]bold[/b] c";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && count == 5);
    assert(text_is(s, &n[0], "a ") && n[1].kind == FP_BB_OPEN && n[1].tag == FP_BB_B);
    assert(text_is(s, &n[2], "bold") && n[3].kind == FP_BB_CLOSE && n[3].tag == FP_BB_B && text_is(s, &n[4], " c"));

    s = "[URL=\"https://4pda.to/x?a=1\"]link[/URL]";
    count = parse(s, n, 64, &status);
    assert(count == 3 && n[0].tag == FP_BB_URL && arg_is(s, &n[0], "https://4pda.to/x?a=1"));

    /* the title of a spoiler may hold tags of its own */
    s = "[spoiler=[color=royalblue]Info[/color]]body[/spoiler]";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && count == 3 && n[0].tag == FP_BB_SPOILER && arg_is(s, &n[0], "[color=royalblue]Info[/color]"));
    assert(fp_bb_strip(s + n[0].start, n[0].length, text, sizeof(text)) == 4 && strcmp(text, "Info") == 0);

    s = "[quote name=\"Denbosh\" date=\"06.12.2012, 23&#58;46\" post=17606210]q[/quote]";
    count = parse(s, n, 64, &status);
    assert(count == 3 && n[0].tag == FP_BB_QUOTE);
    assert(fp_bb_attribute(s + n[0].start, n[0].length, "name", &start, &length) && length == 7 && memcmp(s + n[0].start + start, "Denbosh", 7) == 0);
    assert(fp_bb_attribute(s + n[0].start, n[0].length, "post", &start, &length) && length == 8 && memcmp(s + n[0].start + start, "17606210", 8) == 0);
    assert(!fp_bb_attribute(s + n[0].start, n[0].length, "id", &start, &length));

    /* raw tags keep brackets inside their body */
    s = "[code][b]x[/b][/code]";
    count = parse(s, n, 64, &status);
    assert(count == 3 && n[0].tag == FP_BB_CODE && text_is(s, &n[1], "[b]x[/b]") && n[2].kind == FP_BB_CLOSE);
    s = "[img]https://a/b.png[/img]";
    count = parse(s, n, 64, &status);
    assert(count == 3 && text_is(s, &n[1], "https://a/b.png"));

    s = "before [attachment=\"36133710:10652608.png\"] after";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && count == 4);
    assert(text_is(s, &n[0], "before ") && n[1].tag == FP_BB_ATTACHMENT);
    assert(arg_is(s, &n[1], "36133710:10652608.png") && n[2].kind == FP_BB_CLOSE && text_is(s, &n[3], " after"));
    s = "[attachment]123[/attachment]";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && count == 3 && n[0].tag == FP_BB_ATTACHMENT && text_is(s, &n[1], "123"));
    s = "[attachment=\"x:file.png\"]";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && count == 1 && text_is(s, &n[0], s));

    /* list items stand alone */
    s = "[list][*]one[*]two[/list]";
    count = parse(s, n, 64, &status);
    assert(count == 6 && n[1].tag == FP_BB_ITEM && n[3].tag == FP_BB_ITEM && n[5].kind == FP_BB_CLOSE && n[5].tag == FP_BB_LIST);

    /* a closing tag closes the tags opened inside it, an unmatched one is dropped */
    s = "[b][i]x[/b]y[/i]";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && n[3].kind == FP_BB_CLOSE && n[3].tag == FP_BB_I && n[4].tag == FP_BB_B && text_is(s, &n[5], "y") && count == 6);
    s = "x[/b]";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && count == 1 && text_is(s, &n[0], "x"));
    s = "[color=red][b]Внимание![/b][/color][/b][/color] дальше";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && count == 6 && text_is(s, &n[5], " дальше"));
    s = "[b][color=red]Внимание![/b][/color]";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && count == 5 && text_is(s, &n[2], "Внимание!"));
    s = "[b]text[/b/]";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && count == 3 && n[2].kind == FP_BB_CLOSE && n[2].tag == FP_BB_B);

    /* unclosed tags are closed at the end */
    s = "[b][i]open";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && count == 5 && n[3].tag == FP_BB_I && n[4].tag == FP_BB_B);

    /* things that look like tags but are not */
    s = "[unknown]x[/unknown] [b [b=] [ ] a[1] [b";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && count >= 1 && n[0].kind == FP_BB_TEXT);
    s = "[code]never closed";
    count = parse(s, n, 64, &status);
    assert(status == FP_BB_OK && count == 1 && text_is(s, &n[0], "[code]never closed"));

    /* nesting is bounded: the deepest tags stay text */
    {
        char deep[512];
        size_t k;
        deep[0] = 0;
        for (k = 0; k < 40; k++) strcat(deep, "[b]");
        strcat(deep, "x");
        count = parse(deep, n, 128, &status);
        assert(status == FP_BB_OK && count > 0);
        {
            size_t opens = 0;
            for (i = 0; i < count; i++) if (n[i].kind == FP_BB_OPEN) opens++;
            assert(opens == FP_BB_DEPTH_LIMIT);
        }
    }

    /* capacity overflow is reported and the written nodes stay valid */
    s = "[b]a[/b][b]b[/b]";
    count = parse(s, n, 3, &status);
    assert(status == FP_BB_LIMIT && count == 3);
    assert(fp_bb_parse(NULL, 1, n, 3, &count) == FP_BB_INVALID);

    assert(fp_bb_color("royalblue", 9, &rgb) && rgb == 0x4169E1);
    assert(fp_bb_color("RED", 3, &rgb) && rgb == 0xFF0000);
    assert(fp_bb_color("#fa0", 4, &rgb) && rgb == 0xFFAA00);
    assert(fp_bb_color("#102030", 7, &rgb) && rgb == 0x102030);
    assert(fp_bb_color("102030", 6, &rgb) && rgb == 0x102030);
    assert(!fp_bb_color("#12", 3, &rgb) && !fp_bb_color("notacolor", 9, &rgb) && !fp_bb_color("#gggggg", 7, &rgb));

    assert(fp_bb_strip("a[b]b[/b][unknown]c", 19, text, 128) == 12 && strcmp(text, "ab[unknown]c") == 0);
    assert(fp_bb_strip("abcdef", 6, text, 4) == 3 && strcmp(text, "abc") == 0);
    puts("bbcode tests passed");
    return 0;
}
