#import "FPFavorites.h"
#import "FPModels.h"
#include <stdint.h>

NSString *const FPFavoritesChangedNotification = @"FPFavoritesChanged";
static NSString *const FPFavoriteNewsKey = @"favorite_news_v1";
static NSString *const FPFavoriteGuestTopicsKey = @"favorite_topics_v1";
#define FP_FAVORITES_LIMIT 500

static NSInteger FPFavoritesMember = 0;

static NSString *FPFavoriteTopicsKey(void)
{
    return FPFavoritesMember > 0 ? [NSString stringWithFormat:@"favorite_topics_member%ld_v1", (long)FPFavoritesMember] : FPFavoriteGuestTopicsKey;
}

@implementation FPFavorites
+ (void)setMember:(NSInteger)member
{
    if (member < 0) member = 0;
    if (member == FPFavoritesMember) return;
    FPFavoritesMember = member;
    [[NSNotificationCenter defaultCenter] postNotificationName:FPFavoritesChangedNotification object:nil];
}

+ (NSInteger)member { return FPFavoritesMember; }

+ (void)replaceTopics:(NSArray *)entries
{
    NSMutableArray *items = [NSMutableArray arrayWithCapacity:[entries count]];
    for (FPTopicEntry *topic in entries) {
        if (topic.topicId <= 0 || ![topic.title length] || [topic.title length] > 512) continue;
        [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:topic.topicId], @"id", topic.title, @"title", nil]];
        if ([items count] == FP_FAVORITES_LIMIT) break;
    }
    [[NSUserDefaults standardUserDefaults] setObject:items forKey:FPFavoriteTopicsKey()];
    [[NSNotificationCenter defaultCenter] postNotificationName:FPFavoritesChangedNotification object:nil];
}

+ (NSArray *)topics
{
    id saved = [[NSUserDefaults standardUserDefaults] objectForKey:FPFavoriteTopicsKey()];
    NSMutableArray *items = [NSMutableArray array];
    if (![saved isKindOfClass:[NSArray class]]) return items;
    for (id entry in saved) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        id identifier = [entry objectForKey:@"id"], title = [entry objectForKey:@"title"];
        if (![identifier isKindOfClass:[NSNumber class]] || [identifier integerValue] <= 0 ||
            ![title isKindOfClass:[NSString class]] || ![title length] || [title length] > 512) continue;
        [items addObject:[NSDictionary dictionaryWithObjectsAndKeys:identifier, @"id", title, @"title", nil]];
        if ([items count] == FP_FAVORITES_LIMIT) break;
    }
    return items;
}

+ (NSArray *)news
{
    id saved = [[NSUserDefaults standardUserDefaults] objectForKey:FPFavoriteNewsKey];
    NSMutableArray *items = [NSMutableArray array];
    if (![saved isKindOfClass:[NSArray class]]) return items;
    for (id entry in saved) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        id title = [entry objectForKey:@"title"], url = [entry objectForKey:@"url"], summary = [entry objectForKey:@"summary"];
        if (![title isKindOfClass:[NSString class]] || ![title length] || [title length] > 512 ||
            ![url isKindOfClass:[NSString class]] || [url length] > 2048 ||
            ![summary isKindOfClass:[NSString class]] || [summary length] > 4096) continue;
        NSURL *parsed = [NSURL URLWithString:url];
        if (![[[parsed scheme] lowercaseString] isEqualToString:@"https"] || ![[[parsed host] lowercaseString] isEqualToString:@"4pda.to"]) continue;
        NSMutableDictionary *item = [NSMutableDictionary dictionaryWithObjectsAndKeys:title, @"title", url, @"url", summary, @"summary", nil];
        id newsId = [entry objectForKey:@"news_id"], image = [entry objectForKey:@"image"];
        if ([newsId isKindOfClass:[NSNumber class]] && [newsId longLongValue] > 0 && [newsId longLongValue] <= INT32_MAX) [item setObject:newsId forKey:@"news_id"];
        if ([image isKindOfClass:[NSString class]] && [image length] <= 2048) [item setObject:image forKey:@"image"];
        [items addObject:item];
        if ([items count] == FP_FAVORITES_LIMIT) break;
    }
    return items;
}

