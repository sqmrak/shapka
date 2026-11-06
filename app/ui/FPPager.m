#import "FPPager.h"
#import "FPTheme.h"
#import "FPChrome.h"
#import <QuartzCore/QuartzCore.h>

#define PAGER_HEIGHT 64.0f

@implementation FPPager
@synthesize delegate = _delegate, bottomInset = _bottomInset, page = _page, count = _count;

+ (CGFloat)contentHeight { return PAGER_HEIGHT; }

- (UIButton *)makeButton:(SEL)action
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.layer.cornerRadius = 22;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:button];
    return button;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _previous = [[self makeButton:@selector(previousTapped)] retain];
        _next = [[self makeButton:@selector(nextTapped)] retain];
        _label = [[self makeButton:@selector(jumpTapped)] retain];
        _label.titleLabel.font = FPFont(15, 1, NO);
        _label.layer.cornerRadius = 20;
        _previous.accessibilityLabel = @"Предыдущая страница";
        _next.accessibilityLabel = @"Следующая страница";
        _label.accessibilityLabel = @"Перейти к странице";
        [self applyTheme];
    }
    return self;
}

- (void)dealloc
{
    [_previous release]; [_next release]; [_label release];
    [super dealloc];
}

- (void)applyTheme
{
    self.backgroundColor = FPColor(FPRoleContainer);
    _label.backgroundColor = FPColor(FPRolePrimaryContainer);
    [_label setTitleColor:FPColor(FPRoleOnPrimaryContainer) forState:UIControlStateNormal];
    [_previous setImage:FPIcon(FPIconChevronLeft, 24, FPColor(_page > 0 ? FPRoleOnSurface : FPRoleOutline)) forState:UIControlStateNormal];
    [_next setImage:FPIcon(FPIconChevronRight, 24, FPColor(_page + 1 < _count ? FPRoleOnSurface : FPRoleOutline)) forState:UIControlStateNormal];
    _previous.backgroundColor = _page > 0 ? FPColor(FPRoleHighest) : [UIColor clearColor];
    _next.backgroundColor = _page + 1 < _count ? FPColor(FPRoleHighest) : [UIColor clearColor];
    for (UIButton *button in [NSArray arrayWithObjects:_previous, _label, _next, nil]) {
        FPClassicButtonFace(button, NO);
        button.layer.cornerRadius = FPThemeIsClassic() ? 6 : (button == _label ? 20 : 22);
        if (FPThemeIsClassic()) button.backgroundColor = [UIColor clearColor];
    }
    _label.titleLabel.font = FPFont(15, 1, NO);
}

- (void)setPage:(NSInteger)page count:(NSInteger)count
{
    _page = page;
    _count = count;
    [_label setTitle:[NSString stringWithFormat:@"%ld из %ld", (long)page + 1, (long)MAX(count, 1)] forState:UIControlStateNormal];
    _previous.enabled = page > 0;
    _next.enabled = page + 1 < count;
    _label.enabled = count > 1;
    [self applyTheme];
}

- (void)setBottomInset:(CGFloat)bottomInset
{
    _bottomInset = bottomInset;
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    CGFloat width = self.bounds.size.width, middle = 148, y = 10, side = 44;
    _label.frame = CGRectMake((width - middle) / 2, y, middle, 40 + 0);
    _previous.frame = CGRectMake(MAX(12, (width - middle) / 2 - side - 24), y - 2, side, side);
    _next.frame = CGRectMake(MIN(width - side - 12, (width + middle) / 2 + 24), y - 2, side, side);
}

- (void)previousTapped { [_delegate pagerDidSelectPrevious:self]; }
- (void)nextTapped { [_delegate pagerDidSelectNext:self]; }
- (void)jumpTapped { [_delegate pagerDidSelectJump:self]; }
@end
