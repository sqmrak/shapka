#import <UIKit/UIKit.h>

@class FPPager;

@protocol FPPagerDelegate <NSObject>
- (void)pagerDidSelectPrevious:(FPPager *)pager;
- (void)pagerDidSelectNext:(FPPager *)pager;
- (void)pagerDidSelectJump:(FPPager *)pager;
@end

/* the page bar at the bottom of a paged list: previous, "3 из 12" and next */
@interface FPPager : UIView {
    UIButton *_previous;
    UIButton *_next;
    UIButton *_label;
    NSInteger _page;
    NSInteger _count;
    CGFloat _bottomInset;
    id<FPPagerDelegate> _delegate;
}
@property (nonatomic, assign) id<FPPagerDelegate> delegate;
@property (nonatomic, assign) CGFloat bottomInset;
@property (nonatomic, readonly) NSInteger page;
@property (nonatomic, readonly) NSInteger count;
+ (CGFloat)contentHeight;
/* pages are counted from zero */
- (void)setPage:(NSInteger)page count:(NSInteger)count;
- (void)applyTheme;
@end
