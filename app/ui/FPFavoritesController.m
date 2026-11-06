#import "FPFavoritesController.h"
#import "FPFavorites.h"
#import "FPListKit.h"
#import "FPNewsController.h"
#import "FPNewsCell.h"
#import "FPTheme.h"
#import <QuartzCore/QuartzCore.h>

#define SWIPE_REVEAL 84.0f
#define SWIPE_PILL 52.0f
#define SWIPE_PILL_TAG 7301

@implementation FPFavoritesController
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.delegate = nil;
    _table.dataSource = nil;
    [_table release]; [_items release]; [_swipe release]; [_swipeItem release]; [_removing release];
    [super dealloc];
}

- (void)loadView
{
    [super loadView];
    self.appBar.title = @"4PDA";
    self.appBar.subtitle = @"Избранные";
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.delegate = self;
    _table.dataSource = self;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.backgroundColor = [UIColor clearColor];
    [self.contentView insertSubview:_table belowSubview:self.stateView];
    [self installRefreshOn:_table];
    /* the system delete button is a red rectangle that clips on the cards, so a swipe to the left shows a round button instead */
    _swipe = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)];
    _swipe.delegate = self;
    [_table addGestureRecognizer:_swipe];
    [_table.panGestureRecognizer requireGestureRecognizerToFail:_swipe];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadFavorites) name:FPFavoritesChangedNotification object:nil];
    [self reloadFavorites];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadFavorites];
    [self refreshFromServer];
}

- (void)reloadFromUser
{
    [self refreshFromServer];
}

/* a signed in member sees the list of the server; the copy on the device shows at once and is replaced when the answer is in */
- (void)refreshFromServer
{
    NSInteger member = [FPFavorites member];
    NSUInteger serial = ++_serial;
    if (member <= 0) { [self endRefreshing]; return; }
    [self.api loadFavorites:^(id topics, NSError *error) {
        /* an older answer, or one for a member who is gone, must not overwrite the list on screen */
        if (serial != _serial || member != [FPFavorites member]) return;
        [self endRefreshing];
        if (error) {
            [self showToast:[NSString stringWithFormat:@"Не удалось обновить избранное: %@", [error localizedDescription]]];
            return;
        }
        [FPFavorites replaceTopics:topics];
    }];
}

- (void)reloadFavorites
{
    NSArray *old = _items;
    NSArray *next = [[FPFavorites topics] arrayByAddingObjectsFromArray:[FPFavorites news]];
    NSUInteger gone = _removing ? [old indexOfObject:_removing] : NSNotFound;
    BOOL oneLess = gone != NSNotFound && [next count] + 1 == [old count] && ![next containsObject:_removing];
    _items = [next retain];
    [_swipeItem release]; _swipeItem = nil;
    if (oneLess) [_table deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:(NSInteger)gone inSection:0]] withRowAnimation:UITableViewRowAnimationFade];
    else [_table reloadData];
    [old release];
    [_removing release]; _removing = nil;
    if ([_items count]) self.stateView.hidden = YES;
    else [self.stateView showMessage:@"Избранных тем и новостей пока нет" retry:NO];
}

- (void)layoutContent
{
    UIEdgeInsets safe = FPSafeInsets(self.view);
    CGFloat previousWidth = _table.bounds.size.width;
    _table.frame = self.contentView.bounds;
    _table.contentInset = UIEdgeInsetsMake(4, 0, safe.bottom + 16, 0);
    _table.scrollIndicatorInsets = _table.contentInset;
    if (previousWidth != _table.bounds.size.width) [_table reloadData];
}

