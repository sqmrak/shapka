#import "FPScreenController.h"

@interface FPNewsController : FPScreenController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_table;
    NSArray *_items;
    NSUInteger _serial;
}
@end

@interface FPNewsArticleController : FPScreenController {
    NSDictionary *_item;
    UIScrollView *_scroll;
    UIImageView *_hero;
    NSMutableDictionary *_heroToken;
    /* the page of the article: its token (asked by the blocking calls whether the screen is still here), the blocks read from it and the view of each */
    NSMutableDictionary *_articleToken;
    NSArray *_blockInfo;
    NSMutableArray *_blockViews;
    UILabel *_statusLabel;
    UILabel *_titleLabel;
    UILabel *_summaryLabel;
    UIButton *_favoriteButton;
}
- (id)initWithApi:(FPApi *)api item:(NSDictionary *)item;
@end
