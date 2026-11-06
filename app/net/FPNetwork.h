#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include "fp_session.h"

extern NSString *const FPNetworkEventNotification;
extern NSString *const FPNetworkStateNotification;

typedef void (^FPNetworkCompletion)(NSData *document, NSInteger serverStatus, NSError *error);

@interface FPNetwork : NSObject {
    NSString *_host;
    NSString *_rootsPath;
    dispatch_queue_t _queue;
    fp_session _session;
    dispatch_source_t _readSource;
    BOOL _wantsConnection;
    NSUInteger _retryCount;
    NSUInteger _generation;
}
- (id)initWithHost:(NSString *)host rootsPath:(NSString *)rootsPath;
- (void)connectWithCompletion:(FPNetworkCompletion)completion;
- (void)login:(NSString *)login password:(NSString *)password hidden:(BOOL)hidden
      captcha:(NSInteger)captcha remember:(BOOL)remember completion:(FPNetworkCompletion)completion;
- (void)request:(NSString *)operation arguments:(NSData *)arguments completion:(FPNetworkCompletion)completion;
- (void)disconnect;
@end
