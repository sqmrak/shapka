#import "FPApi.h"
#import "FPAccountStore.h"
#import "FPProtocolDocument.h"
#import "FPNewsProtocol.h"
#include "fp_forum.h"
#include "fp_text.h"
#include "fp_document.h"
#include "fp_compose.h"
#include "fp_qms.h"
#include <stdint.h>

NSString *const FPApiAccountNotification = @"FPApiAccount";

static NSString *const FPApiErrorDomain = @"com.pageflip.shapka.api";

static NSError *FPApiError(NSInteger code, NSString *text)
{
    return [NSError errorWithDomain:FPApiErrorDomain code:code
                           userInfo:[NSDictionary dictionaryWithObject:text forKey:NSLocalizedDescriptionKey]];
}

@interface FPApi ()
- (void)whenConnected:(FPApiDone)block;
- (void)failWaiters:(NSError *)error;
- (void)perform:(NSString *)operation arguments:(NSString *)arguments
          parse:(id (^)(NSData *reply, NSError **error))parse completion:(FPApiCompletion)completion;
- (void)perform:(NSString *)operation data:(NSData *)arguments
          parse:(id (^)(NSData *reply, NSError **error))parse completion:(FPApiCompletion)completion;
@end

@implementation FPApi

- (id)initWithNetwork:(FPNetwork *)network
{
    self = [super init];
    if (self) {
        _network = [network retain];
        _parseQueues[0] = dispatch_queue_create("com.pageflip.shapka.parse.0", DISPATCH_QUEUE_SERIAL);
        _parseQueues[1] = dispatch_queue_create("com.pageflip.shapka.parse.1", DISPATCH_QUEUE_SERIAL);
        _waiters = [[NSMutableArray alloc] init];
        if (!_network || !_parseQueues[0] || !_parseQueues[1]) { [self release]; return nil; }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkState:)
                                                     name:FPNetworkStateNotification object:_network];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_network disconnect];
    [_network release];
    if (_parseQueues[0]) dispatch_release(_parseQueues[0]);
    if (_parseQueues[1]) dispatch_release(_parseQueues[1]);
    [_waiters release];
    [super dealloc];
}

- (void)networkState:(NSNotification *)notification
{
    /* a lost connection is noticed here, so the next request connects again instead of using a dead socket */
    NSError *error = [[notification userInfo] objectForKey:@"error"];
    _connected = error == nil && _active;
    if (error && !_connecting) [self failWaiters:error];
}

- (void)failWaiters:(NSError *)error
{
    NSArray *waiting = [[_waiters copy] autorelease];
    [_waiters removeAllObjects];
    for (FPApiDone block in waiting) block(error);
}

- (void)resume
{
    _active = YES;
    [self whenConnected:^(NSError *error) { (void)error; }];
}

- (void)pause
{
    _active = NO;
    _connected = NO;
    _connecting = NO;
    [_network disconnect];
    [self failWaiters:FPApiError(1, @"Соединение закрыто")];
}

- (void)whenConnected:(FPApiDone)block
{
    FPApiDone copy;
    if (_connected) { block(nil); return; }
    copy = [block copy];
    [_waiters addObject:copy];
    [copy release];
    if (_connecting) return;
    _connecting = YES;
    _active = YES;
    [_network connectWithCompletion:^(NSData *document, NSInteger serverStatus, NSError *error) {
        (void)document;
        (void)serverStatus;
        _connecting = NO;
        _connected = error == nil;
        if (error) {
            [self failWaiters:error];
            return;
        }
        {
            NSArray *waiting = [[_waiters copy] autorelease];
            [_waiters removeAllObjects];
            for (FPApiDone waiter in waiting) waiter(nil);
        }
    }];
}

- (void)perform:(NSString *)operation arguments:(NSString *)arguments
          parse:(id (^)(NSData *reply, NSError **error))parse completion:(FPApiCompletion)completion
{
    [self perform:operation data:[arguments dataUsingEncoding:NSASCIIStringEncoding] parse:parse completion:completion];
}

