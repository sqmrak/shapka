#import "FPModels.h"
#include "fp_forum.h"

NSString *const FPModelErrorDomain = @"com.pageflip.shapka.model";

@implementation FPForumEntry
@synthesize forumId = _forumId, title = _title, flags = _flags, url = _url;
- (BOOL)isCategory { return (_flags & FP_FORUM_ENTRY_CATEGORY) != 0; }
- (BOOL)hasUnread { return (_flags & FP_FORUM_ENTRY_UNREAD) != 0; }
- (void)dealloc { [_title release]; [_url release]; [super dealloc]; }
@end

@implementation FPTopicEntry
@synthesize topicId = _topicId, title = _title, summary = _summary, flags = _flags, posts = _posts, date = _date;
@synthesize lastUser = _lastUser, titleHeight = _titleHeight, heightWidth = _heightWidth;
- (void)dealloc { [_title release]; [_summary release]; [_lastUser release]; [super dealloc]; }
@end

@implementation FPForumPage
@synthesize forumId = _forumId, title = _title, subforums = _subforums, pinned = _pinned, topics = _topics, topicTotal = _topicTotal;
- (void)dealloc { [_title release]; [_subforums release]; [_pinned release]; [_topics release]; [super dealloc]; }
@end

@implementation FPAttachment
@synthesize attachmentId = _attachmentId, image = _image, name = _name, size = _size, url = _url, width = _width, height = _height;
- (void)dealloc { [_name release]; [_url release]; [super dealloc]; }
@end

@implementation FPPost
@synthesize postId = _postId, flags = _flags, userId = _userId, userName = _userName, group = _group, lastSeen = _lastSeen;
@synthesize reputation = _reputation, date = _date, body = _body, avatar = _avatar, signature = _signature;
@synthesize attachments = _attachments, editDate = _editDate, editor = _editor, editReason = _editReason, voteWord = _voteWord;
- (BOOL)isHeader { return (_flags & FP_POST_HEADER) != 0; }
- (BOOL)hasRating { return (_voteWord & FP_POST_VOTE_SHOWN) != 0; }
- (NSInteger)rating { return fp_post_vote_score((int32_t)_voteWord); }
- (BOOL)canBeRated { return [self hasRating] && !(_voteWord & FP_POST_VOTE_DONE); }
- (void)dealloc
{
    [_userName release]; [_body release]; [_avatar release]; [_signature release];
    [_attachments release]; [_editor release]; [_editReason release];
    [super dealloc];
}
@end

@implementation FPTopicPage
@synthesize topicId = _topicId, title = _title, summary = _summary, flags = _flags, postTotal = _postTotal, posts = _posts;
- (void)dealloc { [_title release]; [_summary release]; [_posts release]; [super dealloc]; }
@end

@implementation FPFavoritesPage
@synthesize total = _total, entries = _entries, topics = _topics;
- (void)dealloc { [_topics release]; [super dealloc]; }
@end

static NSString *FPString(fp_span span, BOOL entities)
{
    size_t capacity, written = 0;
    char *buffer;
    NSString *string;
    if (!span.length) return @"";
    capacity = FP_TEXT_UTF8_BOUND(span.length);
    buffer = (char *)malloc(capacity);
    if (!buffer) return @"";
    if (fp_text_decode(span, buffer, capacity, &written) == FP_TEXT_INVALID) {
        free(buffer);
        return @"";
    }
    if (entities) written = fp_text_unescape_entities(buffer, written, buffer, written + 1);
    string = [[[NSString alloc] initWithBytes:buffer length:written encoding:NSUTF8StringEncoding] autorelease];
    free(buffer);
    return string ? string : @"";
}

static NSError *FPModelError(fp_forum_status status)
{
    NSString *text = status == FP_FORUM_SERVER ? @"Сервер отклонил запрос" : @"Некорректный ответ сервера";
    return [NSError errorWithDomain:FPModelErrorDomain code:status
                           userInfo:[NSDictionary dictionaryWithObject:text forKey:NSLocalizedDescriptionKey]];
}

static NSArray *FPEntries(const fp_forum_entry *items, size_t count)
{
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:count];
    size_t i;
    for (i = 0; i < count; i++) {
        FPForumEntry *entry = [[FPForumEntry alloc] init];
        entry.forumId = items[i].id;
        entry.title = FPString(items[i].title, YES);
        entry.flags = items[i].flags;
        entry.url = FPString(items[i].url, YES);
        [list addObject:entry];
        [entry release];
    }
    return list;
}

NSArray *FPParseForumIndex(NSData *reply, NSError **error)
{
    fp_forum_index index;
    fp_forum_status status = fp_forum_parse_index([reply bytes], [reply length], &index);
    NSArray *list;
    if (status != FP_FORUM_OK) {
        if (error) *error = FPModelError(status);
        return nil;
    }
    list = FPEntries(index.entries, index.count);
    fp_forum_index_free(&index);
    return list;
}

