#import "FPRootController.h"
#import "FPScreenController.h"
#import "FPNewsController.h"
#import "FPForumsController.h"
#import "FPFavoritesController.h"
#import "FPSettingsController.h"
#import "FPSettings.h"
#import "FPFavorites.h"
#import <QuartzCore/QuartzCore.h>

#define FP_TAB_HEIGHT 62.0f

@interface FPTabButton : UIButton
@end
@implementation FPTabButton
- (void)layoutSubviews
{
    [super layoutSubviews];
    self.imageView.frame = CGRectMake((self.bounds.size.width - 24) / 2, 7, 24, 24);
    self.titleLabel.frame = CGRectMake(0, 36, self.bounds.size.width, 16);
}
@end

@implementation FPRootController
- (id)initWithApi:(FPApi *)api
{
    self = [super init];
    if (self) {
        _api = [api retain];
        _selected = -1;
        _screens = [[NSMutableArray alloc] initWithObjects:[NSNull null], [NSNull null], [NSNull null], [NSNull null], nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:FPSettingsChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountChanged:) name:FPApiAccountNotification object:_api];
        [FPFavorites setMember:[_api memberId]];
    }
    return self;
}
- (void)accountChanged:(NSNotification *)note
{
    (void)note;
    [FPFavorites setMember:[_api memberId]];
}
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_api release]; [_screens release]; [_indicator release]; [_bar release]; [_buttons release];
    [super dealloc];
}
- (void)loadView
{
    UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = view; [view release];
    _bar = [[UIView alloc] init];
    [self.view addSubview:_bar];
    _indicator = [[UIView alloc] init];
    _indicator.userInteractionEnabled = NO;
    _indicator.layer.cornerRadius = 16;
    [_bar addSubview:_indicator];
    _buttons = [[NSMutableArray alloc] init];
    NSArray *titles = [NSArray arrayWithObjects:@"Главная", @"Форум", @"Избранные", @"Настройки", nil];
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *button = [[[FPTabButton alloc] initWithFrame:CGRectZero] autorelease];
        button.tag = i;
        button.accessibilityLabel = [titles objectAtIndex:(NSUInteger)i];
        button.titleLabel.font = FPFont(10, 1, NO);
        button.titleLabel.textAlignment = NSTextAlignmentCenter;
        [button setTitle:[titles objectAtIndex:(NSUInteger)i] forState:UIControlStateNormal];
        [button addTarget:self action:@selector(selectButton:) forControlEvents:UIControlEventTouchUpInside];
        [_bar addSubview:button]; [_buttons addObject:button];
    }
    [self showTab:0];
    [self applyTheme];
}
- (UIViewController *)screenForTab:(NSInteger)tab
{
    id screen = [_screens objectAtIndex:(NSUInteger)tab];
    if (screen != [NSNull null]) return screen;
    FPScreenController *root;
    switch (tab) {
    case 0: root = [[FPNewsController alloc] initWithApi:_api]; break;
    case 1: root = [[FPForumsController alloc] initWithApi:_api]; break;
    case 2: root = [[FPFavoritesController alloc] initWithApi:_api]; break;
    default: root = [[FPSettingsController alloc] initWithApi:_api]; break;
    }
    FPNavigationController *navigation = [[FPNavigationController alloc] initWithRootViewController:root];
    [root release];
    [_screens replaceObjectAtIndex:(NSUInteger)tab withObject:navigation];
    [navigation release];
    return [_screens objectAtIndex:(NSUInteger)tab];
}
- (void)selectButton:(UIButton *)button { [self showTab:button.tag]; }
- (void)showTab:(NSInteger)tab
{
    if (tab < 0 || tab >= 4 || tab == _selected) return;
    UIViewController *next = [self screenForTab:tab];
    UIViewController *old = _current;
    if (old) {
        [old willMoveToParentViewController:nil];
        [old beginAppearanceTransition:NO animated:NO];
    }
    [self addChildViewController:next];
    next.view.frame = [self screenFrame];
    next.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:next.view belowSubview:_bar];
    [next beginAppearanceTransition:YES animated:NO];
    [next endAppearanceTransition];
    [next didMoveToParentViewController:self];
    BOOL fromRight = tab > _selected;
    CGRect frame = [self screenFrame];
    BOOL slide = old != nil;
    if (slide) {
        /* the new screen enters from the side of its tab in the bar, the old one leaves the other way */
        CGFloat shift = fromRight ? frame.size.width : -frame.size.width;
        next.view.frame = CGRectOffset(frame, shift, 0);
    }
    if (old) {
        [old endAppearanceTransition];
        [old removeFromParentViewController];
    }
    _current = next; _selected = tab;
    CGFloat tabWidth = _bar.bounds.size.width / 4;
    CGRect indicatorFrame = CGRectMake(tabWidth * tab + (tabWidth - 64) / 2, 3, 64, 32);
    if (old && tabWidth > 0) FPAnimate(0.28, ^{ _indicator.frame = indicatorFrame; }, nil);
    else _indicator.frame = indicatorFrame;
    void (^finish)(BOOL) = ^(BOOL finished) {
        (void)finished;
        if (old.view != _current.view) [old.view removeFromSuperview];
    };
    if (slide) {
        CGFloat shift = fromRight ? -frame.size.width : frame.size.width;
        FPAnimate(0.28, ^{
            next.view.frame = frame;
            old.view.frame = CGRectOffset(frame, shift, 0);
        }, finish);
    } else {
        next.view.frame = frame;
        finish(YES);
    }
    [self applyTheme];
}
- (CGRect)screenFrame
{
    CGRect bounds = self.view.bounds;
    CGFloat bottom = FPSafeInsets(self.view).bottom;
    bounds.size.height = MAX(0, bounds.size.height - FP_TAB_HEIGHT - bottom);
    return bounds;
}
- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat bottom = FPSafeInsets(self.view).bottom;
    _bar.frame = CGRectMake(0, bounds.size.height - FP_TAB_HEIGHT - bottom, bounds.size.width, FP_TAB_HEIGHT + bottom);
    FPClassicBar(_bar);
    _current.view.frame = [self screenFrame];
    CGFloat width = _bar.bounds.size.width / 4;
    _indicator.frame = CGRectMake(width * _selected + (width - 64) / 2, 3, 64, 32);
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *button = [_buttons objectAtIndex:(NSUInteger)i];
        button.frame = CGRectMake(width * i, 0, width, FP_TAB_HEIGHT);
    }
}
- (void)themeChanged:(NSNotification *)notification { (void)notification; if ([self isViewLoaded]) [self applyTheme]; }
- (void)applyTheme
{
    static const FPIconKind icons[] = {FPIconHome, FPIconForum, FPIconStar, FPIconSettings};
    self.view.backgroundColor = FPColor(FPRoleSurface);
    _bar.backgroundColor = FPColor(FPRoleContainer);
    FPClassicBar(_bar);
    _indicator.backgroundColor = FPThemeIsClassic() ? [UIColor colorWithWhite:1 alpha:0.22f] : FPColor(FPRolePrimaryContainer);
    _indicator.layer.cornerRadius = FPThemeIsClassic() ? 5 : 16;
    for (NSInteger i = 0; i < 4; i++) {
        UIButton *button = [_buttons objectAtIndex:(NSUInteger)i];
        UIColor *color = FPThemeIsClassic() ? [UIColor colorWithWhite:1 alpha:i == _selected ? 1 : 0.7f] : FPColor(i == _selected ? FPRolePrimary : FPRoleOnVariant);
        button.titleLabel.font = FPFont(10, 1, NO);
        [button setImage:FPIcon(icons[i], 24, color) forState:UIControlStateNormal];
        [button setTitleColor:color forState:UIControlStateNormal];
        button.accessibilityTraits = UIAccessibilityTraitButton | (i == _selected ? UIAccessibilityTraitSelected : 0);
    }
    [self.view setNeedsLayout];
}
- (FPOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { (void)orientation; return YES; }
@end
