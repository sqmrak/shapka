#import "FPScreenController.h"

@interface FPFavoritesController : FPScreenController <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate> {
    UITableView *_table;
    NSArray *_items;
    NSUInteger _serial;
    UIPanGestureRecognizer *_swipe;
    NSDictionary *_swipeItem;
    NSDictionary *_removing;
    CGFloat _swipeBase;
}
@end