- (void)perform:(NSString *)operation data:(NSData *)arguments
          parse:(id (^)(NSData *reply, NSError **error))parse completion:(FPApiCompletion)completion
{
    FPApiCompletion done = [completion copy];
    id (^parser)(NSData *, NSError **) = [parse copy];
    /* the one exit of the request: it runs on the main thread and releases both copies */
    void (^finish)(id, NSError *) = ^(id result, NSError *error) {
        done(result, error);
        [done release];
        [parser release];
    };
    [self whenConnected:^(NSError *connectError) {
        if (connectError) { finish(nil, connectError); return; }
        [_network request:operation arguments:arguments
               completion:^(NSData *document, NSInteger serverStatus, NSError *error) {
            if (error) { finish(nil, error); return; }
            if (serverStatus != 0) {
                finish(nil, FPApiError(serverStatus, [NSString stringWithFormat:@"Сервер отклонил запрос (код %ld)", (long)serverStatus]));
                return;
            }
            /* index replies share a lane so an older parse cannot replace the newer disk cache */
            NSUInteger lane = ([operation isEqualToString:@"fi"] || [operation isEqualToString:@"sl"]) ? 0 : (_nextParseQueue++ % 2);
            dispatch_async(_parseQueues[lane], ^{
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                NSError *parseError = nil;
                id result = [parser(document, &parseError) retain];
                NSError *kept = [parseError retain];
                dispatch_async(dispatch_get_main_queue(), ^{
                    finish(result, kept);
                    [result release];
                    [kept release];
                });
                [pool drain];
            });
        }];
    }];
}

static NSString *FPIndexCachePath(void)
{
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [dirs count] ? [[dirs objectAtIndex:0] stringByAppendingPathComponent:@"forum-index.reply"] : nil;
}

- (NSArray *)cachedForumIndex
{
    NSString *path = FPIndexCachePath();
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    return data ? FPParseForumIndex(data, NULL) : nil;
}

static NSString *FPNewsCachePath(void)
{
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [dirs count] ? [[dirs objectAtIndex:0] stringByAppendingPathComponent:@"news-feed.reply"] : nil;
}

- (NSArray *)cachedNews
{
    NSString *path = FPNewsCachePath();
    NSDictionary *attributes = path ? [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] : nil;
    if (!attributes || [[attributes objectForKey:NSFileSize] unsignedLongLongValue] > 512u * 1024u) return nil;
    return FPParseNewsFeed([NSData dataWithContentsOfFile:path]);
}

- (void)loadNews:(FPApiCompletion)completion
{
    [self perform:@"sl" arguments:@"[0,30,-1,0]" parse:^id(NSData *reply, NSError **error) {
        NSArray *items = FPParseNewsFeed(reply);
        if (!items) { *error = FPApiError(1, @"Неверный формат ленты новостей"); return nil; }
        NSString *path = FPNewsCachePath();
        if (path && ![reply writeToFile:path atomically:YES]) NSLog(@"shapka: cannot save news feed cache");
        return items;
    } completion:completion];
}

- (void)loadNewsArticle:(NSInteger)identifier completion:(FPApiCompletion)completion
{
    if (identifier <= 0 || identifier > INT32_MAX) { completion(nil, FPApiError(1, @"Неверный номер статьи")); return; }
    [self perform:@"sa" arguments:[NSString stringWithFormat:@"[%ld]", (long)identifier] parse:^id(NSData *reply, NSError **error) {
        NSArray *blocks = FPParseNewsArticle(reply, identifier);
        if (!blocks) *error = FPApiError(1, @"Неверный формат статьи");
        return blocks;
    } completion:completion];
}