FPForumPage *FPParseForumPage(NSData *reply, NSError **error)
{
    fp_forum_page page;
    fp_forum_status status = fp_forum_parse_page([reply bytes], [reply length], &page);
    FPForumPage *result;
    NSMutableArray *topics;
    size_t i;
    if (status != FP_FORUM_OK) {
        if (error) *error = FPModelError(status);
        return nil;
    }
    result = [[[FPForumPage alloc] init] autorelease];
    result.forumId = page.id;
    result.title = FPString(page.title, YES);
    result.topicTotal = page.topic_total;
    result.subforums = FPEntries(page.subforums, page.subforum_count);
    result.pinned = FPEntries(page.pinned, page.pinned_count);
    topics = [NSMutableArray arrayWithCapacity:page.topic_count];
    for (i = 0; i < page.topic_count; i++) {
        FPTopicEntry *topic = [[FPTopicEntry alloc] init];
        topic.topicId = page.topics[i].id;
        topic.title = FPString(page.topics[i].title, YES);
        topic.summary = FPString(page.topics[i].description, YES);
        topic.flags = page.topics[i].flags;
        topic.posts = page.topics[i].posts;
        topic.date = page.topics[i].date;
        topic.lastUser = FPString(page.topics[i].last_user, YES);
        [topics addObject:topic];
        [topic release];
    }
    result.topics = topics;
    fp_forum_page_free(&page);
    return result;
}

FPTopicPage *FPParseTopicPage(NSData *reply, NSError **error)
{
    fp_topic_page page;
    fp_forum_status status = fp_forum_parse_topic([reply bytes], [reply length], &page);
    FPTopicPage *result;
    NSMutableArray *posts;
    size_t i, k;
    if (status != FP_FORUM_OK) {
        if (error) *error = FPModelError(status);
        return nil;
    }
    result = [[[FPTopicPage alloc] init] autorelease];
    result.topicId = page.id;
    result.title = FPString(page.title, YES);
    result.summary = FPString(page.description, YES);
    result.flags = page.flags;
    result.postTotal = page.post_total;
    posts = [NSMutableArray arrayWithCapacity:page.post_count];
    for (i = 0; i < page.post_count; i++) {
        const fp_post *source = &page.posts[i];
        FPPost *post = [[FPPost alloc] init];
        NSMutableArray *files = [NSMutableArray arrayWithCapacity:source->attachment_count];
        post.postId = source->id;
        post.flags = source->flags;
        post.userId = source->user_id;
        post.userName = FPString(source->user_name, YES);
        post.group = source->group;
        post.lastSeen = source->last_seen;
        post.reputation = source->reputation;
        post.date = source->date;
        post.body = FPString(source->body, NO);
        post.avatar = FPString(source->avatar, YES);
        post.signature = FPString(source->signature, NO);
        post.voteWord = source->vote_word;
        post.editDate = source->edit_date;
        post.editor = FPString(source->editor, YES);
        post.editReason = FPString(source->edit_reason, YES);
        for (k = 0; k < source->attachment_count; k++) {
            const fp_attachment *a = &page.attachments[source->attachment_first + k];
            FPAttachment *file = [[FPAttachment alloc] init];
            file.attachmentId = a->id;
            file.image = a->kind == 1;
            file.name = FPString(a->name, YES);
            file.size = a->size;
            file.url = FPString(a->url, YES);
            file.width = a->width;
            file.height = a->height;
            [files addObject:file];
            [file release];
        }
        post.attachments = files;
        [posts addObject:post];
        [post release];
    }
    result.posts = posts;
    fp_topic_page_free(&page);
    return result;
}

FPFavoritesPage *FPParseFavorites(NSData *reply, NSError **error)
{
    fp_favorites_page page;
    fp_forum_status status = fp_forum_parse_favorites([reply bytes], [reply length], &page);
    FPFavoritesPage *result;
    NSMutableArray *topics;
    size_t i;
    if (status != FP_FORUM_OK) {
        if (error) *error = FPModelError(status);
        return nil;
    }
    result = [[[FPFavoritesPage alloc] init] autorelease];
    result.total = page.total;
    result.entries = page.count;
    topics = [NSMutableArray arrayWithCapacity:page.count];
    for (i = 0; i < page.count; i++) {
        FPTopicEntry *topic;
        if (page.entries[i].kind != FP_FAVORITE_TOPIC || page.entries[i].id <= 0) continue;
        topic = [[FPTopicEntry alloc] init];
        topic.topicId = page.entries[i].id;
        topic.title = FPString(page.entries[i].title, YES);
        topic.flags = page.entries[i].flags;
        [topics addObject:topic];
        [topic release];
    }
    result.topics = topics;
    fp_favorites_page_free(&page);
    return result;
}

NSArray *FPParseVotes(NSData *reply, NSError **error)
{
    fp_vote_page page;
    fp_forum_status status = fp_forum_parse_votes([reply bytes], [reply length], &page);
    NSMutableArray *votes;
    size_t i;
    if (status != FP_FORUM_OK) {
        if (error) *error = FPModelError(status);
        return nil;
    }
    votes = [NSMutableArray arrayWithCapacity:page.count];
    for (i = 0; i < page.count; i++) {
        [votes addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:page.entries[i].member], @"member",
            FPString(page.entries[i].name, YES), @"name",
            [NSNumber numberWithInt:page.entries[i].value], @"value",
            [NSNumber numberWithLongLong:page.entries[i].time], @"time", nil]];
    }
    fp_vote_page_free(&page);
    return votes;
}
