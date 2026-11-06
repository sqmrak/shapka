#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

extern NSString *const FPSettingsChangedNotification;

typedef enum { FPThemeModeLight = 1, FPThemeModeDark = 2 } FPThemeMode;
typedef enum { FPThemeStyleModern = 0, FPThemeStyleClassic = 1 } FPThemeStyle;

/* user choices kept in NSUserDefaults; every setter posts FPSettingsChangedNotification on the main thread */
@interface FPSettings : NSObject
+ (FPThemeMode)themeMode;
+ (FPThemeStyle)themeStyle;
+ (void)setThemeStyle:(FPThemeStyle)style origin:(CGPoint)origin;
+ (void)setThemeMode:(FPThemeMode)mode origin:(CGPoint)origin;
/* 0 small, 1 normal, 2 large, 3 largest */
+ (NSInteger)textSize;
+ (void)setTextSize:(NSInteger)size;
+ (CGFloat)textScale;
+ (BOOL)showMaterialEffect;
+ (void)setShowMaterialEffect:(BOOL)show;
+ (BOOL)showAvatars;
+ (void)setShowAvatars:(BOOL)show;
+ (BOOL)showSignatures;
+ (void)setShowSignatures:(BOOL)show;
+ (NSInteger)postsPerPage;
+ (void)setPostsPerPage:(NSInteger)count;
+ (NSArray *)postsPerPageChoices;
+ (BOOL)isCategoryOpen:(NSInteger)categoryId;
+ (void)setCategory:(NSInteger)categoryId open:(BOOL)open;
@end
