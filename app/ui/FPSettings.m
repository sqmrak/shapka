#import "FPSettings.h"
#import "FPTheme.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include "fp_theme_settings.h"

NSString *const FPSettingsChangedNotification = @"FPSettingsChanged";

static NSString *const kThemeMode = @"theme_mode";
static NSString *const kThemeStyle = @"theme_style";
static NSString *const kTextSize = @"text_size";
static NSString *const kHideMaterialEffect = @"hide_material_effect";
static NSString *const kAvatars = @"show_avatars";
static NSString *const kSignatures = @"show_signatures";
static NSString *const kPostsPerPage = @"posts_per_page";
static NSString *const kCategoryPrefix = @"category_closed_";

static void FPSettingsPost(void)
{
    [[NSNotificationCenter defaultCenter] postNotificationName:FPSettingsChangedNotification object:nil];
}

@interface FPSettings ()
+ (void)applyThemeStyle:(FPThemeStyle)style mode:(FPThemeMode)mode origin:(CGPoint)origin;
@end

@implementation FPSettings

static fp_theme_settings FPStoredTheme(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return fp_theme_settings_read((int)[defaults integerForKey:kThemeMode], [defaults objectForKey:kThemeStyle] != nil, (int)[defaults integerForKey:kThemeStyle]);
}

+ (FPThemeMode)themeMode { return FPStoredTheme().dark ? FPThemeModeDark : FPThemeModeLight; }
+ (FPThemeStyle)themeStyle { return FPStoredTheme().classic ? FPThemeStyleClassic : FPThemeStyleModern; }

+ (void)setThemeMode:(FPThemeMode)mode origin:(CGPoint)origin
{
    [self applyThemeStyle:[self themeStyle] mode:mode origin:origin];
}

+ (void)setThemeStyle:(FPThemeStyle)style origin:(CGPoint)origin
{
    [self applyThemeStyle:style mode:[self themeMode] origin:origin];
}

+ (void)applyThemeStyle:(FPThemeStyle)style mode:(FPThemeMode)mode origin:(CGPoint)origin
{
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    UIImage *snapshot = nil;
    UIImageView *overlay;
    CGRect bounds;
    CGFloat radius;
    CGMutablePathRef startPath, endPath;
    CAShapeLayer *mask;
    CABasicAnimation *animation;
    if (mode != FPThemeModeDark) mode = FPThemeModeLight;
    if (style != FPThemeStyleClassic) style = FPThemeStyleModern;
    if (!FPReduceMotionEnabled() && window && window.bounds.size.width > 0 && window.bounds.size.height > 0) {
        UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, MIN([[UIScreen mainScreen] scale], 2));
        [window.layer renderInContext:UIGraphicsGetCurrentContext()];
        snapshot = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    [[NSUserDefaults standardUserDefaults] setInteger:style forKey:kThemeStyle];
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kThemeMode];
    FPThemeApply();
    FPSettingsPost();
    if (!window || !snapshot) return;
    [window layoutIfNeeded];
    overlay = [[[UIImageView alloc] initWithImage:snapshot] autorelease];
    overlay.frame = window.bounds;
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.userInteractionEnabled = YES;
    [window addSubview:overlay];
    bounds = overlay.bounds;
    origin.x = MAX(CGRectGetMinX(bounds), MIN(origin.x, CGRectGetMaxX(bounds)));
    origin.y = MAX(CGRectGetMinY(bounds), MIN(origin.y, CGRectGetMaxY(bounds)));
    radius = hypot(MAX(origin.x, bounds.size.width - origin.x), MAX(origin.y, bounds.size.height - origin.y)) + 2;
    startPath = CGPathCreateMutable();
    CGPathAddRect(startPath, NULL, bounds);
    CGPathAddEllipseInRect(startPath, NULL, CGRectMake(origin.x - 0.5, origin.y - 0.5, 1, 1));
    endPath = CGPathCreateMutable();
    CGPathAddRect(endPath, NULL, bounds);
    CGPathAddEllipseInRect(endPath, NULL, CGRectMake(origin.x - radius, origin.y - radius, radius * 2, radius * 2));
    mask = [CAShapeLayer layer];
    mask.frame = bounds;
    mask.fillRule = kCAFillRuleEvenOdd;
    mask.path = endPath;
    overlay.layer.mask = mask;
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.6];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    [CATransaction setCompletionBlock:^{ [overlay removeFromSuperview]; }];
    animation = [CABasicAnimation animationWithKeyPath:@"path"];
    animation.fromValue = (id)startPath;
    animation.toValue = (id)endPath;
    [mask addAnimation:animation forKey:@"themeReveal"];
    [CATransaction commit];
    CGPathRelease(startPath);
    CGPathRelease(endPath);
}

+ (NSInteger)textSize
{
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kTextSize];
    if (![[NSUserDefaults standardUserDefaults] objectForKey:kTextSize]) return 1;
    return value < 0 ? 0 : (value > 2 ? 2 : value);
}

+ (void)setTextSize:(NSInteger)size
{
    [[NSUserDefaults standardUserDefaults] setInteger:size forKey:kTextSize];
    FPSettingsPost();
}

+ (CGFloat)textScale
{
    static const CGFloat scales[] = {0.88f, 1.0f, 1.15f};
    return scales[[self textSize]];
}

+ (BOOL)showMaterialEffect
{
    return ![[NSUserDefaults standardUserDefaults] boolForKey:kHideMaterialEffect];
}

+ (void)setShowMaterialEffect:(BOOL)show
{
    [[NSUserDefaults standardUserDefaults] setBool:!show forKey:kHideMaterialEffect];
    FPSettingsPost();
}

+ (BOOL)showAvatars
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kAvatars];
    return value ? [value boolValue] : YES;
}

+ (void)setShowAvatars:(BOOL)show
{
    [[NSUserDefaults standardUserDefaults] setBool:show forKey:kAvatars];
    FPSettingsPost();
}

+ (BOOL)showSignatures
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kSignatures];
    return value ? [value boolValue] : NO;
}

+ (void)setShowSignatures:(BOOL)show
{
    [[NSUserDefaults standardUserDefaults] setBool:show forKey:kSignatures];
    FPSettingsPost();
}

+ (NSArray *)postsPerPageChoices
{
    return [NSArray arrayWithObjects:[NSNumber numberWithInt:10], [NSNumber numberWithInt:20],
            [NSNumber numberWithInt:30], [NSNumber numberWithInt:50], nil];
}

+ (NSInteger)postsPerPage
{
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kPostsPerPage];
    return [[self postsPerPageChoices] containsObject:[NSNumber numberWithInteger:value]] ? value : 20;
}

+ (void)setPostsPerPage:(NSInteger)count
{
    [[NSUserDefaults standardUserDefaults] setInteger:count forKey:kPostsPerPage];
    FPSettingsPost();
}

+ (BOOL)isCategoryOpen:(NSInteger)categoryId
{
    return ![[NSUserDefaults standardUserDefaults] boolForKey:[kCategoryPrefix stringByAppendingFormat:@"%ld", (long)categoryId]];
}

+ (void)setCategory:(NSInteger)categoryId open:(BOOL)open
{
    NSString *key = [kCategoryPrefix stringByAppendingFormat:@"%ld", (long)categoryId];
    if (open) [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    else [[NSUserDefaults standardUserDefaults] setBool:YES forKey:key];
}

@end
