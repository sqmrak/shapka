#import "FPScreenController.h"

@interface FPQMSController : FPScreenController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate> {
    UITableView *_table;
    NSArray *_rows;
    NSString *_heading;
    NSInteger _member;
    NSInteger _dialog;
    NSUInteger _serial;
    BOOL _loaded;
    BOOL _olderBusy;
    NSArray *_selectedFiles;
    UIActionSheet *_fileSheet;
    UIDocumentInteractionController *_documentController;
}
- (id)initWithApi:(FPApi *)api;
- (id)initWithApi:(FPApi *)api member:(NSInteger)member title:(NSString *)title;
- (id)initWithApi:(FPApi *)api dialog:(NSInteger)dialog title:(NSString *)title;
@end