- (void)themeDidChange { [_table reloadData]; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section
{ (void)table; (void)section; return (NSInteger)[_items count]; }
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path
{
    NSDictionary *item = [_items objectAtIndex:(NSUInteger)path.row];
    if (![item objectForKey:@"id"]) return 118;
    NSString *title = [item objectForKey:@"id"] ? [item objectForKey:@"title"] : [@"Новость: " stringByAppendingString:[item objectForKey:@"title"]];
    return [FPRowView heightForKind:FPRowForum title:title subtitle:nil width:table.bounds.size.width sideInset:FPColumnInset(table.bounds.size.width, FPSafeInsets(self.view))];
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path
{
    NSDictionary *item = [_items objectAtIndex:(NSUInteger)path.row];
    if (![item objectForKey:@"id"]) {
        FPNewsCell *news = (FPNewsCell *)[table dequeueReusableCellWithIdentifier:@"favoriteNews"];
        if (!news) news = [[[FPNewsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"favoriteNews"] autorelease];
        [news configure:item inset:FPColumnInset(table.bounds.size.width, FPSafeInsets(self.view))];
        [self resetSwipeOfCell:news];
        return news;
    }
    FPListCell *cell = (FPListCell *)[table dequeueReusableCellWithIdentifier:@"favorite"];
    if (!cell) cell = [[[FPListCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"favorite"] autorelease];
    cell.row.kind = FPRowForum;
    cell.row.position = FPRowSingle;
    cell.row.title = [item objectForKey:@"id"] ? [item objectForKey:@"title"] : [@"Новость: " stringByAppendingString:[item objectForKey:@"title"]];
    cell.row.sideInset = FPColumnInset(table.bounds.size.width, FPSafeInsets(self.view));
    [cell.row setNeedsDisplay];
    [self resetSwipeOfCell:cell];
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path
{
    NSDictionary *item = [_items objectAtIndex:(NSUInteger)path.row];
    [table deselectRowAtIndexPath:path animated:YES];
    if (_swipeItem) { [self closeSwipe]; return; }
    if ([item objectForKey:@"id"]) [self openTopic:[[item objectForKey:@"id"] integerValue] title:[item objectForKey:@"title"] offset:-1];
    else {
        FPNewsArticleController *controller = [[FPNewsArticleController alloc] initWithApi:self.api item:item];
        [self.navigationController pushViewController:controller animated:YES];
        [controller release];
    }
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scroll { (void)scroll; [self closeSwipe]; }

- (UIButton *)deletePillOfCell:(UITableViewCell *)cell
{
    UIButton *pill = (UIButton *)[cell viewWithTag:SWIPE_PILL_TAG];
    if (!pill) {
        pill = [UIButton buttonWithType:UIButtonTypeCustom];
        pill.tag = SWIPE_PILL_TAG;
        pill.frame = CGRectMake(0, 0, SWIPE_PILL, SWIPE_PILL);
        pill.layer.cornerRadius = SWIPE_PILL / 2;
        pill.accessibilityLabel = @"Удалить";
        [pill setImage:FPIcon(FPIconClose, 22, FPColor(FPRoleOnErrorContainer)) forState:UIControlStateNormal];
        [pill addTarget:self action:@selector(pillTapped) forControlEvents:UIControlEventTouchUpInside];
        [cell insertSubview:pill belowSubview:cell.contentView];
    }
    FPClassicButtonFace(pill, NO);
    pill.layer.cornerRadius = FPThemeIsClassic() ? 6 : SWIPE_PILL / 2;
    pill.backgroundColor = FPThemeIsClassic() ? [UIColor clearColor] : FPColor(FPRoleErrorContainer);
    [pill setImage:FPIcon(FPIconClose, 22, FPThemeIsClassic() ? FPColor(FPRoleError) : FPColor(FPRoleOnErrorContainer)) forState:UIControlStateNormal];
    return pill;
}

/* the card follows the finger, the button trails its edge and grows as it comes out */
- (void)setSwipeOffset:(CGFloat)offset ofCell:(UITableViewCell *)cell
{
    CGFloat width = cell.bounds.size.width, inset = FPColumnInset(_table.bounds.size.width, FPSafeInsets(self.view));
    CGFloat reveal = MIN(1, offset / SWIPE_REVEAL);
    UIButton *pill = [self deletePillOfCell:cell];
    cell.contentView.transform = CGAffineTransformMakeTranslation(-offset, 0);
    pill.center = CGPointMake(width - inset - offset + 12 + SWIPE_PILL / 2, cell.bounds.size.height / 2);
    pill.alpha = MIN(1, offset / 40);
    pill.transform = CGAffineTransformMakeScale(0.5f + 0.5f * reveal, 0.5f + 0.5f * reveal);
}

- (void)resetSwipeOfCell:(UITableViewCell *)cell
{
    cell.contentView.transform = CGAffineTransformIdentity;
    [cell viewWithTag:SWIPE_PILL_TAG].alpha = 0;
}

- (UITableViewCell *)swipeCell
{
    NSUInteger row = _swipeItem ? [_items indexOfObject:_swipeItem] : NSNotFound;
    return row == NSNotFound ? nil : [_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
}

- (void)closeSwipe
{
    UITableViewCell *cell = [self swipeCell];
    [_swipeItem release]; _swipeItem = nil;
    if (!cell) return;
    FPAnimate(0.3, ^{ [self setSwipeOffset:0 ofCell:cell]; }, nil);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture
{
    if (gesture != _swipe) return YES;
    CGPoint velocity = [_swipe velocityInView:_table];
    return fabs(velocity.x) > fabs(velocity.y) * 1.5f && [_table indexPathForRowAtPoint:[_swipe locationInView:_table]] != nil;
}

- (void)swiped:(UIPanGestureRecognizer *)gesture
{
    UITableViewCell *cell;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        NSIndexPath *path = [_table indexPathForRowAtPoint:[gesture locationInView:_table]];
        NSDictionary *item = path ? [_items objectAtIndex:(NSUInteger)path.row] : nil;
        if (_swipeItem && ![_swipeItem isEqual:item]) [self closeSwipe];
        _swipeBase = [_swipeItem isEqual:item] ? SWIPE_REVEAL : 0;
        [_swipeItem release]; _swipeItem = [item retain];
    }
    cell = [self swipeCell];
    if (!cell) return;
    CGFloat offset = MAX(0, _swipeBase - [gesture translationInView:_table].x);
    if (gesture.state == UIGestureRecognizerStateChanged) {
        [self setSwipeOffset:offset ofCell:cell];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        CGFloat velocity = [gesture velocityInView:_table].x;
        if (gesture.state == UIGestureRecognizerStateEnded && (offset > cell.bounds.size.width * 0.45f || (velocity < -1100 && offset > 40))) [self removeSwipedItem];
        else if (gesture.state == UIGestureRecognizerStateEnded && offset > 42 && velocity < 300) FPAnimate(0.3, ^{ [self setSwipeOffset:SWIPE_REVEAL ofCell:cell]; }, nil);
        else [self closeSwipe];
    }
}

- (void)pillTapped { [self removeSwipedItem]; }

/* the card leaves first, then the row folds away when the list changes */
- (void)removeSwipedItem
{
    UITableViewCell *cell = [self swipeCell];
    NSDictionary *item = [[_swipeItem retain] autorelease];
    if (!cell || !item) return;
    CGFloat width = cell.bounds.size.width;
    [UIView animateWithDuration:FPReduceMotionEnabled() ? 0 : 0.22 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        cell.contentView.transform = CGAffineTransformMakeTranslation(-width, 0);
        [cell viewWithTag:SWIPE_PILL_TAG].alpha = 0;
    } completion:^(BOOL finished) {
        (void)finished;
        [self removeItem:item];
    }];
}

- (void)removeItem:(NSDictionary *)item
{
    if (![item objectForKey:@"id"]) { [self startRemoving:item]; [FPFavorites removeNews:[item objectForKey:@"url"]]; return; }
    NSInteger topicId = [[item objectForKey:@"id"] integerValue], member = [FPFavorites member];
    if (member <= 0) { [self startRemoving:item]; [FPFavorites removeTopic:topicId]; return; }
    /* the row leaves only after the server agrees, so a refused removal does not come back at the next refresh */
    [self.api setTopic:topicId favorite:NO completion:^(NSError *error) {
        if (error) {
            [self showToast:[NSString stringWithFormat:@"Не удалось убрать тему: %@", [error localizedDescription]]];
            NSUInteger row = [_items indexOfObject:item];
            UITableViewCell *cell = row == NSNotFound ? nil : [_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]];
            if (cell) FPAnimate(0.3, ^{ [self setSwipeOffset:0 ofCell:cell]; }, nil);
            return;
        }
        if (member == [FPFavorites member]) { [self startRemoving:item]; [FPFavorites removeTopic:topicId]; }
    }];
}

- (void)startRemoving:(NSDictionary *)item
{
    [_removing release]; _removing = [item retain];
}
@end
