#import "FPChrome.h"
#import <QuartzCore/QuartzCore.h>

#define APP_BAR_HEIGHT 56.0f
#define ACTION_SIZE 44.0f

static UIImage *FPClassicButtonImage(BOOL onBar, BOOL dark, BOOL pressed, BOOL disabled)
{
    static UIImage *cache[2][2][2][2];
    UIImage *image = cache[onBar ? 1 : 0][dark ? 1 : 0][pressed ? 1 : 0][disabled ? 1 : 0];
    if (image) return image;
    uint32_t top, middle, bottom, border;
    if (onBar) {
        top = dark ? 0x71899E : 0xA0CEEF;
        middle = dark ? 0x3E5B73 : 0x548EBB;
        bottom = dark ? 0x293E50 : 0x2D70A5;
        border = dark ? 0x162838 : 0x1E5A89;
    } else {
        top = dark ? 0x718396 : 0xFFFFFF;
        middle = dark ? 0x4B6073 : 0xE4EDF5;
        bottom = dark ? 0x34495C : 0xC5D9EA;
        border = dark ? 0x1B2D3C : 0x8AA7BD;
    }
    if (pressed) { top = middle; middle = bottom; }
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(32, 32), NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGPathRef path = FPCreateRoundedRect(CGRectMake(0.5f, 0.5f, 31, 31), 6, 6, 6, 6);
    CGContextSaveGState(c);
    CGContextAddPath(c, path);
    CGContextClip(c);
    if (disabled) CGContextSetAlpha(c, 0.45f);
    NSArray *colors = [NSArray arrayWithObjects:(id)FPColorRGB(top).CGColor, (id)FPColorRGB(middle).CGColor,
                       (id)FPColorRGB(middle).CGColor, (id)FPColorRGB(bottom).CGColor, nil];
    CGFloat locations[] = {0, 0.48f, 0.5f, 1};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space, (CFArrayRef)colors, locations);
    CGContextDrawLinearGradient(c, gradient, CGPointMake(0, 0), CGPointMake(0, 32), 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(c);
    CGContextAddPath(c, path);
    CGContextSetStrokeColorWithColor(c, FPColorRGB(border).CGColor);
    CGContextSetLineWidth(c, 1);
    if (disabled) CGContextSetAlpha(c, 0.45f);
    CGContextStrokePath(c);
    CGPathRelease(path);
    image = [UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:8 topCapHeight:8];
    UIGraphicsEndImageContext();
    cache[onBar ? 1 : 0][dark ? 1 : 0][pressed ? 1 : 0][disabled ? 1 : 0] = [image retain];
    return image;
}

void FPClassicButtonFace(UIButton *button, BOOL onBar)
{
    BOOL classic = FPThemeIsClassic();
    BOOL dark = FPThemeIsDark();
    [button setBackgroundImage:classic ? FPClassicButtonImage(onBar, dark, NO, NO) : nil forState:UIControlStateNormal];
    [button setBackgroundImage:classic ? FPClassicButtonImage(onBar, dark, YES, NO) : nil forState:UIControlStateHighlighted];
    [button setBackgroundImage:classic ? FPClassicButtonImage(onBar, dark, NO, YES) : nil forState:UIControlStateDisabled];
}

static void FPButtonPress(UIView *view, BOOL pressed)
{
    if (FPThemeIsClassic() || FPReduceMotionEnabled()) {
        [view.layer removeAllAnimations];
        view.transform = CGAffineTransformIdentity;
        return;
    }
    CGAffineTransform target = pressed ? CGAffineTransformMakeScale(0.94f, 0.94f) : CGAffineTransformIdentity;
    if (CGAffineTransformEqualToTransform(view.transform, target)) return;
    if (pressed) {
        [view.layer removeAnimationForKey:@"fp.press.release"];
        [UIView animateWithDuration:0.10 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ view.transform = target; } completion:nil];
    } else {
        CALayer *presentation = (CALayer *)view.layer.presentationLayer;
        CGFloat scale = presentation ? [[presentation valueForKeyPath:@"transform.scale.x"] floatValue] : 0.94f;
        CAKeyframeAnimation *motion = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
        motion.values = [NSArray arrayWithObjects:[NSNumber numberWithFloat:scale], [NSNumber numberWithFloat:1.045f],
                         [NSNumber numberWithFloat:0.988f], [NSNumber numberWithFloat:1.0f], nil];
        motion.keyTimes = [NSArray arrayWithObjects:@0.0, @0.48, @0.75, @1.0, nil];
        motion.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        motion.duration = 0.36;
        [view.layer removeAllAnimations];
        view.transform = target;
        [view.layer addAnimation:motion forKey:@"fp.press.release"];
    }
}

