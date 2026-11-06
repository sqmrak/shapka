#import <UIKit/UIKit.h>
#import "FPModels.h"

/* a forum message laid out for one width: text frames, boxes, bars, spoiler headers and images, in document order;
   a layout never changes after it is built, so tiles can draw it on a background thread; a spoiler toggle or a new
   width builds a new one */

typedef enum {
    FPHitNone,
    FPHitLink,
    FPHitSpoiler,
    FPHitImage,
    FPHitFile
} FPHitKind;

@interface FPPostHit : NSObject {
@public
    FPHitKind kind;
    NSString *link;
    NSInteger spoiler;
    NSInteger attachmentId;
    NSString *fileName;
}
@end

@interface FPPostLayout : NSObject {
    NSArray *_items;
    CGFloat _width;
    CGFloat _height;
    NSSet *_awaiting;
}
@property (nonatomic, readonly) CGFloat width;
@property (nonatomic, readonly) CGFloat height;
/* tree of a message body; build it once per post and reuse it for every width */
+ (id)contentForPost:(FPPost *)post includeSignature:(BOOL)signature;
/* spoilers holds the indexes of the opened spoilers */
+ (FPPostLayout *)layoutContent:(id)content width:(CGFloat)width spoilers:(NSIndexSet *)spoilers;
/* YES when the layout gave this picture a placeholder slot because its size was not known yet */
- (BOOL)awaitsSizeOfURL:(NSString *)url;
- (void)drawInRect:(CGRect)dirty;
- (FPPostHit *)hitTest:(CGPoint)point;
/* the image addresses of the layout that are not decoded yet, with the size each is shown at */
- (void)enumerateImages:(void (^)(NSString *url, CGSize size, BOOL thumbnail))block;
@end
