#import "FPTheme.h"
#import "FPSettings.h"
#import <objc/message.h>
#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>
#include <time.h>
#include <dlfcn.h>

NSString *const FPThemeChangedNotification = @"FPThemeChanged";

static BOOL gDark;
static BOOL gDarkKnown;
static FPThemeStyle gStyle;

BOOL FPThemeIsClassic(void)
{
    if (!gDarkKnown) FPThemeApply();
    return gStyle == FPThemeStyleClassic;
}

void FPClassicBar(UIView *view)
{
    CAGradientLayer *gradient = nil;
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer.name isEqualToString:@"fp.classic.bar"]) { gradient = (CAGradientLayer *)layer; break; }
    }
    if (!FPThemeIsClassic()) { [gradient removeFromSuperlayer]; return; }
    if (!gradient) {
        gradient = [CAGradientLayer layer];
        gradient.name = @"fp.classic.bar";
        [view.layer insertSublayer:gradient atIndex:0];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    gradient.frame = view.bounds;
    gradient.colors = FPThemeIsDark()
        ? [NSArray arrayWithObjects:(id)FPColorRGB(0x526C84).CGColor, (id)FPColorRGB(0x2A4055).CGColor, (id)FPColorRGB(0x182C40).CGColor, nil]
        : [NSArray arrayWithObjects:(id)FPColorRGB(0x83B9E4).CGColor, (id)FPColorRGB(0x397EB7).CGColor, (id)FPColorRGB(0x21649B).CGColor, nil];
    gradient.locations = [NSArray arrayWithObjects:@0, @0.49, @1, nil];
    [CATransaction commit];
}

BOOL FPThemeIsDark(void)
{
    if (!gDarkKnown) {
        FPThemeApply();
    }
    return gDark;
}

void FPThemeApply(void)
{
    FPThemeMode mode = [FPSettings themeMode];
    gStyle = [FPSettings themeStyle];
    gDark = mode == FPThemeModeDark;
    gDarkKnown = YES;
}

void FPThemeRefresh(void)
{
    BOOL beforeDark = FPThemeIsDark();
    FPThemeStyle beforeStyle = gStyle;
    FPThemeApply();
    if (beforeDark != gDark || beforeStyle != gStyle) [[NSNotificationCenter defaultCenter] postNotificationName:FPThemeChangedNotification object:nil];
}

UIColor *FPColorRGB(uint32_t rgb)
{
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0f green:((rgb >> 8) & 0xFF) / 255.0f blue:(rgb & 0xFF) / 255.0f alpha:1];
}

/* light and dark tones per role; the dark surfaces follow the 1f201f background of the android client */
static const uint32_t kLight[FPRoleCount] = {
    0xFAFBFF, 0xEDF1F9, 0xE0E5EF, 0x191C20, 0x43474E, 0x73777F, 0xD9DDE6, 0x1976D2, 0xFFFFFF, 0xD3E4FF, 0x001C3A,
    0xBA1A1A, 0xFFDAD6, 0x410002, 0x0072BC,
};
static const uint32_t kDark[FPRoleCount] = {
    0x1F201F, 0x292A29, 0x3A3B3A, 0xE2E2E0, 0xC4C7C5, 0x8E918F, 0x3F403F, 0xA5C8FF, 0x00315B, 0x0E2E49, 0xD3E4FF,
    0xFFB4AB, 0x93000A, 0xFFDAD6, 0x8CC8FF,
};

static const uint32_t kClassic[FPRoleCount] = {
    0xD8E2EC, 0xFFFFFF, 0xDCE8F3, 0x172332, 0x526579, 0x8495A5, 0xB4C2CF, 0x2169A6, 0xFFFFFF, 0xD4E8F8, 0x173C5D,
    0xB3261E, 0xFBE1DE, 0x410002, 0x17659E,
};

static const uint32_t kClassicDark[FPRoleCount] = {
    0x1B2632, 0x2C3947, 0x3D5061, 0xF2F5F8, 0xBAC8D6, 0x8799AA, 0x526474, 0x92C9F5, 0x102B42, 0x345572, 0xF2F8FF,
    0xFFB4AB, 0x793A3A, 0xFFE1DE, 0x9BD3FF,
};

UIColor *FPColor(FPRole role)
{
    static UIColor *cache[4][FPRoleCount];
    int dark = (FPThemeIsClassic() ? 2 : 0) + (FPThemeIsDark() ? 1 : 0);
    if (role < 0 || role >= FPRoleCount) return [UIColor blackColor];
    /* tiles of long messages draw on background threads */
    @synchronized([UIColor class]) {
        if (!cache[dark][role]) cache[dark][role] = [FPColorRGB(dark == 3 ? kClassicDark[role] : (dark == 2 ? kClassic[role] : (dark ? kDark[role] : kLight[role]))) retain];
    }
    return cache[dark][role];
}