- (void)loadForumIndex:(FPApiCompletion)completion
{
    [self perform:@"fi" arguments:@"[]" parse:^id(NSData *reply, NSError **error) {
        NSArray *index = FPParseForumIndex(reply, error);
        NSString *path = FPIndexCachePath();
        /* only a reply that parsed is kept, so a broken answer never replaces the good copy */
        if (index && path) [reply writeToFile:path atomically:YES];
        return index;
    } completion:completion];
}

- (void)resolveAttachment:(NSInteger)attachmentId completion:(FPApiCompletion)completion
{
    if (attachmentId <= 0) { completion(nil, FPApiError(1, @"Неверный номер вложения")); return; }
    [self perform:@"fa" arguments:[NSString stringWithFormat:@"[%ld]", (long)attachmentId]
            parse:^id(NSData *reply, NSError **error) {
        fp_span span;
        char buffer[8192];
        size_t written = 0;
        if (fp_forum_parse_attachment_url([reply bytes], [reply length], &span) != FP_FORUM_OK ||
            fp_text_decode(span, buffer, sizeof(buffer), &written) != FP_TEXT_OK) {
            *error = FPApiError(1, @"Сервер вернул неверный адрес файла");
            return nil;
        }
        return [[[NSString alloc] initWithBytes:buffer length:written encoding:NSUTF8StringEncoding] autorelease];
    } completion:completion];
}

static NSData *FPEncodeMessage(NSString *text)
{
    NSMutableData *encoded = [NSMutableData data];
    NSUInteger index = 0, length = [text length];
    if (!length || length > 60000) return nil;
    while (index < length) {
        unichar first = [text characterAtIndex:index];
        NSUInteger count = 1;
        uint32_t scalar = first;
        if (first >= 0xd800 && first <= 0xdbff && index + 1 < length) {
            unichar second = [text characterAtIndex:index + 1];
            if (second >= 0xdc00 && second <= 0xdfff) {
                scalar = 0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00);
                count = 2;
            }
        }
        if (scalar >= 0xd800 && scalar <= 0xdfff) return nil;
        NSData *part = [[text substringWithRange:NSMakeRange(index, count)] dataUsingEncoding:NSWindowsCP1251StringEncoding allowLossyConversion:NO];
        if (!part) part = [[NSString stringWithFormat:@"&#%u;", (unsigned)scalar] dataUsingEncoding:NSASCIIStringEncoding];
        [encoded appendData:part];
        index += count;
    }
    if ([encoded length] > 200000) return nil;
    return encoded;
}

- (void)sendReply:(NSString *)text topic:(NSInteger)topicId completion:(FPApiDone)completion
{
    if ([self memberId] <= 0) { completion(FPApiError(1, @"Войдите, чтобы ответить")); return; }
    NSData *body = topicId > 0 && topicId <= INT32_MAX ? FPEncodeMessage(text) : nil;
    if (!body) { completion(FPApiError(1, @"Проверьте текст сообщения")); return; }
    NSMutableData *arguments = [NSMutableData dataWithLength:[body length] * 6 + 64];
    size_t written = 0;
    if (fp_compose_reply((int32_t)topicId, [body bytes], [body length], [arguments mutableBytes], [arguments length], &written) != FP_DOCUMENT_OK) {
        completion(FPApiError(1, @"Не удалось подготовить сообщение")); return;
    }
    [arguments setLength:written];
    [self perform:@"fp" data:arguments parse:^id(NSData *reply, NSError **error) {
        (void)reply; (void)error;
        return [NSNull null];
    } completion:^(id result, NSError *error) { (void)result; completion(error); }];
}

