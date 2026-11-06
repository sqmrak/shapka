#import "FPAttachmentTransfer.h"
#import "FPDownload.h"

#define FP_ATTACHMENT_ACTIVE_LIMIT 3u

static NSMutableSet *gTransfers;

@interface FPAttachmentTransfer ()
- (void)finish:(NSString *)path error:(NSError *)error;
@end

@implementation FPAttachmentTransfer
+ (BOOL)startWithApi:(FPApi *)api identifier:(NSInteger)identifier name:(NSString *)name completion:(void (^)(NSString *, NSError *))completion
{
    if (!gTransfers) gTransfers = [[NSMutableSet alloc] init];
    if ([gTransfers count] >= FP_ATTACHMENT_ACTIVE_LIMIT || !api || !completion) return NO;
    FPAttachmentTransfer *transfer = [[FPAttachmentTransfer alloc] init];
    transfer->_api = [api retain];
    transfer->_name = [name copy];
    transfer->_completion = [completion copy];
    [gTransfers addObject:transfer];
    [api resolveAttachment:identifier completion:^(id result, NSError *error) {
        if (error) { [transfer finish:nil error:error]; return; }
        transfer->_download = [[FPDownload alloc] initWithURL:[NSURL URLWithString:result] name:transfer->_name completion:^(NSString *path, NSError *downloadError) {
            [transfer finish:path error:downloadError];
        }];
        if (!transfer->_download) {
            NSError *invalid = [NSError errorWithDomain:@"com.pageflip.shapka.download" code:1
                                              userInfo:[NSDictionary dictionaryWithObject:@"Неверный адрес файла" forKey:NSLocalizedDescriptionKey]];
            [transfer finish:nil error:invalid];
            return;
        }
        [transfer->_download start];
    }];
    [transfer release];
    return YES;
}
+ (NSUInteger)activeCount { return [gTransfers count]; }
- (void)finish:(NSString *)path error:(NSError *)error
{
    if (_finished) return;
    _finished = YES;
    [[self retain] autorelease];
    [gTransfers removeObject:self];
    _completion(path, error);
    [_download release]; _download = nil;
}
- (void)dealloc
{
    [_api release]; [_name release]; [_download release]; [_completion release];
    [super dealloc];
}
@end