UIColor *FPGroupColor(NSInteger group)
{
    /* index order of the protocol; zero means the plain text color */
    static const uint32_t light[] = {
        0, 0, 0, 0x008000, 0xFF0000, 0xA0A0A0, 0, 0x008000, 0xFF9900, 0x0099FF, 0x0000FF, 0x0099FF, 0x32CD32,
        0x800080, 0, 0xBC33FF, 0x000000, 0xB100BF, 0x9A60FF, 0x0099FF, 0x008B8B,
    };
    static const uint32_t dark[] = {
        0, 0, 0, 0x20A020, 0xFF5050, 0x808080, 0, 0x20A020, 0xFF9900, 0x4DB6FF, 0x6C8CFF, 0x4DB6FF, 0x32CD32,
        0xC060C0, 0, 0xBC33FF, 0xB0B0B0, 0xD060E0, 0x9A60FF, 0x4DB6FF, 0x00B4B4,
    };
    uint32_t rgb = 0;
    if (group >= 0 && group < (NSInteger)(sizeof(light) / sizeof(light[0]))) rgb = FPThemeIsDark() ? dark[group] : light[group];
    return rgb ? FPColorRGB(rgb) : FPColor(FPRoleOnSurface);
}

UIFont *FPFont(CGFloat size, NSInteger weight, BOOL scaled)
{
    static NSString *const names[] = {@"Rubik-Regular", @"Rubik-Medium", @"Rubik-Bold"};
    UIFont *font;
    if (scaled) size = floorf(size * [FPSettings textScale] + 0.5f);
    if (weight < 0) weight = 0;
    if (weight > 2) weight = 2;
    if (FPThemeIsClassic()) return weight == 0 ? [UIFont systemFontOfSize:size] : [UIFont boldSystemFontOfSize:size];
    font = [UIFont fontWithName:names[weight] size:size];
    if (font) return font;
    return weight == 0 ? [UIFont systemFontOfSize:size] : [UIFont boldSystemFontOfSize:size];
}

UIImage *FPIcon(FPIconKind kind, CGFloat size, UIColor *color)
{
    static NSString *const names[] = {
        @"ex_back", @"ex_retry", @"ex_gear", @"ex_person", @"ex_arrowdown", @"ex_arrowdown",
        @"ex_chevronright", @"ex_chevronright", @"ex_document", @"ex_close", @"ex_check", @"ex_chats",
        @"ex_fave", @"ex_star", @"ex_megaphone", @"ex_home", @"ex_compose", @"ex_chats"
    };
    static NSMutableDictionary *cache;
    CGFloat scale = [[UIScreen mainScreen] scale];
    CGFloat r = 0, g = 0, b = 0, a = 0;
    NSString *key;
    UIImage *image, *source;
    CGContextRef c;
    if (kind < 0 || kind >= (NSInteger)(sizeof(names) / sizeof(names[0])) || size <= 0 || !color) return nil;
    [color getRed:&r green:&g blue:&b alpha:&a];
    key = [NSString stringWithFormat:@"%d/%.1f/%.1f/%.0f/%.0f/%.0f/%.0f", (int)kind, size, scale, r * 255, g * 255, b * 255, a * 255];
    @synchronized([UIImage class]) {
        if (!cache) cache = [[NSMutableDictionary alloc] init];
        image = [[[cache objectForKey:key] retain] autorelease];
    }
    if (image) return image;
    source = [UIImage imageNamed:names[kind]];
    if (!source) { NSLog(@"Shapka: missing icon %@", names[kind]); return nil; }
    if (kind == FPIconChevronUp || kind == FPIconChevronLeft)
        source = [UIImage imageWithCGImage:source.CGImage scale:source.scale orientation:UIImageOrientationDown];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    c = UIGraphicsGetCurrentContext();
    [source drawInRect:CGRectMake(0, 0, size, size)];
    CGContextSetBlendMode(c, kCGBlendModeSourceIn);
    CGContextSetFillColorWithColor(c, color.CGColor);
    CGContextFillRect(c, CGRectMake(0, 0, size, size));
    image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) {
        @synchronized([UIImage class]) {
            if ([cache count] < 256) [cache setObject:image forKey:key];
        }
    }
    return image;
}

BOOL FPSendBool(id object, SEL selector, BOOL value)
{
    if (![object respondsToSelector:selector]) return NO;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(object, selector, value);
    return YES;
}