- (void)votePost:(NSInteger)postId up:(BOOL)up completion:(FPApiDone)completion
{
    if ([self memberId] <= 0) { completion(FPApiError(1, @"Войдите, чтобы оценить пост")); return; }
    NSMutableData *arguments = [NSMutableData dataWithLength:40];
    size_t written = 0;
    if (postId > INT32_MAX || fp_compose_post_vote((int32_t)postId, up ? 2 : 1, [arguments mutableBytes], [arguments length], &written) != FP_DOCUMENT_OK) {
        completion(FPApiError(1, @"Неверный номер сообщения")); return;
    }
    [arguments setLength:written];
    FPApiDone done = [completion copy];
    [self perform:@"fk" data:arguments parse:^id(NSData *reply, NSError **error) { (void)reply; (void)error; return [NSNull null]; }
       completion:^(id result, NSError *error) {
        (void)result;
        done(error);
        [done release];
    }];
}

- (void)loadVotesOfPost:(NSInteger)postId completion:(FPApiCompletion)completion
{
    NSMutableData *arguments = [NSMutableData dataWithLength:40];
    size_t written = 0;
    if (postId > INT32_MAX || fp_compose_post_vote((int32_t)postId, 0, [arguments mutableBytes], [arguments length], &written) != FP_DOCUMENT_OK) {
        completion(nil, FPApiError(1, @"Неверный номер сообщения")); return;
    }
    [arguments setLength:written];
    [self perform:@"fk" data:arguments parse:^id(NSData *reply, NSError **error) { return FPParseVotes(reply, error); } completion:completion];
}

- (void)changeKarmaOfMember:(NSInteger)memberId post:(NSInteger)postId up:(BOOL)up reason:(NSString *)reason completion:(FPApiDone)completion
{
    if ([self memberId] <= 0) { completion(FPApiError(1, @"Войдите, чтобы изменить репутацию")); return; }
    NSData *body = memberId > 0 && memberId <= INT32_MAX && postId > 0 && postId <= INT32_MAX && [reason length] <= 500 ? FPEncodeMessage(reason) : nil;
    if (!body) { completion(FPApiError(1, @"Укажите причину изменения репутации")); return; }
    NSMutableData *arguments = [NSMutableData dataWithLength:[body length] * 6 + 64];
    size_t written = 0;
    if (fp_compose_karma((int32_t)memberId, up ? 1 : 0, (int32_t)postId, [body bytes], [body length], [arguments mutableBytes], [arguments length], &written) != FP_DOCUMENT_OK) {
        completion(FPApiError(1, @"Не удалось подготовить запрос")); return;
    }
    [arguments setLength:written];
    FPApiDone done = [completion copy];
    [self perform:@"mr" data:arguments parse:^id(NSData *reply, NSError **error) { (void)reply; (void)error; return [NSNull null]; }
       completion:^(id result, NSError *error) {
        (void)result;
        /* statuses 4 to 13 are the refusals the original client explains; a transport error keeps its own text */
        const char *refusal = error && [[error domain] isEqualToString:FPApiErrorDomain] ? fp_compose_karma_refusal((int32_t)[error code]) : NULL;
        done(refusal ? FPApiError([error code], [NSString stringWithUTF8String:refusal]) : error);
        [done release];
    }];
}

- (void)sendMessage:(NSString *)text subject:(NSString *)subject member:(NSInteger)memberId completion:(FPApiDone)completion
{
    if ([self memberId] <= 0) { completion(FPApiError(1, @"Войдите, чтобы написать")); return; }
    NSData *body = FPEncodeMessage(text);
    NSData *title = [subject length] <= 255 ? FPEncodeMessage(subject) : nil;
    if (memberId <= 0 || memberId > INT32_MAX || !body || !title) { completion(FPApiError(1, @"Проверьте тему и текст сообщения")); return; }
    NSMutableData *arguments = [NSMutableData dataWithLength:([body length] + [title length]) * 6 + 64];
    size_t written = 0;
    if (fp_compose_message((int32_t)memberId, [body bytes], [body length], [title bytes], [title length], [arguments mutableBytes], [arguments length], &written) != FP_DOCUMENT_OK) {
        completion(FPApiError(1, @"Не удалось подготовить сообщение")); return;
    }
    [arguments setLength:written];
    [self perform:@"qp" data:arguments parse:^id(NSData *reply, NSError **error) {
        (void)reply; (void)error;
        return [NSNull null];
    } completion:^(id result, NSError *error) { (void)result; completion(error); }];
}

