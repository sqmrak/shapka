#import "FPForumsController.h"
#import "FPListKit.h"
#import "FPSettings.h"
#import "FPLoginController.h"
#import "FPQMSController.h"

@implementation FPForumsController

- (id)initWithApi:(FPApi *)api
{
    self = [super initWithApi:api];
    if (self) {
        self.title = @"Форум";
        _rows = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    _table.delegate = nil;
    _table.dataSource = nil;
    [_table release]; [_index release]; [_rows release];
    [super dealloc];
}

- (void)loadView
{
    [super loadView];
    self.appBar.title = @"4PDA";
    self.appBar.subtitle = @"Форум";
    [self.appBar addActionWithIcon:FPIconPerson target:self action:@selector(openAccount)].accessibilityLabel = @"Аккаунт";
    [self.appBar addActionWithIcon:FPIconMessage target:self action:@selector(openMessages)].accessibilityLabel = @"Сообщения";
    [self.appBar addActionWithIcon:FPIconRefresh target:self action:@selector(reloadFromUser)].accessibilityLabel = @"Обновить";
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.dataSource = self;
    _table.delegate = self;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.backgroundColor = [UIColor clearColor];
    _table.showsVerticalScrollIndicator = YES;
    [self.contentView insertSubview:_table belowSubview:self.stateView];
    [self installRefreshOn:_table];
    /* the saved index fills the screen before the network answers */
    _index = [[self.api cachedForumIndex] retain];
    [self rebuildRows];
    if (![_index count]) [self.stateView showLoading];
}

- (void)openMessages
{
    FPQMSController *controller = [[FPQMSController alloc] initWithApi:self.api];
    [self.navigationController pushViewController:controller animated:YES];
    [controller release];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!_loadedOnce) {
        _loadedOnce = YES;
        [self load];
    }
}

- (void)themeDidChange
{
    _table.backgroundColor = [UIColor clearColor];
    [_table reloadData];
}

- (void)layoutContent
{
    UIEdgeInsets safe = FPSafeInsets(self.view);
    CGFloat previousWidth = _table.bounds.size.width;
    _table.frame = self.contentView.bounds;
    _table.contentInset = UIEdgeInsetsMake(0, 0, safe.bottom + 16, 0);
    _table.scrollIndicatorInsets = _table.contentInset;
    if (previousWidth != _table.bounds.size.width) [_table reloadData];
}

- (void)openAccount
{
    FPLoginController *controller = [[FPLoginController alloc] initWithApi:self.api];
    [self.navigationController pushViewController:controller animated:YES];
    [controller release];
}

- (void)reloadFromUser
{
    [self load];
}

- (void)load
{
    NSUInteger serial = ++_serial;
    _loading = YES;
    if (![_index count]) [self.stateView showLoading];
    [self.api loadForumIndex:^(id result, NSError *error) {
        /* an older answer must not replace the result of a newer request */
        if (serial != _serial) return;
        _loading = NO;
        [self endRefreshing];
        if (error) {
            if ([_index count]) [self showToast:[NSString stringWithFormat:@"Не удалось обновить: %@", [error localizedDescription]]];
            else [self.stateView showMessage:[error localizedDescription] retry:YES];
            return;
        }
        [_index release];
        _index = [result retain];
        [self rebuildRows];
        if ([_rows count]) self.stateView.hidden = YES;
        else [self.stateView showMessage:@"Список форумов пуст" retry:YES];
        [_table reloadData];
    }];
}

- (void)rebuildRows
{
    BOOL open = YES;
    FPForumEntry *entry;
    [_rows removeAllObjects];
    for (entry in _index) {
        if ([entry isCategory]) open = [FPSettings isCategoryOpen:entry.forumId];
        if ([entry isCategory] || open) [_rows addObject:entry];
    }
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section
{
    (void)table;
    (void)section;
    return (NSInteger)[_rows count];
}

- (FPRowPosition)positionAtIndex:(NSUInteger)i
{
    BOOL before = i > 0 && ![[_rows objectAtIndex:i - 1] isCategory];
    BOOL after = i + 1 < [_rows count] && ![[_rows objectAtIndex:i + 1] isCategory];
    if (before && after) return FPRowMiddle;
    if (before) return FPRowBottom;
    if (after) return FPRowTop;
    return FPRowSingle;
}

- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path
{
    FPForumEntry *entry = [_rows objectAtIndex:(NSUInteger)path.row];
    CGFloat width = table.bounds.size.width;
    return [FPRowView heightForKind:[entry isCategory] ? FPRowCategory : FPRowForum title:entry.title subtitle:nil
                              width:width sideInset:FPColumnInset(width, FPSafeInsets(self.view))];
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path
{
    static NSString *identifier = @"row";
    FPListCell *cell = (FPListCell *)[table dequeueReusableCellWithIdentifier:identifier];
    FPForumEntry *entry = [_rows objectAtIndex:(NSUInteger)path.row];
    FPRowView *row;
    if (!cell) cell = [[[FPListCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    row = cell.row;
    row.kind = [entry isCategory] ? FPRowCategory : FPRowForum;
    row.position = [entry isCategory] ? FPRowSingle : [self positionAtIndex:(NSUInteger)path.row];
    row.title = entry.title;
    row.unread = [entry hasUnread];
    row.expanded = [entry isCategory] && [FPSettings isCategoryOpen:entry.forumId];
    row.sideInset = FPColumnInset(table.bounds.size.width, FPSafeInsets(self.view));
    [row setNeedsDisplay];
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path
{
    FPForumEntry *entry = [_rows objectAtIndex:(NSUInteger)path.row];
    [table deselectRowAtIndexPath:path animated:YES];
    if ([entry isCategory]) {
        BOOL open = ![FPSettings isCategoryOpen:entry.forumId];
        [FPSettings setCategory:entry.forumId open:open];
        [self rebuildRows];
        [table reloadData];
        return;
    }
    if ([entry.url length]) [self openLink:entry.url];
    else [self openForum:entry.forumId title:entry.title];
}

- (void)scrollViewDidScroll:(UIScrollView *)scroll
{
    [self.appBar setElevated:scroll.contentOffset.y > 2];
}

@end