BOOL FPSendInteger(id object, SEL selector, NSInteger value)
{
    if (![object respondsToSelector:selector]) return NO;
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(object, selector, value);
    return YES;
}

UIEdgeInsets FPSafeInsets(UIView *view)
{
    SEL safe = NSSelectorFromString(@"safeAreaInsets");
    UIEdgeInsets insets = UIEdgeInsetsZero;
    if ([view respondsToSelector:safe]) {
        /* key-value coding boxes the struct, so no struct-returning message is sent by hand */
        insets = [[view valueForKey:@"safeAreaInsets"] UIEdgeInsetsValue];
    } else if (view.window) {
        /* before ios 11 only the status bar can overlap the view */
        CGRect bar = [view convertRect:[[UIApplication sharedApplication] statusBarFrame] fromView:nil];
        CGRect overlap = CGRectIntersection(bar, view.bounds);
        if (!CGRectIsNull(overlap)) insets.top = CGRectGetMaxY(overlap);
    }
    return insets;
}

BOOL FPReduceMotionEnabled(void)
{
    BOOL (*enabled)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "UIAccessibilityIsReduceMotionEnabled");
    return enabled && enabled();
}

void FPAnimate(NSTimeInterval duration, void (^animations)(void), void (^completion)(BOOL finished))
{
    if (FPReduceMotionEnabled()) {
        BOOL wasEnabled = [UIView areAnimationsEnabled];
        [UIView setAnimationsEnabled:NO];
        animations();
        [UIView setAnimationsEnabled:wasEnabled];
        if (completion) completion(YES);
        return;
    }
    SEL spring = NSSelectorFromString(@"animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:");
    if ([UIView respondsToSelector:spring]) {
        ((void (*)(id, SEL, NSTimeInterval, NSTimeInterval, CGFloat, CGFloat, UIViewAnimationOptions, void (^)(void), void (^)(BOOL)))objc_msgSend)(
            [UIView class], spring, duration, 0, 0.72f, 0.4f, UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction, animations, completion);
        return;
    }
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:animations completion:completion];
}

NSString *FPFormatDate(int64_t unixTime)
{
    time_t now = time(NULL), then = (time_t)unixTime;
    struct tm a, b;
    char text[40];
    if (unixTime <= 0) return @"";
    localtime_r(&then, &a);
    localtime_r(&now, &b);
    if (a.tm_year == b.tm_year && a.tm_yday == b.tm_yday) {
        snprintf(text, sizeof(text), "сегодня, %02d:%02d", a.tm_hour, a.tm_min);
    } else if ((a.tm_year == b.tm_year && a.tm_yday + 1 == b.tm_yday) || (a.tm_year + 1 == b.tm_year && a.tm_yday >= 364 && b.tm_yday == 0)) {
        snprintf(text, sizeof(text), "вчера, %02d:%02d", a.tm_hour, a.tm_min);
    } else {
        snprintf(text, sizeof(text), "%02d.%02d.%02d, %02d:%02d", a.tm_mday, a.tm_mon + 1, a.tm_year % 100, a.tm_hour, a.tm_min);
    }
    return [NSString stringWithUTF8String:text];
}

CGSize FPTextSize(NSString *text, UIFont *font, CGFloat width)
{
    CTFontRef ctFont;
    NSDictionary *attributes;
    NSAttributedString *string;
    CTFramesetterRef setter;
    CGSize size;
    if (![text length]) return CGSizeZero;
    ctFont = CTFontCreateWithName((CFStringRef)font.fontName, font.pointSize, NULL);
    attributes = [NSDictionary dictionaryWithObject:(id)ctFont forKey:(id)kCTFontAttributeName];
    CFRelease(ctFont);
    string = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    setter = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)string);
    size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRangeMake(0, 0), NULL,
                                                        CGSizeMake(width > 0 ? width : CGFLOAT_MAX, CGFLOAT_MAX), NULL);
    CFRelease(setter);
    [string release];
    return CGSizeMake(ceilf(size.width) + 1, ceilf(size.height) + 1);
}

CGFloat FPLineHeight(UIFont *font)
{
    return ceilf(font.lineHeight * 1.12f);
}

static CTFontRef FPCoreTextFont(UIFont *font)
{
    static NSMutableDictionary *cache;
    NSString *key = [NSString stringWithFormat:@"%@/%.1f", font.fontName, font.pointSize];
    NSValue *value;
    CTFontRef ct;
    @synchronized([UIFont class]) {
        if (!cache) cache = [[NSMutableDictionary alloc] init];
        value = [cache objectForKey:key];
        if (value) return (CTFontRef)[value pointerValue];
        ct = CTFontCreateWithName((CFStringRef)font.fontName, font.pointSize, NULL);
        /* faces times sizes times text scales is a small fixed set, so the fonts live as long as the app */
        if (ct) [cache setObject:[NSValue valueWithPointer:ct] forKey:key];
    }
    return ct;
}

