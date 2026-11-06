#import "FPNewsProtocol.h"
#import "FPProtocolDocument.h"
#include "fp_news_body.h"
#include "fp_news_article.h"
#include <stdlib.h>

static BOOL FPNewsField(NSArray *row, NSUInteger index, Class type)
{
    return index < [row count] && [[row objectAtIndex:index] isKindOfClass:type];
}

NSArray *FPParseNewsFeed(NSData *data)
{
    NSArray *document = FPProtocolDocument(data);
    if ([document count] < 4 || !FPNewsField(document, 3, [NSArray class])) return nil;
    NSArray *rows = [document objectAtIndex:3];
    if ([rows count] > 30) return nil;
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:[rows count]];
    for (id row in rows) {
        if (![row isKindOfClass:[NSArray class]] || !FPNewsField(row, 0, [NSNumber class]) ||
            !FPNewsField(row, 8, [NSString class]) || !FPNewsField(row, 9, [NSString class]) ||
            !FPNewsField(row, 10, [NSString class])) return nil;
        long long identifier = [[row objectAtIndex:0] longLongValue];
        NSString *title = [row objectAtIndex:9], *summary = [row objectAtIndex:10], *image = [row objectAtIndex:8];
        if (identifier <= 0 || identifier > INT32_MAX || ![title length] || [title length] > 512 || [summary length] > 8192 || [image length] > 2048) return nil;
        if ([summary length] > 4096) summary = [summary substringToIndex:4096];
        NSString *url = [NSString stringWithFormat:@"https://4pda.to/?p=%ld", (long)identifier];
        [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:identifier], @"news_id", title, @"title", summary, @"summary", url, @"url", image, @"image", nil]];
    }
    return items;
}

NSArray *FPParseNewsArticle(NSData *data, NSInteger articleId)
{
    NSArray *doc = FPProtocolDocument(data);
    if ([doc count] < 14 || !FPNewsField(doc, 2, [NSNumber class]) || [[doc objectAtIndex:2] integerValue] != articleId ||
        !FPNewsField(doc, 12, [NSString class]) || !FPNewsField(doc, 13, [NSArray class])) return nil;
    NSData *utf8 = [[doc objectAtIndex:12] dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *rows = [doc objectAtIndex:13];
    if ([rows count] > 256) return nil;
    fp_news_attachment *attachments = calloc(MAX([rows count], 1), sizeof(*attachments));
    if (!attachments) return nil;
    NSUInteger index = 0;
    for (id row in rows) {
        if (![row isKindOfClass:[NSArray class]] || !FPNewsField(row, 0, [NSNumber class]) || !FPNewsField(row, 1, [NSString class]) ||
            !FPNewsField(row, 2, [NSNumber class]) || !FPNewsField(row, 3, [NSNumber class])) { free(attachments); return nil; }
        long long identifier = [[row objectAtIndex:0] longLongValue];
        long long width = [[row objectAtIndex:2] longLongValue], height = [[row objectAtIndex:3] longLongValue];
        if (identifier <= 0 || identifier > INT32_MAX || width < 0 || width > UINT16_MAX || height < 0 || height > UINT16_MAX || [[row objectAtIndex:1] length] > FP_ARTICLE_URL_MAX) { free(attachments); return nil; }
        attachments[index].id = (int32_t)identifier;
        attachments[index].url = [[row objectAtIndex:1] UTF8String];
        attachments[index].width = (uint16_t)width;
        attachments[index].height = (uint16_t)height;
        index++;
    }
    fp_article article;
    fp_article_status status = fp_news_body_parse([utf8 bytes], [utf8 length], attachments, [rows count], &article);
    free(attachments);
    if (status != FP_ARTICLE_OK && status != FP_ARTICLE_PARTIAL) return nil;
    NSMutableArray *blocks = [NSMutableArray arrayWithCapacity:article.count + 1];
    for (size_t i = 0; i < article.count; i++) {
        NSString *text = [NSString stringWithUTF8String:fp_article_text(&article, i)];
        if (!text) { fp_article_free(&article); return nil; }
        [blocks addObject:[NSDictionary dictionaryWithObjectsAndKeys:@(article.blocks[i].kind), @"kind", text, @"text",
                           @(article.blocks[i].width), @"width", @(article.blocks[i].height), @"height", nil]];
    }
    fp_article_free(&article);
    if (status == FP_ARTICLE_PARTIAL) [blocks addObject:[NSDictionary dictionaryWithObjectsAndKeys:@(FP_ARTICLE_PARAGRAPH), @"kind",
        @"Статья показана не полностью, остальное можно прочитать в браузере.", @"text", @0, @"width", @0, @"height", nil]];
    return [blocks count] ? blocks : nil;
}
