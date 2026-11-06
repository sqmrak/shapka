#import "FPNewsCell.h"
#import "FPTheme.h"
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#include "fp_news_http.h"
#include "fp_news_image.h"
#include "fp_webp.h"
#include <stdlib.h>

@interface FPNewsPreviewJob : NSObject {
@public
    FPNewsCell *target;
    NSString *url;
    NSString *failure;
    BOOL cancelled;
    BOOL direct;
}
- (void)run:(id)unused;
- (void)cancel;
@end

@interface FPNewsCell ()
- (void)previewFinished:(UIImage *)image job:(FPNewsPreviewJob *)job;
@end

static NSOperationQueue *FPPreviewQueue;
static NSCache *FPPreviewCache;

static NSString *FPPreviewPath(NSString *url)
{
    NSURL *parsed = [NSURL URLWithString:url];
    if (![[[parsed scheme] lowercaseString] isEqualToString:@"https"] ||
        ![[[parsed host] lowercaseString] isEqualToString:@"4pda.to"] ||
        [parsed user] || [parsed password] || [parsed port] || [parsed fragment]) return nil;
    NSRange scheme = [url rangeOfString:@"://"];
    if (scheme.location == NSNotFound) return nil;
    NSRange slash = [url rangeOfString:@"/" options:0 range:NSMakeRange(scheme.location + 3, [url length] - scheme.location - 3)];
    return slash.location == NSNotFound ? @"/" : [url substringFromIndex:slash.location];
}

static void FPReleaseWebPPixels(void *info, const void *data, size_t size)
{
    (void)info; (void)size;
    free((void *)data);
}

/* imageio decodes webp only from ios 14 and 4pda serves its article pictures as webp */
static UIImage *FPWebPImage(const uint8_t *data, size_t length, int maxPixel, NSString **reason)
{
    uint8_t *pixels = NULL;
    int width = 0, height = 0;
    fp_webp_status status = fp_webp_decode(data, length, maxPixel, &pixels, &width, &height);
    if (status != FP_WEBP_OK) {
        *reason = [NSString stringWithFormat:@"Картинка: webp не разобран (%d)", (int)status];
        return nil;
    }
    size_t bytes = (size_t)width * (size_t)height * 4u;
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels, bytes, FPReleaseWebPPixels);
    if (!provider) { free(pixels); *reason = @"Картинка: нет памяти"; return nil; }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef ref = space ? CGImageCreate((size_t)width, (size_t)height, 8, 32, (size_t)width * 4u, space,
        kCGImageAlphaLast | kCGBitmapByteOrderDefault, provider, NULL, NO, kCGRenderingIntentDefault) : NULL;
    if (space) CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    if (!ref) { *reason = @"Картинка: не создана"; return nil; }
    UIImage *image = [UIImage imageWithCGImage:ref];
    CGImageRelease(ref);
    return image;
}

