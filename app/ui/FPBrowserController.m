#import "FPBrowserController.h"
#import "FPChrome.h"

/* uiwebview is the only web view that exists on ios 5 to 7 and it still runs on current systems */
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation FPBrowserController
- (id)initWithApi:(FPApi *)api url:(NSURL *)url
{
    self = [super initWithApi:api];
    if (self) _url = [url retain];
    return self;
}
- (void)dealloc
{
    _web.delegate = nil;
    [_web stopLoading];
    [_web release]; [_url release];
    [super dealloc];
}
- (void)loadView
{
    [super loadView];
    self.appBar.title = [_url host];
    [self.appBar addActionWithIcon:FPIconChevronRight target:self action:@selector(openInSafari)].accessibilityLabel = @"Открыть в Safari";
    [self.appBar addActionWithIcon:FPIconRefresh target:self action:@selector(reloadFromUser)].accessibilityLabel = @"Обновить";
    _web = [[UIWebView alloc] init];
    _web.delegate = self;
    _web.scalesPageToFit = YES;
    _web.backgroundColor = [UIColor whiteColor];
    [self.contentView insertSubview:_web belowSubview:self.stateView];
    [self.stateView showLoading];
    [_web loadRequest:[NSURLRequest requestWithURL:_url]];
}
- (void)layoutContent { _web.frame = self.contentView.bounds; }
- (void)reloadFromUser
{
    if ([_web request]) [_web reload];
    else [_web loadRequest:[NSURLRequest requestWithURL:_url]];
}
- (void)openInSafari
{
    NSURL *current = [[_web request] URL];
    [self openInBrowser:current ? current : _url];
}
- (void)goBack
{
    if ([_web canGoBack]) [_web goBack];
    else [super goBack];
}
- (BOOL)webView:(UIWebView *)view shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)type
{
    (void)view;
    NSURL *target = [request URL];
    NSString *scheme = [[target scheme] lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        if ([scheme isEqualToString:@"about"]) return YES;
        [self openInBrowser:target];
        return NO;
    }
    /* a forum topic or forum reached from a page opens as a native screen */
    if (type == UIWebViewNavigationTypeLinkClicked && [[target path] hasPrefix:@"/forum/index.php"] &&
        ([[target host] hasSuffix:@"4pda.to"] || [[target host] hasSuffix:@"4pda.ru"]) &&
        ([[target query] rangeOfString:@"showtopic="].location != NSNotFound || [[target query] rangeOfString:@"showforum="].location != NSNotFound)) {
        [self openLink:[target absoluteString]];
        return NO;
    }
    return YES;
}
- (void)webViewDidStartLoad:(UIWebView *)view { (void)view; _loads++; }
- (void)webViewDidFinishLoad:(UIWebView *)view
{
    if (_loads) _loads--;
    self.stateView.hidden = YES;
    NSString *title = [view stringByEvaluatingJavaScriptFromString:@"document.title"];
    self.appBar.title = [title length] ? title : [[[view request] URL] host];
}
- (void)webView:(UIWebView *)view didFailLoadWithError:(NSError *)error
{
    (void)view;
    if (_loads) _loads--;
    /* a load that a newer one cancelled reports -999 and must not replace the page with an error */
    if ([[error domain] isEqualToString:NSURLErrorDomain] && [error code] == NSURLErrorCancelled) return;
    if (_loads) return;
    [self.stateView showMessage:[NSString stringWithFormat:@"Страница не открылась: %@", [error localizedDescription]] retry:YES];
    [self.stateView.retryButton removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    [self.stateView.retryButton addTarget:self action:@selector(reloadFromUser) forControlEvents:UIControlEventTouchUpInside];
}
@end