- (void)loadQMSContacts:(NSInteger)memberId completion:(FPApiCompletion)completion
{
    if ([self memberId] <= 0) { completion(nil, FPApiError(1, @"Войдите, чтобы открыть сообщения")); return; }
    NSString *arguments = memberId > 0 ? [NSString stringWithFormat:@"[%ld]", (long)memberId] : @"[]";
    [self perform:@"ql" arguments:arguments parse:^id(NSData *reply, NSError **error) {
        if (!fp_qms_validate([reply bytes], [reply length], FP_QMS_CONTACTS)) {
            *error = FPApiError(1, @"Неверный список собеседников"); return nil;
        }
        NSArray *root = FPProtocolDocument(reply);
        if ([root count] < 3 || ![[root objectAtIndex:2] isKindOfClass:[NSArray class]]) {
            *error = FPApiError(1, @"Неверный список собеседников"); return nil;
        }
        return [root objectAtIndex:2];
    } completion:completion];
}

- (void)loadQMSTalk:(NSInteger)dialogId completion:(FPApiCompletion)completion
{
    [self loadQMSTalk:dialogId before:0 completion:completion];
}

- (void)loadQMSTalk:(NSInteger)dialogId before:(NSInteger)messageId completion:(FPApiCompletion)completion
{
    if ([self memberId] <= 0 || dialogId <= 0 || messageId < 0) { completion(nil, FPApiError(1, @"Невозможно открыть диалог")); return; }
    [self perform:@"qt" arguments:[NSString stringWithFormat:@"[%ld,%ld,-60]", (long)dialogId, (long)messageId] parse:^id(NSData *reply, NSError **error) {
        if (!fp_qms_validate([reply bytes], [reply length], FP_QMS_TALK)) {
            *error = FPApiError(1, @"Неверный ответ диалога"); return nil;
        }
        NSArray *root = FPProtocolDocument(reply);
        if ([root count] < 16 || ![[root objectAtIndex:5] isKindOfClass:[NSString class]] ||
            ![[root objectAtIndex:15] isKindOfClass:[NSArray class]]) {
            *error = FPApiError(1, @"Неверный ответ диалога"); return nil;
        }
        for (id message in [root objectAtIndex:15]) {
            if ([[message objectAtIndex:3] length] > 60000) {
                *error = FPApiError(1, @"Сообщение слишком велико"); return nil;
            }
        }
        return root;
    } completion:completion];
}

- (void)sendQMSText:(NSString *)text dialog:(NSInteger)dialogId completion:(FPApiDone)completion
{
    NSData *body = FPEncodeMessage(text);
    if ([self memberId] <= 0 || dialogId <= 0 || dialogId > INT32_MAX || !body) {
        completion(FPApiError(1, @"Проверьте текст сообщения")); return;
    }
    NSMutableData *arguments = [NSMutableData dataWithLength:[body length] * 6 + 64];
    size_t written = 0;
    if (fp_compose_qms_reply((int32_t)dialogId, [body bytes], [body length], [arguments mutableBytes], [arguments length], &written) != FP_DOCUMENT_OK) {
        completion(FPApiError(1, @"Не удалось подготовить сообщение")); return;
    }
    [arguments setLength:written];
    [self perform:@"qp" data:arguments parse:^id(NSData *reply, NSError **error) {
        (void)reply; (void)error; return [NSNull null];
    } completion:^(id result, NSError *error) { (void)result; completion(error); }];
}

