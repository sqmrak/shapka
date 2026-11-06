#import "FPImageLoader.h"
#import <ImageIO/ImageIO.h>

/* NSURLSession is missing before ios 7, and NSURLConnection is the one asynchronous http client of ios 5 and 6 */
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#define FP_IMAGE_BYTES_LIMIT (6u * 1024u * 1024u)
#define FP_IMAGE_ACTIVE_LIMIT 4u
#define FP_IMAGE_DECODE_LIMIT 2u
#define FP_IMAGE_FAILED_LIMIT 512u
#define FP_IMAGE_CACHE_BYTES (8u * 1024u * 1024u)
#define FP_IMAGE_SIZES_LIMIT 1024u

NSString *const FPImageSizeKnownNotification = @"FPImageSizeKnown";

@interface FPImageJob : NSObject {
@public
    NSString *key;
    NSString *url;
    CGSize size;
    BOOL circle;
    NSMutableArray *waiters;
    NSMutableData *data;
    NSURLConnection *connection;
}
@end

@implementation FPImageJob
- (void)dealloc
{
    [key release]; [url release]; [waiters release]; [data release];
    [super dealloc];
}
@end

@interface FPImageWaiter : NSObject {
@public
    id owner;
    FPImageBlock block;
}
@end

@implementation FPImageWaiter
- (void)dealloc { [block release]; [super dealloc]; }
@end

@interface FPImageLoader ()
+ (void)pump;
@end

static NSCache *gCache;
static NSMutableDictionary *gJobs;
static NSMutableArray *gPending;
static NSMutableSet *gFailed;
static NSUInteger gActive;
static NSUInteger gDecoding;
static NSMutableDictionary *gSizes;
static NSOperationQueue *gDecodeQueue;

@interface FPImageDelegate : NSObject
+ (FPImageDelegate *)shared;
@end

static NSString *FPImageKey(NSString *url, CGSize size, BOOL circle)
{
    return [NSString stringWithFormat:@"%@|%.0fx%.0f|%d|%.0f", url, size.width, size.height, circle ? 1 : 0, [[UIScreen mainScreen] scale]];
}

static void FPImageSetup(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gCache = [[NSCache alloc] init];
        [gCache setTotalCostLimit:FP_IMAGE_CACHE_BYTES];
        gJobs = [[NSMutableDictionary alloc] init];
        gPending = [[NSMutableArray alloc] init];
        gFailed = [[NSMutableSet alloc] init];
        gDecodeQueue = [[NSOperationQueue alloc] init];
        [gDecodeQueue setMaxConcurrentOperationCount:FP_IMAGE_DECODE_LIMIT];
    });
}

/* reads the dimensions from the header without decoding; returns YES when the address was not known before */
static BOOL FPImageRememberSize(NSString *url, NSData *data)
{
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
    NSDictionary *properties;
    NSNumber *width, *height;
    BOOL fresh = NO;
    if (!source) return NO;
    properties = [(NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL) autorelease];
    CFRelease(source);
    width = [properties objectForKey:(id)kCGImagePropertyPixelWidth];
    height = [properties objectForKey:(id)kCGImagePropertyPixelHeight];
    if (![width isKindOfClass:[NSNumber class]] || ![height isKindOfClass:[NSNumber class]] || [width floatValue] < 1 || [height floatValue] < 1) return NO;
    @synchronized([FPImageLoader class]) {
        if (!gSizes) gSizes = [[NSMutableDictionary alloc] init];
        if ([gSizes count] >= FP_IMAGE_SIZES_LIMIT) [gSizes removeAllObjects];
        fresh = [gSizes objectForKey:url] == nil;
        [gSizes setObject:[NSValue valueWithCGSize:CGSizeMake([width floatValue], [height floatValue])] forKey:url];
    }
    return fresh;
}