/* breaks the text into at most maxLines lines; the last one is truncated when text remains;
   the caller releases the lines; draw is NO for pure measurement */
static NSInteger FPLayoutLines(NSString *text, UIFont *font, UIColor *color, CGRect rect, NSInteger maxLines, BOOL draw)
{
    CTFontRef ct = FPCoreTextFont(font);
    NSMutableDictionary *attributes;
    NSAttributedString *string;
    CTTypesetterRef typesetter;
    CFIndex start = 0, length;
    NSInteger count = 0;
    CGContextRef c = draw ? UIGraphicsGetCurrentContext() : NULL;
    CGFloat lineHeight = FPLineHeight(font), ascent = font.ascender + (lineHeight - ceilf(font.lineHeight)) / 2;
    if (![text length] || !ct || rect.size.width < 1) return 0;
    attributes = [NSMutableDictionary dictionaryWithObject:(id)ct forKey:(id)kCTFontAttributeName];
    if (color) [attributes setObject:(id)color.CGColor forKey:(id)kCTForegroundColorAttributeName];
    string = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    typesetter = CTTypesetterCreateWithAttributedString((CFAttributedStringRef)string);
    length = (CFIndex)[string length];
    if (draw) {
        CGContextSaveGState(c);
        CGContextSetTextMatrix(c, CGAffineTransformMakeScale(1, -1));
    }
    while (start < length && (maxLines <= 0 || count < maxLines)) {
        CFIndex n = CTTypesetterSuggestLineBreak(typesetter, start, rect.size.width);
        BOOL last = maxLines > 0 && count == maxLines - 1 && start + n < length;
        CTLineRef line;
        if (n <= 0) break;
        if (draw) {
            if (last) {
                CTLineRef whole = CTTypesetterCreateLine(typesetter, CFRangeMake(start, length - start));
                CFAttributedStringRef token = CFAttributedStringCreate(NULL, CFSTR("\u2026"), (CFDictionaryRef)attributes);
                CTLineRef ellipsis = CTLineCreateWithAttributedString(token);
                line = CTLineCreateTruncatedLine(whole, rect.size.width, kCTLineTruncationEnd, ellipsis);
                CFRelease(token);
                CFRelease(ellipsis);
                CFRelease(whole);
            } else {
                line = CTTypesetterCreateLine(typesetter, CFRangeMake(start, n));
            }
            if (line) {
                CGContextSetTextPosition(c, rect.origin.x, rect.origin.y + count * lineHeight + ascent);
                CTLineDraw(line, c);
                CFRelease(line);
            }
        }
        start += n;
        count++;
    }
    if (draw) CGContextRestoreGState(c);
    CFRelease(typesetter);
    [string release];
    return count;
}

CGFloat FPDrawText(NSString *text, UIFont *font, UIColor *color, CGRect rect, NSInteger maxLines)
{
    return FPLayoutLines(text, font, color, rect, maxLines, YES) * FPLineHeight(font);
}

NSInteger FPTextLines(NSString *text, UIFont *font, CGFloat width, NSInteger maxLines)
{
    return FPLayoutLines(text, font, nil, CGRectMake(0, 0, width, 0), maxLines, NO);
}

CGPathRef FPCreateRoundedRect(CGRect r, CGFloat tl, CGFloat tr, CGFloat br, CGFloat bl)
{
    CGMutablePathRef path = CGPathCreateMutable();
    CGFloat x0 = CGRectGetMinX(r), x1 = CGRectGetMaxX(r), y0 = CGRectGetMinY(r), y1 = CGRectGetMaxY(r);
    CGPathMoveToPoint(path, NULL, x0 + tl, y0);
    CGPathAddLineToPoint(path, NULL, x1 - tr, y0);
    CGPathAddArcToPoint(path, NULL, x1, y0, x1, y0 + tr, tr);
    CGPathAddLineToPoint(path, NULL, x1, y1 - br);
    CGPathAddArcToPoint(path, NULL, x1, y1, x1 - br, y1, br);
    CGPathAddLineToPoint(path, NULL, x0 + bl, y1);
    CGPathAddArcToPoint(path, NULL, x0, y1, x0, y1 - bl, bl);
    CGPathAddLineToPoint(path, NULL, x0, y0 + tl);
    CGPathAddArcToPoint(path, NULL, x0, y0, x0 + tl, y0, tl);
    CGPathCloseSubpath(path);
    return path;
}
