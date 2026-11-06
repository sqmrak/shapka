#include "fp_news_article.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static fp_article_status parse(const char *html, fp_article *a)
{
    return fp_article_parse((const uint8_t *)html, strlen(html), a);
}

#define PAGE(body) "<html><div class=\"article\">" body "<div class=\"article-footer\">x</div></div><div id=\"comments\"><p>comment</p></div></html>"

static void fixture(void)
{
    FILE *f = fopen("tests/fixtures/news_article.html", "rb");
    long size;
    uint8_t *data;
    fp_article a;
    assert(f);
    fseek(f, 0, SEEK_END);
    size = ftell(f);
    rewind(f);
    data = malloc((size_t)size);
    assert(data && fread(data, 1, (size_t)size, f) == (size_t)size);
    fclose(f);
    assert(fp_article_parse(data, (size_t)size, &a) == FP_ARTICLE_OK);
    /* the lead, then a picture, two paragraphs, a picture and so on; nothing of the comment after the footer */
    assert(a.count == 12);
    assert(a.blocks[0].kind == FP_ARTICLE_PARAGRAPH && strncmp(fp_article_text(&a, 0), "Сбер представил набор", 21) == 0);
    assert(a.blocks[1].kind == FP_ARTICLE_IMAGE && a.blocks[1].width == 480 && a.blocks[1].height == 270);
    assert(strncmp(fp_article_text(&a, 1), "https://4pda.to/s/", 18) == 0);
    assert(strchr(fp_article_text(&a, 1), ' ') == NULL);
    assert(a.blocks[11].kind == FP_ARTICLE_PARAGRAPH && strncmp(fp_article_text(&a, 11), "Все четыре инструмента", 41) == 0);
    {
        size_t i;
        for (i = 0; i < a.count; i++) assert(strstr(fp_article_text(&a, i), "comment text") == NULL);
    }
    fp_article_free(&a);
    assert(parse(PAGE("<p>[color=red][b]Текст[/b/][/color] [1] [unknown]x[/unknown]</p>"), &a) == FP_ARTICLE_OK);
    assert(a.count == 1 && strcmp(fp_article_text(&a, 0), "Текст [1] [unknown]x[/unknown]") == 0);
    fp_article_free(&a);
    assert(parse(PAGE("<p>[color=red][b]Текст[/b][/color]</p>"), &a) == FP_ARTICLE_OK);
    assert(a.count == 1 && strcmp(fp_article_text(&a, 0), "Текст") == 0);
    fp_article_free(&a);
    free(data);
}

static void blocks(void)
{
    fp_article a;
    /* a paragraph with inline markup, a break, entities and a no-break space */
    assert(parse(PAGE("<p>One <strong>two</strong>&nbsp;&nbsp;three<br />four &laquo;q&raquo; &#215; &amp; &unknown;</p>"), &a) == FP_ARTICLE_OK);
    assert(a.count == 1 && a.blocks[0].kind == FP_ARTICLE_PARAGRAPH);
    assert(strcmp(fp_article_text(&a, 0), "One two three\nfour «q» × & &unknown;") == 0);
    fp_article_free(&a);
    /* headings, list items, a definition list and a quote with two paragraphs */
    assert(parse(PAGE("<h2>Head</h2><ul><li>a</li><li>b <b>c</b></li></ul><dl><dt><strong>T</strong></dt><dd>d1<br />d2</dd></dl>"
                      "<blockquote class=\"article-blockquote\"><p>q1</p><p>q2</p></blockquote><p>after</p>"), &a) == FP_ARTICLE_OK);
    assert(a.count == 8);
    assert(a.blocks[0].kind == FP_ARTICLE_HEADING && a.blocks[1].kind == FP_ARTICLE_ITEM && a.blocks[2].kind == FP_ARTICLE_ITEM);
    assert(strcmp(fp_article_text(&a, 2), "b c") == 0);
    assert(a.blocks[3].kind == FP_ARTICLE_HEADING && a.blocks[4].kind == FP_ARTICLE_PARAGRAPH && strcmp(fp_article_text(&a, 4), "d1\nd2") == 0);
    assert(a.blocks[5].kind == FP_ARTICLE_QUOTE && a.blocks[6].kind == FP_ARTICLE_QUOTE && a.blocks[7].kind == FP_ARTICLE_PARAGRAPH);
    fp_article_free(&a);
    /* the pictures: a plain one, a protocol relative one, an emoticon that is left out, and a gallery whose preview strip is not read twice */
    assert(parse(PAGE("<figure><a href=\"https://4pda.to/s/big.png\"><img width=\"480\" height=\"270\" src=\"https://4pda.to/s/a.png\" srcset=\"https://4pda.to/s/x.png 2392w\" /></a></figure>"
                      "<p>x <img src=\"https://4pda.to/s/smile.gif\" width=\"20\" height=\"20\" /> y</p><img src=\"//4pda.to/s/b.jpg\" />"
                      "<div class=\"article-gallery\"><div class=\"article-gallery-previews\"><div class=\"article-gallery-previews-item\" style=\"background-image:url(https://4pda.to/s/p1.jpg)\"></div>"
                      "<img src=\"https://4pda.to/s/never.jpg\" width=\"400\" height=\"300\" /></div>"
                      "<div class=\"article-gallery-image\"><figure><img src=\"https://4pda.to/s/g1.jpg\" width=\"480\" height=\"300\" /></figure></div></div>"), &a) == FP_ARTICLE_OK);
    /* the emoticon leaves the sentence whole */
    assert(a.count == 4);
    assert(a.blocks[0].kind == FP_ARTICLE_IMAGE && strcmp(fp_article_text(&a, 0), "https://4pda.to/s/a.png") == 0);
    assert(a.blocks[1].kind == FP_ARTICLE_PARAGRAPH && strcmp(fp_article_text(&a, 1), "x y") == 0);
    assert(a.blocks[2].kind == FP_ARTICLE_IMAGE && strcmp(fp_article_text(&a, 2), "https://4pda.to/s/b.jpg") == 0);
    assert(a.blocks[3].kind == FP_ARTICLE_IMAGE && strcmp(fp_article_text(&a, 3), "https://4pda.to/s/g1.jpg") == 0);
    {
        size_t i, images = 0;
        for (i = 0; i < a.count; i++) {
            assert(strstr(fp_article_text(&a, i), "never.jpg") == NULL && strstr(fp_article_text(&a, i), "smile.gif") == NULL);
            if (a.blocks[i].kind == FP_ARTICLE_IMAGE) images++;
        }
        assert(images == 3);
    }
    fp_article_free(&a);
    /* a youtube preview becomes a video, an address of another site does not */
    assert(parse(PAGE("<p><a data-notrack href=\"https://www.youtube.com/watch?v=abcdEFGH123\" class=\"yt-p-overlay\" style=\"background-image:url(//4pda.to/s/t.jpg);\"><span class=\"yt-p-gradient\"></span></a></p>"
                      "<p><a href=\"https://evil.example/watch?v=1\" class=\"yt-p-overlay\"></a></p><p>text</p>"), &a) == FP_ARTICLE_OK);
    assert(a.count == 2 && a.blocks[0].kind == FP_ARTICLE_VIDEO && strcmp(fp_article_text(&a, 0), "https://www.youtube.com/watch?v=abcdEFGH123") == 0);
    fp_article_free(&a);
    /* scripts, styles, comments and drawings carry no text */
    assert(parse(PAGE("<p>a<script>var s = \"<p>no</p>\";</script><!-- <p>no</p> --><style>p{}</style><svg><p>no</p></svg>b</p>"), &a) == FP_ARTICLE_OK);
    assert(a.count == 1 && strcmp(fp_article_text(&a, 0), "ab") == 0);
    fp_article_free(&a);
}

