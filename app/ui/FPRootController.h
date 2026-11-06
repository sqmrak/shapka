#import <UIKit/UIKit.h>
#import "FPApi.h"

@interface FPRootController : UIViewController {
    FPApi *_api;
    NSMutableArray *_screens;
    UIViewController *_current;
    UIView *_bar;
    UIView *_indicator;
    NSMutableArray *_buttons;
    NSInteger _selected;
}
- (id)initWithApi:(FPApi *)api;
@end
