#import <UIKit/UIKit.h>
#import "FPApi.h"
#import "FPChrome.h"
#import "FPPager.h"
#import "FPTheme.h"

/* the base of every screen: surface, app bar, content area below it, loading and failure state,
   a transient message, pull to refresh, and the theme and layout plumbing */
@interface FPScreenController : UIViewController <UIGestureRecognizerDelegate> {
    FPApi *_api;
    FPAppBar *_appBar;
    UIView *_contentView;
    FPStateView *_stateView;
    UILabel *_toast;
    UIControl *_refresh;
    BOOL _viewVisible;
}
@property (nonatomic, readonly) FPApi *api;
@property (nonatomic, readonly) FPAppBar *appBar;
@property (nonatomic, readonly) UIView *contentView;
@property (nonatomic, readonly) FPStateView *stateView;
- (id)initWithApi:(FPApi *)api;
/* hooks; the base versions do nothing */
- (void)layoutContent;
- (void)themeDidChange;
- (void)reloadFromUser;
/* a short message at the bottom that does not replace the content */
- (void)showToast:(NSString *)text;
- (void)installRefreshOn:(UIScrollView *)scroll;
- (void)endRefreshing;
/* opens a forum link inside the app, anything else in the system browser */
- (void)openLink:(NSString *)url;
/* a link to a member page; return YES when the screen handled it, the base version leaves it to the browser */
- (BOOL)openMember:(NSInteger)memberId link:(NSString *)url;
- (void)goBack;
- (void)openInBrowser:(NSURL *)url;
- (void)openForum:(NSInteger)forumId title:(NSString *)title;
- (void)openTopic:(NSInteger)topicId title:(NSString *)title offset:(NSInteger)offset;
- (void)pageSwipedBy:(NSInteger)direction;
/* installs left and right swipes that call pageSwipedBy: with -1 and +1 */
- (void)installPageSwipeOn:(UIView *)view;
@end

/* hides the system bar and lets the edge swipe pop on every system */
@interface FPNavigationController : UINavigationController <UIGestureRecognizerDelegate, UINavigationControllerDelegate>
@end