- (void)loadAnnouncement:(NSInteger)identifier completion:(FPApiCompletion)completion
{
    if (identifier <= 0 || identifier > INT32_MAX) { completion(nil, FPApiError(1, @"Неверный номер объявления")); return; }
    [self perform:@"fn" arguments:[NSString stringWithFormat:@"[%ld]", (long)identifier] parse:^id(NSData *reply, NSError **error) {
        NSArray *root = FPProtocolDocument(reply);
        if ([root count] < 4 || ![[root objectAtIndex:2] isKindOfClass:[NSString class]] ||
            ![[root objectAtIndex:3] isKindOfClass:[NSString class]]) {
            *error = FPApiError(1, @"Неверные данные объявления"); return nil;
        }
        return [NSDictionary dictionaryWithObjectsAndKeys:[root objectAtIndex:2], @"title", [root objectAtIndex:3], @"body", nil];
    } completion:completion];
}

- (void)loadForum:(NSInteger)forumId offset:(NSInteger)offset count:(NSInteger)count completion:(FPApiCompletion)completion
{
    [self perform:@"fs" arguments:[NSString stringWithFormat:@"[%ld,%ld,%ld]", (long)forumId, (long)offset, (long)count]
            parse:^id(NSData *reply, NSError **error) { return FPParseForumPage(reply, error); } completion:completion];
}

- (void)loadTopic:(NSInteger)topicId offset:(NSInteger)offset count:(NSInteger)count completion:(FPApiCompletion)completion
{
    [self perform:@"fr" arguments:[NSString stringWithFormat:@"[%ld,%ld,%ld,0]", (long)topicId, (long)offset, (long)count]
            parse:^id(NSData *reply, NSError **error) { return FPParseTopicPage(reply, error); } completion:completion];
}

#define FP_FAVORITES_WINDOW 30
#define FP_FAVORITES_APP_LIMIT 500

- (void)loadFavoritesFrom:(NSInteger)offset collected:(NSArray *)collected completion:(FPApiCompletion)completion
{
    FPApiCompletion done = [completion copy];
    NSArray *kept = [collected retain];
    [self perform:@"mf" arguments:[NSString stringWithFormat:@"[%ld,%d,0]", (long)offset, FP_FAVORITES_WINDOW]
            parse:^id(NSData *reply, NSError **error) { return FPParseFavorites(reply, error); }
       completion:^(id result, NSError *error) {
        FPFavoritesPage *page = result;
        NSArray *all;
        NSInteger next;
        if (error) { done(nil, error); [done release]; [kept release]; return; }
        all = [kept arrayByAddingObjectsFromArray:page.topics];
        next = offset + (NSInteger)page.entries;
        /* an empty window ends the loop even when the total claims more, so a server that lies cannot make it spin */
        if (!page.entries || next >= page.total || next >= FP_FAVORITES_APP_LIMIT) {
            done([all count] > FP_FAVORITES_APP_LIMIT ? [all subarrayWithRange:NSMakeRange(0, FP_FAVORITES_APP_LIMIT)] : all, nil);
            [done release]; [kept release];
            return;
        }
        [self loadFavoritesFrom:next collected:all completion:done];
        [done release]; [kept release];
    }];
}

- (void)loadFavorites:(FPApiCompletion)completion
{
    [self loadFavoritesFrom:0 collected:[NSArray array] completion:completion];
}

/* the arguments are those the original client sends for the subscription to a topic: 11, the topic ids, the mask 8 (the favorite bit of a topic page) and its new value */
- (void)setTopic:(NSInteger)topicId favorite:(BOOL)favorite completion:(FPApiDone)completion
{
    FPApiDone done = [completion copy];
    [self perform:@"fm" arguments:[NSString stringWithFormat:@"[11,[%ld],8,%d,\"\"]", (long)topicId, favorite ? 8 : 0]
            parse:^id(NSData *reply, NSError **error) { (void)reply; (void)error; return [NSNumber numberWithBool:YES]; }
       completion:^(id result, NSError *error) { (void)result; done(error); [done release]; }];
}