@implementation FPPillButton
@synthesize quiet = _quiet;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.titleLabel.font = FPFont(15, 1, NO);
        self.layer.cornerRadius = 20;
        self.contentEdgeInsets = UIEdgeInsetsMake(0, 22, 0, 22);
        [self applyTheme];
    }
    return self;
}

- (void)setQuiet:(BOOL)quiet
{
    _quiet = quiet;
    [self applyTheme];
}

- (void)applyTheme
{
    self.titleLabel.font = FPFont(15, 1, NO);
    self.layer.cornerRadius = FPThemeIsClassic() ? 6 : 20;
    self.layer.borderWidth = 0;
    FPClassicButtonFace(self, NO);
    self.layer.borderColor = FPColor(FPRoleOutline).CGColor;
    self.backgroundColor = FPThemeIsClassic() || _quiet ? [UIColor clearColor] : FPColor(FPRolePrimaryContainer);
    [self setTitleColor:_quiet ? FPColor(FPRolePrimary) : FPColor(FPRoleOnPrimaryContainer) forState:UIControlStateNormal];
    [self setTitleColor:FPColor(FPRoleOutline) forState:UIControlStateDisabled];
    self.titleLabel.shadowColor = FPThemeIsClassic() ? (FPThemeIsDark() ? [UIColor blackColor] : [UIColor whiteColor]) : nil;
    self.titleLabel.shadowOffset = CGSizeMake(0, FPThemeIsDark() ? -1 : 1);
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    FPButtonPress(self, highlighted);
}

- (CGSize)sizeThatFits:(CGSize)size
{
    CGSize text = FPTextSize([self titleForState:UIControlStateNormal], self.titleLabel.font, 0);
    (void)size;
    return CGSizeMake(ceilf(text.width) + 44, 40);
}
@end

@interface FPActionButton : UIButton {
    FPIconKind _kind;
}
@property (nonatomic, assign) FPIconKind kind;
- (void)applyTheme;
@end

@implementation FPActionButton
@synthesize kind = _kind;
- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) self.layer.cornerRadius = ACTION_SIZE / 2;
    return self;
}
- (void)applyTheme
{
    [self setImage:FPIcon(_kind, 24, FPThemeIsClassic() ? [UIColor whiteColor] : FPColor(FPRoleOnSurface)) forState:UIControlStateNormal];
    FPClassicButtonFace(self, YES);
    self.backgroundColor = !FPThemeIsClassic() && self.highlighted ? FPColor(FPRoleHighest) : [UIColor clearColor];
}
- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    self.backgroundColor = !FPThemeIsClassic() && highlighted ? FPColor(FPRoleHighest) : [UIColor clearColor];
    FPButtonPress(self, highlighted);
}
@end

@implementation FPAppBar
@synthesize topInset = _topInset, sideInsets = _sideInsets, backButton = _backButton;

+ (CGFloat)contentHeight { return APP_BAR_HEIGHT; }

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _actions = [[NSMutableArray alloc] init];
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.backgroundColor = [UIColor clearColor];
        _subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _backButton = [[FPActionButton buttonWithType:UIButtonTypeCustom] retain];
        ((FPActionButton *)_backButton).kind = FPIconBack;
        _backButton.hidden = YES;
        _backButton.accessibilityLabel = @"Назад";
        [self addSubview:_titleLabel];
        [self addSubview:_subtitleLabel];
        [self addSubview:_backButton];
        self.clipsToBounds = NO;
        [self applyTheme];
    }
    return self;
}

- (void)dealloc
{
    [_titleLabel release]; [_subtitleLabel release]; [_backButton release]; [_actions release];
    [super dealloc];
}