/* decodes at most the pixel size of the target and, for avatars, crops to a circle in the same bitmap */
static UIImage *FPImageDecode(NSData *data, CGSize points, BOOL circle, CGFloat scale)
{
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
    CGFloat longest = ceilf(MAX(points.width, points.height) * scale);
    NSDictionary *options;
    CGImageRef thumb;
    UIImage *result = nil;
    if (!source) return nil;
    options = [NSDictionary dictionaryWithObjectsAndKeys:
               (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailFromImageAlways,
               (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailWithTransform,
               [NSNumber numberWithFloat:(float)longest], (id)kCGImageSourceThumbnailMaxPixelSize, nil];
    thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, (CFDictionaryRef)options);
    CFRelease(source);
    if (!thumb) return nil;
    if (circle) {
        size_t side = (size_t)ceilf(points.width * scale);
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef c = CGBitmapContextCreate(NULL, side, side, 8, 0, space, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(space);
        if (c) {
            CGFloat w = (CGFloat)CGImageGetWidth(thumb), h = (CGFloat)CGImageGetHeight(thumb);
            CGFloat fit = MAX(side / w, side / h);
            CGRect rect = CGRectMake((side - w * fit) / 2, (side - h * fit) / 2, w * fit, h * fit);
            CGImageRef out;
            CGContextAddEllipseInRect(c, CGRectMake(0, 0, side, side));
            CGContextClip(c);
            CGContextDrawImage(c, rect, thumb);
            out = CGBitmapContextCreateImage(c);
            CGContextRelease(c);
            if (out) {
                result = [UIImage imageWithCGImage:out scale:scale orientation:UIImageOrientationUp];
                CGImageRelease(out);
            }
        }
    } else {
        result = [UIImage imageWithCGImage:thumb scale:scale orientation:UIImageOrientationUp];
    }
    CGImageRelease(thumb);
    return result;
}

/* a job that left the network no longer counts as active, whatever ended it */
static void FPImageDetach(FPImageJob *job)
{
    if (!job->connection) return;
    [job->connection cancel];
    [job->connection release];
    job->connection = nil;
    gActive--;
}

static void FPImageFinish(FPImageJob *job, UIImage *image)
{
    NSArray *waiters = [[job->waiters copy] autorelease];
    FPImageWaiter *waiter;
    /* a cancelled decode can finish after a new job for the same key starts */
    if ([gJobs objectForKey:job->key] != job) return;
    if (image) {
        CGSize s = image.size;
        [gCache setObject:image forKey:job->key cost:(NSUInteger)(s.width * s.height * image.scale * image.scale * 4)];
    } else {
        if ([gFailed count] >= FP_IMAGE_FAILED_LIMIT) [gFailed removeAllObjects];
        [gFailed addObject:job->url];
    }
    [[job retain] autorelease];
    [gJobs removeObjectForKey:job->key];
    for (waiter in waiters) waiter->block(image);
}

@implementation FPImageDelegate
+ (FPImageDelegate *)shared
{
    static FPImageDelegate *shared;
    if (!shared) shared = [[FPImageDelegate alloc] init];
    return shared;
}

- (FPImageJob *)jobFor:(NSURLConnection *)connection
{
    FPImageJob *job;
    for (job in [gJobs allValues]) if (job->connection == connection) return job;
    return nil;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    FPImageJob *job = [self jobFor:connection];
    NSInteger code = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 200;
    /* an html error page or a captive portal answers 200 too, so the type is checked next to the status */
    NSString *type = [[response MIMEType] lowercaseString];
    if (!job) return;
    if (code != 200 || ![type hasPrefix:@"image/"] || [response expectedContentLength] > (long long)FP_IMAGE_BYTES_LIMIT) {
        FPImageDetach(job);
        FPImageFinish(job, nil);
        [FPImageLoader pump];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)chunk
{
    FPImageJob *job = [self jobFor:connection];
    if (!job) return;
    if ([job->data length] + [chunk length] > FP_IMAGE_BYTES_LIMIT) {
        FPImageDetach(job);
        FPImageFinish(job, nil);
        [FPImageLoader pump];
        return;
    }
    [job->data appendData:chunk];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    FPImageJob *job = [self jobFor:connection];
    (void)error;
    if (!job) return;
    FPImageDetach(job);
    FPImageFinish(job, nil);
    [FPImageLoader pump];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    FPImageJob *job = [self jobFor:connection];
    NSData *data;
    NSString *address;
    CGSize size;
    BOOL circle;
    CGFloat scale = [[UIScreen mainScreen] scale];
    if (!job) return;
    data = [[job->data retain] autorelease];
    size = job->size;
    circle = job->circle;
    address = [[job->url copy] autorelease];
    [job retain];
    FPImageDetach(job);
    gDecoding++;
    [gDecodeQueue addOperationWithBlock:^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        UIImage *image = [FPImageDecode(data, size, circle, scale) retain];
        BOOL fresh = FPImageRememberSize(address, data);
        dispatch_async(dispatch_get_main_queue(), ^{
            FPImageFinish(job, image);
            if (fresh) [[NSNotificationCenter defaultCenter] postNotificationName:FPImageSizeKnownNotification object:address];
            [image release];
            [job release];
            gDecoding--;
            [FPImageLoader pump];
        });
        [pool drain];
    }];
    [FPImageLoader pump];
}
@end

@implementation FPImageLoader

+ (UIImage *)cachedImageForURL:(NSString *)url size:(CGSize)size circle:(BOOL)circle
{
    FPImageSetup();
    return [gCache objectForKey:FPImageKey(url, size, circle)];
}

+ (void)pump
{
    while (gActive + gDecoding < FP_IMAGE_ACTIVE_LIMIT && [gPending count]) {
        FPImageJob *job = [[gPending objectAtIndex:0] retain];
        NSURLRequest *request;
        [gPending removeObjectAtIndex:0];
        if (![gJobs objectForKey:job->key]) { [job release]; continue; }
        request = [NSURLRequest requestWithURL:[NSURL URLWithString:job->url] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:20];
        job->data = [[NSMutableData alloc] init];
        job->connection = [[NSURLConnection alloc] initWithRequest:request delegate:[FPImageDelegate shared] startImmediately:NO];
        if (!job->connection) {
            FPImageFinish(job, nil);
            [job release];
            continue;
        }
        /* common modes keep downloads running while a table scrolls */
        [job->connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        gActive++;
        [job->connection start];
        [job release];
    }
}

+ (void)loadURL:(NSString *)url size:(CGSize)size circle:(BOOL)circle owner:(id)owner completion:(FPImageBlock)completion
{
    NSString *key;
    FPImageJob *job;
    FPImageWaiter *waiter;
    NSURL *parsed;
    UIImage *cached;
    FPImageSetup();
    key = FPImageKey(url, size, circle);
    cached = [gCache objectForKey:key];
    if (cached) {
        completion(cached);
        return;
    }
    parsed = [url length] ? [NSURL URLWithString:url] : nil;
    if (![[parsed scheme] isEqualToString:@"https"] || [gFailed containsObject:url]) {
        /* plain http is refused by app transport security on current systems and is not downgraded to */
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    job = [gJobs objectForKey:key];
    if (!job) {
        job = [[[FPImageJob alloc] init] autorelease];
        job->key = [key copy];
        job->url = [url copy];
        job->size = size;
        job->circle = circle;
        job->waiters = [[NSMutableArray alloc] init];
        [gJobs setObject:job forKey:key];
        [gPending addObject:job];
    }
    waiter = [[[FPImageWaiter alloc] init] autorelease];
    waiter->owner = owner;
    waiter->block = [completion copy];
    [job->waiters addObject:waiter];
    [self pump];
}

+ (BOOL)knownSizeForURL:(NSString *)url size:(CGSize *)size
{
    NSValue *value;
    @synchronized([FPImageLoader class]) { value = [[[gSizes objectForKey:url] retain] autorelease]; }
    if (!value) return NO;
    if (size) *size = [value CGSizeValue];
    return YES;
}

+ (void)cancelOwner:(id)owner
{
    FPImageJob *job;
    for (job in [gJobs allValues]) {
        NSUInteger i = [job->waiters count];
        while (i--) {
            FPImageWaiter *waiter = [job->waiters objectAtIndex:i];
            if (waiter->owner == owner) [job->waiters removeObjectAtIndex:i];
        }
        /* a job nobody waits for stops before it costs bandwidth */
        if (![job->waiters count]) {
            FPImageDetach(job);
            [[job retain] autorelease];
            [gJobs removeObjectForKey:job->key];
        }
    }
    [self pump];
}

@end