/* the picture of a captcha is named in the reply as one of the forum's own files, and nothing else is taken for it */
static NSString *FPCaptchaURL(NSData *document)
{
    NSString *text = [[[NSString alloc] initWithData:document encoding:NSWindowsCP1251StringEncoding] autorelease];
    NSString *prefix = @"https://4pda.to/static/captcha/";
    NSRange start = [text rangeOfString:prefix], end;
    NSString *url;
    NSString *name;
    if (!text || start.location == NSNotFound) return nil;
    end = [text rangeOfString:@"\"" options:0 range:NSMakeRange(start.location, [text length] - start.location)];
    if (end.location == NSNotFound) return nil;
    url = [text substringWithRange:NSMakeRange(start.location, end.location - start.location)];
    name = [url substringFromIndex:[prefix length]];
    if ([name length] != 36 || ![name hasSuffix:@".gif"]) return nil;
    for (NSUInteger i = 0; i < 32; i++) {
        unichar c = [name characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return nil;
    }
    return url;
}

- (void)loginWithName:(NSString *)name password:(NSString *)password hidden:(BOOL)hidden captcha:(NSInteger)captcha remember:(BOOL)remember completion:(FPApiLoginDone)completion
{
    FPApiLoginDone done = [completion copy];
    [self whenConnected:^(NSError *connectError) {
        if (connectError) { done(connectError, nil); [done release]; return; }
        [_network login:name password:password hidden:hidden captcha:captcha remember:remember
             completion:^(NSData *document, NSInteger serverStatus, NSError *error) {
            NSError *result = error;
            NSString *picture = nil;
            if (!result && serverStatus == 4) {
                picture = FPCaptchaURL(document);
                result = FPApiError(serverStatus, captcha > 0 ? @"Число с картинки не подошло, попробуйте ещё раз" : @"Введите число с картинки");
                if (!picture) result = FPApiError(serverStatus, @"Сервер просит капчу, но не прислал картинку");
            } else if (!result && serverStatus != 0) {
                result = FPApiError(serverStatus, [NSString stringWithFormat:@"Сервер не принял логин или пароль (код %ld)", (long)serverStatus]);
            }
            if (!result) {
                [FPAccountStore rememberName:name avatar:nil forMember:[self memberId]];
                [[NSNotificationCenter defaultCenter] postNotificationName:FPApiAccountNotification object:self];
            }
            done(result, picture);
            [done release];
        }];
    }];
}

- (void)loadCaptcha:(FPApiCaptchaDone)completion
{
    FPApiCaptchaDone done = [completion copy];
    [self whenConnected:^(NSError *connectError) {
        if (connectError) { done(nil, connectError); [done release]; return; }
        [_network request:@"mc" arguments:[NSData dataWithBytes:"[0]" length:3]
               completion:^(NSData *document, NSInteger serverStatus, NSError *error) {
            NSString *picture = error || serverStatus != 12 ? nil : FPCaptchaURL(document);
            if (!error && !picture) error = FPApiError(serverStatus, @"Не удалось получить картинку капчи");
            done(picture, error);
            [done release];
        }];
    }];
}

- (void)logout:(FPApiDone)completion
{
    FPApiDone done = [completion copy];
    OSStatus status = [FPAccountStore removeAccount];
    if (status != errSecSuccess && status != errSecItemNotFound) {
        done(FPApiError(status, @"Не удалось удалить сохранённый вход"));
        [done release];
        return;
    }
    /* the live session still belongs to the member, so it is replaced by a guest connection */
    _connected = NO;
    _connecting = NO;
    [_network disconnect];
    [self whenConnected:^(NSError *error) {
        [[NSNotificationCenter defaultCenter] postNotificationName:FPApiAccountNotification object:self];
        done(error);
        [done release];
    }];
}

- (NSInteger)memberId
{
    fp_auth_account account;
    NSInteger member = 0;
    if ([FPAccountStore loadAccount:&account] == errSecSuccess) member = account.member_id;
    fp_auth_clear(&account);
    return member;
}

@end
