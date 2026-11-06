#import "FPScreenController.h"
#include "fp_forum.h"
@interface FPTopicsController : FPScreenController <UITableViewDataSource, UITableViewDelegate, FPPagerDelegate> {
    NSInteger _forumId;
    NSString *_forumTitle;
    FPForumPage *_page;
    NSMutableArray *_items;
    UITableView *_table;
    FPPager *_pager;
    NSInteger _pageIndex;
    NSUInteger _serial;
    BOOL _loading;
}
- (id)initWithApi:(FPApi *)api forumId:(NSInteger)forumId title:(NSString *)title;
@end