+ (BOOL)containsNews:(NSString *)url
{
    for (NSDictionary *item in [self news]) if ([[item objectForKey:@"url"] isEqualToString:url]) return YES;
    return NO;
}

+ (BOOL)addNews:(NSDictionary *)item
{
    NSString *title = [item objectForKey:@"title"], *url = [item objectForKey:@"url"], *summary = [item objectForKey:@"summary"];
    if (![url isKindOfClass:[NSString class]]) return NO;
    NSURL *parsed = [NSURL URLWithString:url];
    if (![title isKindOfClass:[NSString class]] || ![title length] || [title length] > 512 ||
        ![url isKindOfClass:[NSString class]] || [url length] > 2048 ||
        ![summary isKindOfClass:[NSString class]] || [summary length] > 4096 ||
        ![[[parsed scheme] lowercaseString] isEqualToString:@"https"] || ![[[parsed host] lowercaseString] isEqualToString:@"4pda.to"]) return NO;
    NSMutableArray *items = [NSMutableArray arrayWithArray:[self news]];
    if ([self containsNews:url]) return YES;
    if ([items count] >= FP_FAVORITES_LIMIT) return NO;
    NSMutableDictionary *saved = [NSMutableDictionary dictionaryWithObjectsAndKeys:title, @"title", url, @"url", summary, @"summary", nil];
    id newsId = [item objectForKey:@"news_id"], image = [item objectForKey:@"image"];
    if ([newsId isKindOfClass:[NSNumber class]] && [newsId longLongValue] > 0 && [newsId longLongValue] <= INT32_MAX) [saved setObject:newsId forKey:@"news_id"];
    if ([image isKindOfClass:[NSString class]] && [image length] <= 2048) [saved setObject:image forKey:@"image"];
    [items insertObject:saved atIndex:0];
    [[NSUserDefaults standardUserDefaults] setObject:items forKey:FPFavoriteNewsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:FPFavoritesChangedNotification object:nil];
    return YES;
}

+ (void)removeNews:(NSString *)url
{
    NSMutableArray *items = [NSMutableArray arrayWithArray:[self news]];
    for (NSInteger i = (NSInteger)[items count] - 1; i >= 0; i--)
        if ([[[items objectAtIndex:(NSUInteger)i] objectForKey:@"url"] isEqualToString:url]) [items removeObjectAtIndex:(NSUInteger)i];
    [[NSUserDefaults standardUserDefaults] setObject:items forKey:FPFavoriteNewsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:FPFavoritesChangedNotification object:nil];
}

+ (BOOL)containsTopic:(NSInteger)topicId
{
    for (NSDictionary *entry in [self topics]) if ([[entry objectForKey:@"id"] integerValue] == topicId) return YES;
    return NO;
}

+ (BOOL)addTopic:(NSInteger)topicId title:(NSString *)title
{
    NSMutableArray *items = [NSMutableArray arrayWithArray:[self topics]];
    if (topicId <= 0 || ![title length] || [title length] > 512 || [items count] >= FP_FAVORITES_LIMIT) return NO;
    if ([self containsTopic:topicId]) return YES;
    [items insertObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:topicId], @"id", title, @"title", nil] atIndex:0];
    [[NSUserDefaults standardUserDefaults] setObject:items forKey:FPFavoriteTopicsKey()];
    [[NSNotificationCenter defaultCenter] postNotificationName:FPFavoritesChangedNotification object:nil];
    return YES;
}

+ (void)removeTopic:(NSInteger)topicId
{
    NSMutableArray *items = [NSMutableArray arrayWithArray:[self topics]];
    for (NSInteger i = (NSInteger)[items count] - 1; i >= 0; i--)
        if ([[[items objectAtIndex:(NSUInteger)i] objectForKey:@"id"] integerValue] == topicId) [items removeObjectAtIndex:(NSUInteger)i];
    [[NSUserDefaults standardUserDefaults] setObject:items forKey:FPFavoriteTopicsKey()];
    [[NSNotificationCenter defaultCenter] postNotificationName:FPFavoritesChangedNotification object:nil];
}
@end
