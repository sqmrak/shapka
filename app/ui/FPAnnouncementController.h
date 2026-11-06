#import "FPScreenController.h"
#import "FPPostViews.h"
@interface FPAnnouncementController : FPScreenController {
    NSInteger _identifier;
    NSString *_heading;
    UIScrollView *_scroll;
    FPPostBodyView *_bodyView;
    id _content;
    FPPostLayout *_layout;
    NSMutableIndexSet *_spoilers;
    CGFloat _layoutWidth;
    NSUInteger _serial;
}
- (id)initWithApi:(FPApi *)api identifier:(NSInteger)identifier title:(NSString *)title;
@end
