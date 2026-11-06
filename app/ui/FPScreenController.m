#import "FPBrowserController.h"
#import "FPScreenController.h"
#import "FPTopicsController.h"
#import "FPPostsController.h"
#import "FPSettings.h"
#import "FPWaveBackground.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

#define EDGE_WIDTH 30.0f

@implementation FPScreenController
@synthesize api = _api, appBar = _appBar, contentView = _contentView, stateView = _stateView;

- (id)initWithApi:(FPApi *)api
{
    self = [super init];
    if (self) {
        _api = [api retain];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:FPThemeChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:FPSettingsChangedNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_api release]; [_appBar release]; [_contentView release]; [_stateView release]; [_toast release]; [_refresh release];
    [super dealloc];
}

- (void)loadView
{
    FPWaveBackground *view = [[FPWaveBackground alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.backgroundColor = FPColor(FPRoleSurface);
    self.view = view;
    [view release];
    _contentView = [[UIView alloc] init];
    _contentView.backgroundColor = [UIColor clearColor];
    _contentView.clipsToBounds = YES;
    [self.view addSubview:_contentView];
    _stateView = [[FPStateView alloc] init];
    [_stateView.retryButton addTarget:self action:@selector(reloadFromUser) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_stateView];
    _appBar = [[FPAppBar alloc] init];
    [self.view addSubview:_appBar];
    FPSendBool(self, NSSelectorFromString(@"setAutomaticallyAdjustsScrollViewInsets:"), NO);
    if ([self.navigationController.viewControllers count] > 1) {
        [_appBar setBackVisible:YES];
        [_appBar.backButton addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)goBack
{
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if ([self.navigationController.viewControllers count] > 1 && _appBar.backButton.hidden) {
        [_appBar setBackVisible:YES];
        [_appBar.backButton addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    _viewVisible = YES;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    _viewVisible = NO;
}

- (void)themeChanged:(NSNotification *)notification
{
    (void)notification;
    if (![self isViewLoaded]) return;
    [(FPWaveBackground *)self.view applyTheme];
    _contentView.backgroundColor = [UIColor clearColor];
    [_appBar applyTheme];
    [_stateView applyTheme];
    _toast.backgroundColor = FPColor(FPRoleOnSurface);
    _toast.textColor = FPColor(FPRoleSurface);
    [self themeDidChange];
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews
{
    UIEdgeInsets safe = FPSafeInsets(self.view);
    CGRect bounds = self.view.bounds;
    CGFloat barHeight = safe.top + [FPAppBar contentHeight];
    [super viewDidLayoutSubviews];
    _appBar.sideInsets = UIEdgeInsetsMake(0, safe.left, 0, safe.right);
    _appBar.topInset = safe.top;
    _appBar.frame = CGRectMake(0, 0, bounds.size.width, barHeight);
    _contentView.frame = CGRectMake(0, barHeight, bounds.size.width, bounds.size.height - barHeight);
    _stateView.frame = _contentView.bounds;
    [self layoutContent];
}

- (FPOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation
{
    (void)orientation;
    return YES;
}

- (void)layoutContent {}
- (void)themeDidChange {}
- (void)reloadFromUser {}

- (void)showToast:(NSString *)text
{
    CGSize size;
    if (!_toast) {
        _toast = [[UILabel alloc] init];
        _toast.font = FPFont(14, 0, NO);
        _toast.textAlignment = NSTextAlignmentCenter;
        _toast.numberOfLines = 2;
        _toast.layer.cornerRadius = 16;
        _toast.layer.masksToBounds = YES;
        _toast.backgroundColor = FPColor(FPRoleOnSurface);
        _toast.textColor = FPColor(FPRoleSurface);
        _toast.alpha = 0;
    }
    _toast.text = text;
    if (!_toast.superview) [self.view addSubview:_toast];
    [self.view bringSubviewToFront:_toast];
    {
        UIEdgeInsets safe = FPSafeInsets(self.view);
        CGFloat width = MIN(self.view.bounds.size.width - 32 - safe.left - safe.right, 420);
        size = FPTextSize(text, _toast.font, width - 32);
        size.width = MIN(width, size.width + 32);
        size.height = MIN(60, size.height + 20);
        _toast.frame = CGRectMake((self.view.bounds.size.width - size.width) / 2,
                                  self.view.bounds.size.height - safe.bottom - 88 - size.height, size.width, size.height);
    }
    FPAnimate(0.3, ^{ _toast.alpha = 1; }, nil);
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideToast) object:nil];
    [self performSelector:@selector(hideToast) withObject:nil afterDelay:3.5];
}

- (void)hideToast
{
    [UIView animateWithDuration:0.25 animations:^{ _toast.alpha = 0; }];
}

- (void)installRefreshOn:(UIScrollView *)scroll
{
    Class refreshClass = NSClassFromString(@"UIRefreshControl");
    SEL property = NSSelectorFromString(@"setRefreshControl:");
    if (!refreshClass || _refresh) return;
    _refresh = [[refreshClass alloc] init];
    [_refresh addTarget:self action:@selector(reloadFromUser) forControlEvents:UIControlEventValueChanged];
    if ([scroll respondsToSelector:property]) ((void (*)(id, SEL, id))objc_msgSend)(scroll, property, _refresh);
    else [scroll addSubview:_refresh];
}

- (void)endRefreshing
{
    SEL end = NSSelectorFromString(@"endRefreshing");
    if ([_refresh respondsToSelector:end]) ((void (*)(id, SEL))objc_msgSend)(_refresh, end);
}

- (void)openForum:(NSInteger)forumId title:(NSString *)title
{
    FPTopicsController *controller = [[FPTopicsController alloc] initWithApi:_api forumId:forumId title:title];
    [self.navigationController pushViewController:controller animated:YES];
    [controller release];
}

- (void)openTopic:(NSInteger)topicId title:(NSString *)title offset:(NSInteger)offset
{
    FPPostsController *controller = [[FPPostsController alloc] initWithApi:_api topicId:topicId title:title offset:offset];
    [self.navigationController pushViewController:controller animated:YES];
    [controller release];
}

static NSInteger FPQueryNumber(NSString *url, NSString *name)
{
    NSRange key = [url rangeOfString:[name stringByAppendingString:@"="]];
    NSInteger value = 0;
    NSUInteger i;
    if (key.location == NSNotFound) return -1;
    for (i = key.location + key.length; i < [url length]; i++) {
        unichar c = [url characterAtIndex:i];
        if (c < '0' || c > '9') break;
        value = value * 10 + (c - '0');
        if (value > 100000000) return -1;
    }
    return i == key.location + key.length ? -1 : value;
}

static void FPOpenExternal(NSURL *url)
{
    UIApplication *app = [UIApplication sharedApplication];
    SEL modern = NSSelectorFromString(@"openURL:options:completionHandler:");
    if ([app respondsToSelector:modern]) {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(app, modern, url, [NSDictionary dictionary], nil);
    } else {
        [app performSelector:@selector(openURL:) withObject:url];
    }
}

- (void)openInBrowser:(NSURL *)url { FPOpenExternal(url); }

- (BOOL)openMember:(NSInteger)memberId link:(NSString *)url { (void)memberId; (void)url; return NO; }

- (void)openLink:(NSString *)url
{
    NSURL *parsed = [NSURL URLWithString:url];
    NSString *host = [[parsed host] lowercaseString];
    BOOL ours = [host isEqualToString:@"4pda.to"] || [host isEqualToString:@"4pda.ru"] || [host hasSuffix:@".4pda.to"] || [host hasSuffix:@".4pda.ru"];
    if (ours && [[parsed path] hasPrefix:@"/forum/index.php"]) {
        NSInteger topic = FPQueryNumber(url, @"showtopic"), forum = FPQueryNumber(url, @"showforum"), start = FPQueryNumber(url, @"st");
        if (topic > 0) { [self openTopic:topic title:nil offset:MAX(start, 0)]; return; }
        if (forum > 0) { [self openForum:forum title:nil]; return; }
        NSInteger member = FPQueryNumber(url, @"showuser");
        if (member > 0 && [self openMember:member link:url]) return;
    }
    if (!parsed || !([[parsed scheme] isEqualToString:@"https"] || [[parsed scheme] isEqualToString:@"http"] || [[parsed scheme] isEqualToString:@"mailto"])) {
        [self showToast:@"Эту ссылку нельзя открыть"];
        return;
    }
    if ([[parsed scheme] isEqualToString:@"mailto"]) { FPOpenExternal(parsed); return; }
    FPBrowserController *browser = [[FPBrowserController alloc] initWithApi:_api url:parsed];
    [self.navigationController pushViewController:browser animated:YES];
    [browser release];
}

- (void)pageSwipedBy:(NSInteger)direction { (void)direction; }

- (void)installPageSwipeOn:(UIView *)view
{
    UISwipeGestureRecognizer *left = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)];
    UISwipeGestureRecognizer *right = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)];
    left.direction = UISwipeGestureRecognizerDirectionLeft;
    right.direction = UISwipeGestureRecognizerDirectionRight;
    left.delegate = self;
    right.delegate = self;
    [view addGestureRecognizer:left];
    [view addGestureRecognizer:right];
    [left release];
    [right release];
}

- (void)swiped:(UISwipeGestureRecognizer *)gesture
{
    if (gesture.state == UIGestureRecognizerStateEnded) [self pageSwipedBy:gesture.direction == UISwipeGestureRecognizerDirectionLeft ? 1 : -1];
}

/* the first strip of the screen belongs to the edge swipe back, so page swipes start further in */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch
{
    (void)gesture;
    return [touch locationInView:self.view].x > EDGE_WIDTH;
}

@end

@implementation FPNavigationController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationBarHidden = YES;
    self.delegate = self;
    if ([self respondsToSelector:NSSelectorFromString(@"interactivePopGestureRecognizer")]) {
        [[self valueForKey:@"interactivePopGestureRecognizer"] setEnabled:NO];
    }
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(edgeSwiped:)];
    swipe.direction = UISwipeGestureRecognizerDirectionRight;
    swipe.delegate = self;
    [self.view addGestureRecognizer:swipe];
    [swipe release];
}