- (NSString *)title { return _titleLabel.text; }
- (void)setTitle:(NSString *)title { _titleLabel.text = title; [self setNeedsLayout]; }
- (NSString *)subtitle { return _subtitleLabel.text; }
- (void)setSubtitle:(NSString *)subtitle { _subtitleLabel.text = subtitle; [self setNeedsLayout]; }
- (void)setTopInset:(CGFloat)topInset { _topInset = topInset; [self setNeedsLayout]; }
- (void)setSideInsets:(UIEdgeInsets)sideInsets { _sideInsets = sideInsets; [self setNeedsLayout]; }
- (void)setBackVisible:(BOOL)visible { _backButton.hidden = !visible; [self setNeedsLayout]; }

- (UIButton *)addActionWithIcon:(FPIconKind)kind target:(id)target action:(SEL)action
{
    FPActionButton *button = [FPActionButton buttonWithType:UIButtonTypeCustom];
    button.kind = kind;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [button applyTheme];
    [self addSubview:button];
    [_actions addObject:button];
    [self setNeedsLayout];
    return button;
}

- (void)setElevated:(BOOL)elevated
{
    if (elevated == _elevated || FPThemeIsClassic()) return;
    _elevated = elevated;
    [UIView animateWithDuration:0.2 animations:^{ self.backgroundColor = elevated ? FPColor(FPRoleContainer) : [UIColor clearColor]; }];
}

- (void)applyTheme
{
    FPActionButton *button;
    self.backgroundColor = _elevated ? FPColor(FPRoleContainer) : [UIColor clearColor];
    FPClassicBar(self);
    _titleLabel.textColor = FPThemeIsClassic() ? [UIColor whiteColor] : FPColor(FPRoleOnSurface);
    _subtitleLabel.textColor = FPThemeIsClassic() ? [UIColor whiteColor] : FPColor(FPRoleOnVariant);
    _titleLabel.shadowColor = FPThemeIsClassic() ? FPColorRGB(0x24577F) : nil;
    _titleLabel.shadowOffset = CGSizeMake(0, -1);
    [(FPActionButton *)_backButton applyTheme];
    for (button in _actions) [button applyTheme];
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    FPClassicBar(self);
    CGFloat width = self.bounds.size.width, left = _sideInsets.left + 4, right = width - _sideInsets.right - 4;
    CGFloat y = _topInset, textLeft, textRight, titleHeight;
    BOOL hasSubtitle = [_subtitleLabel.text length] > 0;
    FPActionButton *button;
    _backButton.frame = CGRectMake(left, y + (APP_BAR_HEIGHT - ACTION_SIZE) / 2, ACTION_SIZE, ACTION_SIZE);
    textLeft = _backButton.hidden ? _sideInsets.left + 20 : left + ACTION_SIZE + 4;
    for (button in _actions) {
        right -= ACTION_SIZE;
        button.frame = CGRectMake(right, y + (APP_BAR_HEIGHT - ACTION_SIZE) / 2, ACTION_SIZE, ACTION_SIZE);
    }
    textRight = right - 8;
    _titleLabel.font = FPFont(hasSubtitle ? 17 : 19, 1, NO);
    _subtitleLabel.font = FPFont(12, 0, NO);
    titleHeight = ceilf(_titleLabel.font.lineHeight);
    if (hasSubtitle) {
        CGFloat subtitleHeight = ceilf(_subtitleLabel.font.lineHeight), block = titleHeight + subtitleHeight;
        CGFloat top = y + floorf((APP_BAR_HEIGHT - block) / 2);
        _titleLabel.frame = CGRectMake(textLeft, top, MAX(0, textRight - textLeft), titleHeight);
        _subtitleLabel.frame = CGRectMake(textLeft, top + titleHeight, MAX(0, textRight - textLeft), subtitleHeight);
        _subtitleLabel.hidden = NO;
    } else {
        _titleLabel.frame = CGRectMake(textLeft, y + floorf((APP_BAR_HEIGHT - titleHeight) / 2), MAX(0, textRight - textLeft), titleHeight);
        _subtitleLabel.hidden = YES;
    }
}
@end