UIImage *FPNewsLoadImageAtURL(NSString *imageURL, int maxPixel, NSString **failure, BOOL (^cancelled)(void))
{
    uint8_t *body = NULL; size_t length = 0; int http = 0;
    NSString *roots = [[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"];
    NSString *imagePath = FPPreviewPath(imageURL);
    UIImage *image = nil;
    NSString *reason = nil;
    fp_session_status status;
    if (!imagePath || !roots) reason = @"Адрес картинки не разрешён";
    else if (!cancelled()) {
        status = fp_news_get([roots fileSystemRepresentation], [imagePath UTF8String], 2u * 1024u * 1024u, &body, &length, &http);
        if (status != FP_SESSION_OK) reason = [NSString stringWithFormat:@"Картинка: ошибка сети %d", (int)status];
        else if (http != 200) reason = [NSString stringWithFormat:@"Картинка: HTTP %d", http];
        else if (fp_webp_is_webp(body, length)) image = FPWebPImage(body, length, maxPixel, &reason);
        else {
            NSData *data = [NSData dataWithBytesNoCopy:body length:length freeWhenDone:NO];
            CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
            if (source) {
                NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:(id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailFromImageAlways,
                    (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailWithTransform,
                    [NSNumber numberWithInt:maxPixel], (id)kCGImageSourceThumbnailMaxPixelSize, nil];
                CGImageRef thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, (CFDictionaryRef)options);
                if (thumb) { image = [UIImage imageWithCGImage:thumb]; CGImageRelease(thumb); }
                CFRelease(source);
            }
            if (!image) reason = @"картинки нет :P";
        }
    }
    free(body);
    if (failure) *failure = reason;
    return image;
}

UIImage *FPNewsLoadImage(NSString *articleURL, int maxPixel, NSString **failure, BOOL (^cancelled)(void))
{
    uint8_t *body = NULL; size_t length = 0; int http = 0;
    char imageURL[2048];
    NSString *roots = [[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"];
    NSString *path = FPPreviewPath(articleURL);
    NSString *reason = nil, *address = nil;
    fp_session_status status;
    if (!cancelled() && path && roots) {
        status = fp_news_get_head([roots fileSystemRepresentation], [path UTF8String], 24u * 1024u, &body, &length, &http);
        if (status != FP_SESSION_OK) reason = [NSString stringWithFormat:@"Статья: ошибка сети %d", (int)status];
        else if (http != 200) reason = [NSString stringWithFormat:@"Статья: HTTP %d", http];
        else if (!fp_news_image_url(body, length, imageURL, sizeof(imageURL))) reason = @"В статье нет картинки";
        else address = [NSString stringWithUTF8String:imageURL];
    }
    free(body);
    if (!address) {
        if (failure) *failure = reason;
        return nil;
    }
    return FPNewsLoadImageAtURL(address, maxPixel, failure, cancelled);
}

@implementation FPNewsPreviewJob
- (void)dealloc { [url release]; [failure release]; [super dealloc]; }
- (void)cancel { @synchronized(self) { cancelled = YES; } target = nil; }
- (BOOL)isCancelled { @synchronized(self) { return cancelled; } }
- (void)run:(id)unused
{
    (void)unused;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *reason = nil;
    UIImage *image = [(direct ? FPNewsLoadImageAtURL(url, 320, &reason, ^BOOL{ return [self isCancelled]; }) : FPNewsLoadImage(url, 320, &reason, ^BOOL{ return [self isCancelled]; })) retain];
    failure = [reason copy];
    if (![self isCancelled]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!cancelled && target) [target previewFinished:image job:self];
            [image release];
        });
    } else [image release];
    [pool drain];
}
@end

@implementation FPNewsCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (self) {
        if (!FPPreviewQueue) {
            FPPreviewQueue = [[NSOperationQueue alloc] init];
            [FPPreviewQueue setMaxConcurrentOperationCount:2];
            FPPreviewCache = [[NSCache alloc] init];
            [FPPreviewCache setTotalCostLimit:4u * 1024u * 1024u];
        }
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        _card = [[UIView alloc] init]; _card.layer.cornerRadius = 20; _card.clipsToBounds = YES; [self.contentView addSubview:_card];
        _preview = [[UIImageView alloc] init]; _preview.contentMode = UIViewContentModeScaleAspectFill; _preview.clipsToBounds = YES; [_card addSubview:_preview];
        _previewStatus = [[UILabel alloc] init]; _previewStatus.backgroundColor = [UIColor clearColor];
        _previewStatus.numberOfLines = 2; _previewStatus.textAlignment = NSTextAlignmentCenter;
        _previewStatus.font = FPFont(11, 0, NO); [_card addSubview:_previewStatus];
        _headline = [[UILabel alloc] init]; _headline.backgroundColor = [UIColor clearColor]; _headline.numberOfLines = 3; [_card addSubview:_headline];
    }
    return self;
}
- (void)dealloc
{
    [(FPNewsPreviewJob *)_job cancel]; [_job release]; [_url release]; [_card release]; [_preview release]; [_previewStatus release]; [_headline release];
    [super dealloc];
}
- (void)prepareForReuse
{
    [super prepareForReuse];
    [(FPNewsPreviewJob *)_job cancel]; [_job release]; _job = nil;
    [_url release]; _url = nil; _preview.image = nil;
}
- (void)configure:(NSDictionary *)item inset:(CGFloat)inset
{
    NSString *url = [item objectForKey:@"image"];
    BOOL direct = [url length] > 0;
    if (!direct) url = [item objectForKey:@"url"];
    _card.backgroundColor = FPColor(FPRoleContainer);
    _preview.backgroundColor = FPColor(FPRoleHighest);
    _previewStatus.textColor = FPColor(FPRoleOnVariant);
    _headline.font = FPFont(15, 1, YES); _headline.textColor = FPColor(FPRoleOnSurface);
    _headline.text = [item objectForKey:@"title"];
    _inset = inset;
    [self setNeedsLayout];
    if ([_url isEqualToString:url]) return;
    [(FPNewsPreviewJob *)_job cancel]; [_job release]; _job = nil;
    [_url release]; _url = [url copy];
    _preview.image = [FPPreviewCache objectForKey:url];
    _previewStatus.hidden = _preview.image != nil;
    _previewStatus.text = @"Загрузка…";
    if (_preview.image) return;
    if (!FPPreviewPath(url)) { _previewStatus.text = @"Превью недоступно"; return; }
    FPNewsPreviewJob *job = [[FPNewsPreviewJob alloc] init];
    job->target = self; job->url = [url copy]; job->direct = direct; _job = job;
    NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithTarget:job selector:@selector(run:) object:nil];
    [FPPreviewQueue addOperation:operation]; [operation release];
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    _card.frame = CGRectMake(_inset, 3, MAX(0, self.contentView.bounds.size.width - 2 * _inset), 112);
    _preview.frame = CGRectMake(0, 0, 112, 112);
    _previewStatus.frame = CGRectInset(_preview.frame, 6, 6);
    _headline.frame = CGRectMake(124, 8, MAX(0, _card.bounds.size.width - 136), 96);
}
- (void)previewFinished:(UIImage *)image job:(FPNewsPreviewJob *)job
{
    if (_job != job) return;
    if (image) {
        [FPPreviewCache setObject:image forKey:_url cost:(NSUInteger)(CGImageGetWidth(image.CGImage) * CGImageGetHeight(image.CGImage) * 4)];
        _preview.image = image;
        _previewStatus.hidden = YES;
    } else {
        _previewStatus.hidden = NO;
        _previewStatus.text = job->failure ? job->failure : @"Превью недоступно";
    }
    [_job release]; _job = nil;
}
@end
