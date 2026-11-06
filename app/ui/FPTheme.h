#import <UIKit/UIKit.h>

/* colors, type and shared drawing for the modern and classic themes */

extern NSString *const FPThemeChangedNotification;

/* the return type of supportedInterfaceOrientations differs between the ios 6 sdk of the armv7 slice and the current one */
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 70000
typedef UIInterfaceOrientationMask FPOrientationMask;
#else
typedef NSUInteger FPOrientationMask;
#endif

typedef enum {
    FPRoleSurface,
    FPRoleContainer,
    FPRoleHighest,
    FPRoleOnSurface,
    FPRoleOnVariant,
    FPRoleOutline,
    FPRoleDivider,
    FPRolePrimary,
    FPRoleOnPrimary,
    FPRolePrimaryContainer,
    FPRoleOnPrimaryContainer,
    FPRoleError,
    FPRoleErrorContainer,
    FPRoleOnErrorContainer,
    FPRoleLink,
    FPRoleCount
} FPRole;

BOOL FPThemeIsDark(void);
BOOL FPThemeIsClassic(void);
void FPClassicBar(UIView *view);
/* applies the stored theme without telling anyone */
void FPThemeApply(void);
/* posts FPThemeChangedNotification when the stored theme changed */
void FPThemeRefresh(void);
UIColor *FPColor(FPRole role);
UIColor *FPColorRGB(uint32_t rgb);
/* the color of a user group index from the forum protocol */
UIColor *FPGroupColor(NSInteger group);

/* weight 0 regular, 1 medium, 2 bold; the size is multiplied by the text size setting when scaled is YES */
UIFont *FPFont(CGFloat size, NSInteger weight, BOOL scaled);

typedef enum {
    FPIconBack,
    FPIconRefresh,
    FPIconSettings,
    FPIconPerson,
    FPIconChevronDown,
    FPIconChevronUp,
    FPIconChevronRight,
    FPIconChevronLeft,
    FPIconFile,
    FPIconClose,
    FPIconCheck,
    FPIconForum,
    FPIconStar,
    FPIconStarFilled,
    FPIconNews,
    FPIconHome,
    FPIconReply,
    FPIconMessage
} FPIconKind;

/* a tinted icon drawn at the screen scale and cached by kind, size and color */
UIImage *FPIcon(FPIconKind kind, CGFloat size, UIColor *color);

/* insets of the area free of the status bar, notch and home indicator, in the coordinates of the view */
UIEdgeInsets FPSafeInsets(UIView *view);

/* a spring on ios 7 and later, an ease out before that */
BOOL FPReduceMotionEnabled(void);
void FPAnimate(NSTimeInterval duration, void (^animations)(void), void (^completion)(BOOL finished));

/* sends a selector that the oldest sdk of the build does not declare; returns NO when the object lacks it */
BOOL FPSendBool(id object, SEL selector, BOOL value);
BOOL FPSendInteger(id object, SEL selector, NSInteger value);

/* the size a text takes in a width (zero or less for one line of any length), measured by CoreText on every system */
CGSize FPTextSize(NSString *text, UIFont *font, CGFloat width);

/* wrapped text in a rect, cut with an ellipsis after maxLines (zero for no limit); returns the height used;
   it draws into the current UIKit context, so lists need no label subviews */
CGFloat FPDrawText(NSString *text, UIFont *font, UIColor *color, CGRect rect, NSInteger maxLines);
/* the number of lines the same text takes, so heights and drawing agree */
NSInteger FPTextLines(NSString *text, UIFont *font, CGFloat width, NSInteger maxLines);
/* the height of one line of the font as the lists lay it out */
CGFloat FPLineHeight(UIFont *font);

/* a rounded rectangle with a radius per corner */
CGPathRef FPCreateRoundedRect(CGRect rect, CGFloat topLeft, CGFloat topRight, CGFloat bottomRight, CGFloat bottomLeft);

/* relative time text of a unix time: "сегодня, 14:05", "вчера, 09:30" or "29.10.26, 14:05" */
NSString *FPFormatDate(int64_t unixTime);
