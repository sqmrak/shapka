#import "FPWaveBackground.h"
#import "FPSettings.h"
#import "FPTheme.h"
#include <math.h>
#include <dlfcn.h>

@implementation FPWaveBackground
- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.clipsToBounds = YES;
        _wave = [[CAGradientLayer alloc] init];
        _shape = [[CAShapeLayer alloc] init];
        _wave.mask = _shape;
        _wave.startPoint = CGPointMake(0, 0);
        _wave.endPoint = CGPointMake(0.4f, 0.3f);
        [self.layer addSublayer:_wave];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(motionChanged:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(motionChanged:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        NSString **motionName = (NSString **)dlsym(RTLD_DEFAULT, "UIAccessibilityReduceMotionStatusDidChangeNotification");
        if (motionName && *motionName) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(motionChanged:) name:*motionName object:nil];
        [self applyTheme];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_wave release]; [_shape release];
    [super dealloc];
}

- (CGPathRef)newPathWithAmplitude:(CGFloat)amplitude
{
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat span = MIN(h, w * 4.0f / 3.0f);
    CGPoint from = CGPointMake(0.46f * w, 0), control = CGPointMake(0.30f * w, 0.28f * span), to = CGPointMake(0, 0.36f * span);
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, 0, 0);
    CGPathAddLineToPoint(path, NULL, from.x, from.y);
    for (int i = 1; i <= 96; i++) {
        CGFloat t = (CGFloat)i / 96, u = 1 - t;
        CGFloat x = u * u * from.x + 2 * u * t * control.x + t * t * to.x;
        CGFloat y = u * u * from.y + 2 * u * t * control.y + t * t * to.y;
        CGFloat dx = 2 * u * (control.x - from.x) + 2 * t * (to.x - control.x);
        CGFloat dy = 2 * u * (control.y - from.y) + 2 * t * (to.y - control.y);
        CGFloat length = sqrtf(dx * dx + dy * dy);
        CGFloat offset = amplitude * sinf(2 * M_PI * 3.5f * t) * sinf(M_PI * t);
        if (length > 0) { x -= dy / length * offset; y += dx / length * offset; }
        CGPathAddLineToPoint(path, NULL, x, y);
    }
    CGPathCloseSubpath(path);
    return path;
}

- (void)applyTheme
{
    self.backgroundColor = FPColor(FPRoleSurface);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _wave.hidden = FPThemeIsClassic() || ![FPSettings showMaterialEffect];
    _wave.colors = FPThemeIsDark()
        ? [NSArray arrayWithObjects:(id)[UIColor colorWithRed:0.17 green:0.39 blue:0.67 alpha:0.55].CGColor, (id)[UIColor colorWithRed:0.12 green:0.25 blue:0.44 alpha:0.08].CGColor, nil]
        : [NSArray arrayWithObjects:(id)[UIColor colorWithRed:0.40 green:0.68 blue:0.95 alpha:0.48].CGColor, (id)[UIColor colorWithRed:0.72 green:0.84 blue:1.0 alpha:0.08].CGColor, nil];
    [CATransaction commit];
    [self updateMotion];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _wave.frame = self.bounds;
    _shape.frame = _wave.bounds;
    CGPathRef path = [self newPathWithAmplitude:0.03f * self.bounds.size.width];
    _shape.path = path;
    CGPathRelease(path);
    [CATransaction commit];
    [self updateMotion];
}

- (void)updateMotion
{
    [_shape removeAnimationForKey:@"ripple"];
    if (!self.window || _wave.hidden || [UIApplication sharedApplication].applicationState != UIApplicationStateActive ||
        FPReduceMotionEnabled() || self.bounds.size.width <= 0 || !_shape.path) return;
    CGPathRef opposite = [self newPathWithAmplitude:-0.03f * self.bounds.size.width];
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"path"];
    animation.fromValue = (id)_shape.path;
    animation.toValue = (id)opposite;
    animation.duration = 3.2;
    animation.autoreverses = YES;
    animation.repeatCount = HUGE_VALF;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_shape addAnimation:animation forKey:@"ripple"];
    CGPathRelease(opposite);
}

- (void)motionChanged:(NSNotification *)notification
{
    (void)notification;
    [self updateMotion];
}

- (void)didMoveToWindow
{
    [super didMoveToWindow];
    [self updateMotion];
}
@end
