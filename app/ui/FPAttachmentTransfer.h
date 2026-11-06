#import <Foundation/Foundation.h>
#import "FPApi.h"

/* all entry points and completions run on the main thread */
@class FPDownload;
@interface FPAttachmentTransfer : NSObject {
    FPApi *_api;
    NSString *_name;
    FPDownload *_download;
    void (^_completion)(NSString *, NSError *);
    BOOL _finished;
}
+ (BOOL)startWithApi:(FPApi *)api identifier:(NSInteger)identifier name:(NSString *)name completion:(void (^)(NSString *path, NSError *error))completion;
+ (NSUInteger)activeCount;
@end
