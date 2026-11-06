#include "fp_news_body.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    const char *body = "First [b]line[/b]\n\n[center][attachment=\"1:dummy\"][/center]\n\nSecond";
    fp_news_attachment image = {1, "https://4pda.to/static/news.jpg", 480, 254};
    fp_article article;
    assert(fp_news_body_parse(body, strlen(body), &image, 1, &article) == FP_ARTICLE_OK);
    assert(article.count == 3);
    assert(!strcmp(fp_article_text(&article, 0), "First line"));
    assert(article.blocks[1].kind == FP_ARTICLE_IMAGE && article.blocks[1].width == 480 && article.blocks[1].height == 254);
    assert(!strcmp(fp_article_text(&article, 1), image.url));
    assert(!strcmp(fp_article_text(&article, 2), "Second"));
    fp_article_free(&article);
    assert(fp_news_body_parse(body, strlen(body), NULL, 0, &article) == FP_ARTICLE_PARTIAL);
    assert(article.count == 2);
    fp_article_free(&article);
    body = "before [youtube=s96XAFQ9IMo:640:360::0] after";
    assert(fp_news_body_parse(body, strlen(body), NULL, 0, &article) == FP_ARTICLE_OK);
    assert(article.count == 3 && article.blocks[1].kind == FP_ARTICLE_VIDEO);
    assert(!strcmp(fp_article_text(&article, 1), "https://www.youtube.com/watch?v=s96XAFQ9IMo"));
    assert(!strcmp(fp_article_text(&article, 2), "after"));
    fp_article_free(&article);
    body = "[youtube=s96XAFQ9IMo][youtube=s96XAFQ9IMo:1]";
    assert(fp_news_body_parse(body, strlen(body), NULL, 0, &article) == FP_ARTICLE_OK);
    assert(article.count == 2 && article.blocks[0].kind == FP_ARTICLE_VIDEO && article.blocks[1].kind == FP_ARTICLE_VIDEO);
    fp_article_free(&article);
    body = "[youtube=s96XAFQ9IMo:640";
    assert(fp_news_body_parse(body, strlen(body), NULL, 0, &article) == FP_ARTICLE_OK);
    assert(article.count == 1 && !strcmp(fp_article_text(&article, 0), body));
    fp_article_free(&article);
    body = "[youtube=bad:640:360::0]";
    assert(fp_news_body_parse(body, strlen(body), NULL, 0, &article) == FP_ARTICLE_OK);
    assert(article.count == 1 && !strcmp(fp_article_text(&article, 0), body));
    fp_article_free(&article);
    assert(fp_news_body_parse(NULL, 0, NULL, 0, &article) == FP_ARTICLE_ARGUMENT && !article.text);
    assert(fp_news_body_parse(body, strlen(body), NULL, 1, &article) == FP_ARTICLE_ARGUMENT && !article.text);
    puts("news body tests passed");
    return 0;
}