static void bounds(void)
{
    fp_article a;
    char *big;
    size_t i, n;
    assert(fp_article_parse(NULL, 0, &a) == FP_ARTICLE_ARGUMENT);
    assert(fp_article_parse((const uint8_t *)"x", 1, NULL) == FP_ARTICLE_ARGUMENT);
    assert(parse("", &a) == FP_ARTICLE_NOTFOUND && a.count == 0 && a.text == NULL);
    assert(parse("<html><p>no article here</p></html>", &a) == FP_ARTICLE_NOTFOUND);
    /* an article block with nothing readable in it */
    assert(parse(PAGE(""), &a) == FP_ARTICLE_NOTFOUND);
    /* a page cut before the footer keeps what came and says so */
    assert(parse("<div class=\"article\"><p>first</p><p>second</p><p>thi", &a) == FP_ARTICLE_PARTIAL);
    assert(a.count == 3);
    assert(strcmp(fp_article_text(&a, 0), "first") == 0 && strcmp(fp_article_text(&a, 2), "thi") == 0);
    fp_article_free(&a);
    /* a tag that never closes is text, not a hang */
    assert(parse(PAGE("<p>a < b <img src=\"x"), &a) == FP_ARTICLE_OK);
    assert(a.count == 1 && strcmp(fp_article_text(&a, 0), "a < b <img src=\"x") == 0);
    fp_article_free(&a);
    /* more blocks than the bound: the first ones stay, the status is PARTIAL */
    n = (size_t)(FP_ARTICLE_BLOCK_MAX + 50u) * 8u + 128u;
    big = malloc(n);
    assert(big);
    strcpy(big, "<div class=\"article\">");
    for (i = 0; i < FP_ARTICLE_BLOCK_MAX + 50u; i++) strcat(big, "<p>x</p>");
    strcat(big, "<div class=\"article-footer\">");
    assert(parse(big, &a) == FP_ARTICLE_PARTIAL && a.count == FP_ARTICLE_BLOCK_MAX);
    fp_article_free(&a);
    free(big);
    /* text beyond its bound stops the reading without writing past it */
    n = FP_ARTICLE_TEXT_MAX + 4096u;
    big = malloc(n + 128u);
    assert(big);
    strcpy(big, "<div class=\"article\"><p>");
    i = strlen(big);
    memset(big + i, 'a', n);
    big[i + n] = 0;
    strcpy(big + strlen(big), "</p><div class=\"article-footer\">");
    assert(parse(big, &a) == FP_ARTICLE_PARTIAL);
    assert(a.count == 1 && a.text_length <= FP_ARTICLE_TEXT_MAX);
    fp_article_free(&a);
    free(big);
}

int main(void)
{
    fixture();
    blocks();
    bounds();
    puts("news article tests passed");
    return 0;
}
