#import "FPScreenController.h"
@interface FPForumsController : FPScreenController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_table;
    NSArray *_index;
    NSMutableArray *_rows;
    NSUInteger _serial;
    BOOL _loading;
    BOOL _loadedOnce;
}
@end
