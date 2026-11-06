#import "FPScreenController.h"
@interface FPSettingsController : FPScreenController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate> {
    UITableView *_table;
    NSArray *_rows;
    NSInteger _memberId;
    UIActionSheet *_choices;
    CGPoint _themeOrigin;
}
@end
