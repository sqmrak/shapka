#import <Foundation/Foundation.h>

typedef void (^FPDownloadCompletion)(NSString *path, NSError *error);

@interface FPDownload : NSObject {
    NSURLConnection *_connection;
    NSOutputStream *_stream;
    NSString *_temporaryPath;
    NSString *_finalPath;
    FPDownloadCompletion _completion;
    unsigned long long _received;
    long long _expected;
    NSUInteger _redirects;
    BOOL _acceptedResponse;
    BOOL _finished;
}
- (id)initWithURL:(NSURL *)url name:(NSString *)name completion:(FPDownloadCompletion)completion;
- (void)start;
- (void)cancel;
@end
