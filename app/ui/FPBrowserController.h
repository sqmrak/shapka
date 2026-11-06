#import "FPScreenController.h"

/* opens a web page inside the app; the back button first walks back through the pages of the view */
@interface FPBrowserController : FPScreenController <UIWebViewDelegate> {
    UIWebView *_web;
    NSURL *_url;
    NSUInteger _loads;
}
- (id)initWithApi:(FPApi *)api url:(NSURL *)url;
@end
