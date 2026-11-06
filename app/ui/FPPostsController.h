#import "FPScreenController.h"
#import "FPPostViews.h"

@interface FPPostsController : FPScreenController <UITableViewDataSource, UITableViewDelegate, FPPagerDelegate, FPPostCellDelegate, UIActionSheetDelegate> {
    NSInteger _topicId;
    NSString *_topicTitle;
    FPTopicPage *_page;
    UITableView *_table;
    UIButton *_favoriteButton;
    FPPager *_pager;
    NSInteger _pageIndex;
    NSInteger _perPage;
    NSInteger _restorePostId;
    NSUInteger _serial;
    NSUInteger _buildSerial;
    NSMutableDictionary *_contents;
    NSMutableDictionary *_layouts;
    NSMutableDictionary *_spoilers;
    CGFloat _buildWidth;
    BOOL _headerOpen;
    BOOL _favoriteBusy;
    UIDocumentInteractionController *_documentController;
    FPPost *_selectedPost;
    UIActionSheet *_postActions;
    NSMutableArray *_postActionKinds;
    NSString *_memberLink;
    NSInteger _memberId;
}
- (id)initWithApi:(FPApi *)api topicId:(NSInteger)topicId title:(NSString *)title offset:(NSInteger)offset;
@end
