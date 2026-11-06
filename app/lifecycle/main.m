#import <UIKit/UIKit.h>
#import "FPApi.h"
#import "FPRootController.h"
#import "FPScreenController.h"
#import "FPSettings.h"
#import "FPTheme.h"

@interface FPAppDelegate : UIResponder <UIApplicationDelegate> {
    UIWindow *_window;
    FPApi *_api;
}
@property (nonatomic, retain) UIWindow *window;
@end

@implementation FPAppDelegate
@synthesize window = _window;

- (void)applyStatusBar
{
    /* the bar content must stay readable over the app bar: light content in the dark theme */
    FPSendInteger([UIApplication sharedApplication], NSSelectorFromString(@"setStatusBarStyle:"), FPThemeIsDark() ? 1 : 0);
    _window.backgroundColor = FPColor(FPRoleSurface);
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    NSString *roots = [[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"];
    FPNetwork *network = [[FPNetwork alloc] initWithHost:@"appbk.4pda.to" rootsPath:roots];
    FPRootController *root;
    (void)application;
    (void)options;
    FPThemeRefresh();
    _api = [[FPApi alloc] initWithNetwork:network];
    [network release];
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    root = [[FPRootController alloc] initWithApi:_api];
    _window.rootViewController = root;
    [root release];
    [self applyStatusBar];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyStatusBar) name:FPThemeChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyStatusBar) name:FPSettingsChangedNotification object:nil];
    [_window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    (void)application;
    FPThemeRefresh();
    [_api resume];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    (void)application;
    [_api pause];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_api release];
    [_window release];
    [super dealloc];
}
@end

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int result = UIApplicationMain(argc, argv, nil, NSStringFromClass([FPAppDelegate class]));
    [pool drain];
    return result;
}