- (void)edgeSwiped:(UISwipeGestureRecognizer *)swipe
{
    if (swipe.state == UIGestureRecognizerStateEnded && [self.viewControllers count] > 1) [self popViewControllerAnimated:YES];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture
{
    (void)gesture;
    return [self.viewControllers count] > 1;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch
{
    if ([gesture isKindOfClass:[UISwipeGestureRecognizer class]]) return [touch locationInView:self.view].x <= EDGE_WIDTH;
    return YES;
}

- (void)animateNavigationFromRight:(BOOL)right
{
    if (FPReduceMotionEnabled()) return;
    CATransition *transition = [CATransition animation];
    transition.type = kCATransitionPush;
    transition.subtype = right ? kCATransitionFromRight : kCATransitionFromLeft;
    transition.duration = 0.32;
    transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.view.layer addAnimation:transition forKey:@"navigation"];
}

- (void)pushViewController:(UIViewController *)controller animated:(BOOL)animated
{
    if (animated && [self.viewControllers count]) [self animateNavigationFromRight:YES];
    [super pushViewController:controller animated:NO];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated
{
    if (animated && [self.viewControllers count] > 1) [self animateNavigationFromRight:NO];
    return [super popViewControllerAnimated:NO];
}

- (FPOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation
{
    (void)orientation;
    return YES;
}

@end