@implementation FPStateView
@synthesize retryButton = _retry;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        _spinner.hidesWhenStopped = YES;
        _message = [[UILabel alloc] init];
        _message.backgroundColor = [UIColor clearColor];
        _message.numberOfLines = 0;
        _message.textAlignment = NSTextAlignmentCenter;
        _retry = [[FPPillButton buttonWithType:UIButtonTypeCustom] retain];
        [_retry setTitle:@"Повторить" forState:UIControlStateNormal];
        /* a plain accent colored word under the message, as the retry of the exteria lists, not a filled pill */
        _retry.quiet = YES;
        _retry.titleLabel.font = FPFont(17, 1, NO);
        [self addSubview:_spinner];
        [self addSubview:_message];
        [self addSubview:_retry];
        self.hidden = YES;
        [self applyTheme];
    }
    return self;
}

- (void)dealloc
{
    [_spinner release]; [_message release]; [_retry release];
    [super dealloc];
}

- (void)applyTheme
{
    _message.textColor = FPColor(FPRoleOnVariant);
    _message.font = FPFont(16, 0, YES);
    _spinner.activityIndicatorViewStyle = FPThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray;
    [_retry applyTheme];
    [self setNeedsLayout];
}

- (void)showLoading
{
    self.hidden = NO;
    _message.hidden = YES;
    _retry.hidden = YES;
    [_spinner startAnimating];
    [self setNeedsLayout];
}

- (void)showMessage:(NSString *)message retry:(BOOL)retry
{
    self.hidden = NO;
    [_spinner stopAnimating];
    _message.hidden = NO;
    _message.text = message;
    _retry.hidden = !retry;
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    CGFloat width = MIN(self.bounds.size.width - 48, 420), x = (self.bounds.size.width - width) / 2;
    CGFloat textHeight = 0, total, y;
    CGSize pill = CGSizeMake(140, 40);
    if (!_message.hidden) textHeight = ceilf(FPTextSize(_message.text, _message.font, width).height);
    total = (_spinner.isAnimating ? 40 : 0) + textHeight + (_retry.hidden ? 0 : pill.height + 8);
    y = MAX(16, (self.bounds.size.height - total) / 2);
    _spinner.frame = CGRectMake((self.bounds.size.width - 37) / 2, y, 37, 37);
    if (_spinner.isAnimating) y += 40;
    _message.frame = CGRectMake(x, y, width, textHeight);
    y += textHeight + 8;
    _retry.frame = CGRectMake((self.bounds.size.width - pill.width) / 2, y, pill.width, pill.height);
}
@end

@implementation FPDialog

+ (FPDialog *)presentInView:(UIView *)host title:(NSString *)title message:(NSString *)message
                fieldText:(NSString *)fieldText numeric:(BOOL)numeric confirm:(NSString *)confirm handler:(FPDialogHandler)handler
{
    FPDialog *dialog = [[[FPDialog alloc] initWithFrame:host.bounds] autorelease];
    dialog.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dialog->_handler = [handler copy];
    dialog->_titleLabel.text = title;
    dialog->_messageLabel.text = message;
    [dialog->_confirm setTitle:confirm forState:UIControlStateNormal];
    if (fieldText) {
        dialog->_field = [[UITextField alloc] init];
        dialog->_field.text = fieldText;
        dialog->_field.font = FPFont(18, 0, NO);
        dialog->_field.textColor = FPColor(FPRoleOnSurface);
        dialog->_field.backgroundColor = FPColor(FPRoleHighest);
        dialog->_field.layer.cornerRadius = FPThemeIsClassic() ? 6 : 16;
        dialog->_field.textAlignment = NSTextAlignmentCenter;
        dialog->_field.keyboardType = numeric ? UIKeyboardTypeNumberPad : UIKeyboardTypeDefault;
        dialog->_field.returnKeyType = UIReturnKeyDone;
        dialog->_field.delegate = dialog;
        dialog->_field.keyboardAppearance = FPThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
        [dialog->_card addSubview:dialog->_field];
    }
    [host addSubview:dialog];
    dialog->_card.alpha = 0;
    dialog->_card.transform = CGAffineTransformMakeScale(0.85f, 0.85f);
    dialog.backgroundColor = [UIColor clearColor];
    FPAnimate(0.35, ^{
        dialog.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45f];
        dialog->_card.alpha = 1;
        dialog->_card.transform = CGAffineTransformIdentity;
    }, nil);
    [dialog setNeedsLayout];
    if (dialog->_field) [dialog->_field becomeFirstResponder];
    return dialog;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _card = [[UIView alloc] init];
        _card.backgroundColor = FPColor(FPRoleContainer);
        _card.layer.cornerRadius = FPThemeIsClassic() ? 8 : 28;
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = FPFont(22, 1, NO);
        _titleLabel.textColor = FPColor(FPRoleOnSurface);
        _titleLabel.numberOfLines = 0;
        _messageLabel = [[UILabel alloc] init];
        _messageLabel.backgroundColor = [UIColor clearColor];
        _messageLabel.font = FPFont(15, 0, NO);
        _messageLabel.textColor = FPColor(FPRoleOnVariant);
        _messageLabel.numberOfLines = 0;
        _confirm = [[FPPillButton buttonWithType:UIButtonTypeCustom] retain];
        _cancel = [[FPPillButton buttonWithType:UIButtonTypeCustom] retain];
        _cancel.quiet = YES;
        [_cancel setTitle:@"Отмена" forState:UIControlStateNormal];
        [_confirm addTarget:self action:@selector(confirmed) forControlEvents:UIControlEventTouchUpInside];
        [_cancel addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_card];
        [_card addSubview:_titleLabel];
        [_card addSubview:_messageLabel];
        [_card addSubview:_confirm];
        [_card addSubview:_cancel];
    }
    return self;
}

- (void)dealloc
{
    [_card release]; [_titleLabel release]; [_messageLabel release]; [_field release];
    [_confirm release]; [_cancel release]; [_handler release];
    [super dealloc];
}

- (void)layoutSubviews
{
    CGFloat width = MIN(self.bounds.size.width - 48, 340), inner = width - 48, y = 24, height;
    CGSize title = FPTextSize(_titleLabel.text, _titleLabel.font, inner);
    CGSize text = [_messageLabel.text length] ? FPTextSize(_messageLabel.text, _messageLabel.font, inner) : CGSizeZero;
    CGSize ok = [_confirm sizeThatFits:CGSizeZero], no = [_cancel sizeThatFits:CGSizeZero];
    _titleLabel.frame = CGRectMake(24, y, inner, ceilf(title.height));
    y += ceilf(title.height) + 12;
    _messageLabel.frame = CGRectMake(24, y, inner, ceilf(text.height));
    if (text.height > 0) y += ceilf(text.height) + 16;
    if (_field) {
        _field.frame = CGRectMake(24, y, inner, 52);
        y += 52 + 16;
    }
    _confirm.frame = CGRectMake(width - 24 - ok.width, y, ok.width, 40);
    _cancel.frame = CGRectMake(CGRectGetMinX(_confirm.frame) - 8 - no.width, y, no.width, 40);
    height = y + 40 + 24;
    _card.bounds = CGRectMake(0, 0, width, height);
    /* a field puts the card in the upper part so the keyboard never covers it */
    _card.center = CGPointMake(self.bounds.size.width / 2, _field ? MIN(self.bounds.size.height / 2, height / 2 + 72) : self.bounds.size.height / 2);
}

- (void)confirmed
{
    NSString *text = [[_field.text copy] autorelease];
    FPDialogHandler handler = [[_handler retain] autorelease];
    [self dismiss];
    if (handler) handler(text);
}

- (BOOL)textFieldShouldReturn:(UITextField *)field
{
    (void)field;
    [self confirmed];
    return NO;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    (void)event;
    if (!CGRectContainsPoint(_card.frame, [touch locationInView:self])) [self dismiss];
}

- (void)dismiss
{
    [_field resignFirstResponder];
    self.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.18 animations:^{
        self.alpha = 0;
        _card.transform = CGAffineTransformMakeScale(0.9f, 0.9f);
    } completion:^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
    }];
}
@end
