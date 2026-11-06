#import "FPTopicsController.h"
#import "FPListKit.h"
#import "FPAnnouncementController.h"
#import <QuartzCore/QuartzCore.h>

#define TOPICS_PER_PAGE 30

@interface FPTopicsItem : NSObject {
@public
    FPRowKind kind;
    FPRowPosition position;
    id object;
    NSString *label;
}
@end

@implementation FPTopicsItem
- (void)dealloc { [object release]; [label release]; [super dealloc]; }
@end

@interface FPTopicsController ()
- (void)loadPage:(NSInteger)index direction:(NSInteger)direction;
- (void)rebuildItems;
@end

@implementation FPTopicsController

- (id)initWithApi:(FPApi *)api forumId:(NSInteger)forumId title:(NSString *)title
{
    self = [super initWithApi:api];
    if (self) {
        _forumId = forumId;
        _forumTitle = [title copy];
        _items = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    _table.delegate = nil;
    _table.dataSource = nil;
    _pager.delegate = nil;
    [_table release]; [_pager release]; [_page release]; [_forumTitle release]; [_items release];
    [super dealloc];
}

- (void)loadView
{
    [super loadView];
    self.appBar.title = [_forumTitle length] ? _forumTitle : @"Форум";
    [self.appBar addActionWithIcon:FPIconRefresh target:self action:@selector(reloadFromUser)].accessibilityLabel = @"Обновить";
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.dataSource = self;
    _table.delegate = self;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.backgroundColor = [UIColor clearColor];
    [self.contentView insertSubview:_table belowSubview:self.stateView];
    _pager = [[FPPager alloc] init];
    _pager.delegate = self;
    _pager.hidden = YES;
    [self.contentView addSubview:_pager];
    [self installRefreshOn:_table];
    [self installPageSwipeOn:_table];
    [self.stateView showLoading];
    [self loadPage:0 direction:0];
}

- (void)themeDidChange
{
    _table.backgroundColor = [UIColor clearColor];
    [_pager applyTheme];
    [_table reloadData];
}

- (void)layoutContent
{
    UIEdgeInsets safe = FPSafeInsets(self.view);
    CGRect bounds = self.contentView.bounds;
    CGFloat previousWidth = _table.bounds.size.width;
    CGFloat pagerHeight = _pager.hidden ? 0 : [FPPager contentHeight] + safe.bottom;
    _pager.frame = CGRectMake(0, bounds.size.height - pagerHeight, bounds.size.width, pagerHeight);
    _pager.bottomInset = safe.bottom;
    _table.frame = CGRectMake(0, 0, bounds.size.width, bounds.size.height - pagerHeight);
    _table.contentInset = UIEdgeInsetsMake(0, 0, pagerHeight ? 8 : safe.bottom + 16, 0);
    _table.scrollIndicatorInsets = _table.contentInset;
    if (previousWidth != _table.bounds.size.width) [_table reloadData];
}

- (void)reloadFromUser
{
    [self loadPage:_pageIndex direction:0];
}

- (NSInteger)pageCount
{
    long long total = _page ? _page.topicTotal : 0;
    return total > 0 ? (NSInteger)((total + TOPICS_PER_PAGE - 1) / TOPICS_PER_PAGE) : 1;
}

- (void)loadPage:(NSInteger)index direction:(NSInteger)direction
{
    NSUInteger serial = ++_serial;
    _loading = YES;
    /* the page on screen stays, only dimmed, until the new one arrives */
    if (_page) FPAnimate(0.2, ^{ _table.alpha = 0.55f; }, nil);
    [self.api loadForum:_forumId offset:index * TOPICS_PER_PAGE count:TOPICS_PER_PAGE completion:^(id result, NSError *error) {
        if (serial != _serial) return;
        _loading = NO;
        [self endRefreshing];
        FPAnimate(0.2, ^{ _table.alpha = 1; }, nil);
        if (error) {
            if (_page) [self showToast:[NSString stringWithFormat:@"Не удалось загрузить: %@", [error localizedDescription]]];
            else [self.stateView showMessage:[error localizedDescription] retry:YES];
            return;
        }
        if (direction != 0 && !FPReduceMotionEnabled()) {
            CATransition *transition = [CATransition animation];
            transition.type = kCATransitionPush;
            transition.subtype = direction > 0 ? kCATransitionFromRight : kCATransitionFromLeft;
            transition.duration = 0.28;
            transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            [_table.layer addAnimation:transition forKey:@"page"];
        }
        [_page release];
        _page = [(FPForumPage *)result retain];
        _pageIndex = MIN(index, [self pageCount] - 1);
        if ([_forumTitle length] == 0 || [_page.title length]) self.appBar.title = [_page.title length] ? _page.title : _forumTitle;
        self.appBar.subtitle = [self pageCount] > 1 ? [NSString stringWithFormat:@"Тем: %lld", _page.topicTotal] : nil;
        [self rebuildItems];
        self.stateView.hidden = YES;
        if (![_items count]) [self.stateView showMessage:@"В этом разделе пока нет тем" retry:NO];
        _pager.hidden = [self pageCount] < 2;
        [_pager setPage:_pageIndex count:[self pageCount]];
        [self.view setNeedsLayout];
        [_table reloadData];
        [_table setContentOffset:CGPointMake(0, 0) animated:NO];
    }];
}

- (void)appendGroup:(NSArray *)entries kind:(FPRowKind)kind label:(NSString *)label
{
    NSUInteger i, n = [entries count];
    FPTopicsItem *header;
    if (!n) return;
    header = [[FPTopicsItem alloc] init];
    header->kind = FPRowSection;
    header->label = [label copy];
    [_items addObject:header];
    [header release];
    for (i = 0; i < n; i++) {
        FPTopicsItem *item = [[FPTopicsItem alloc] init];
        item->kind = kind;
        item->object = [[entries objectAtIndex:i] retain];
        item->position = n == 1 ? FPRowSingle : (i == 0 ? FPRowTop : (i == n - 1 ? FPRowBottom : FPRowMiddle));
        [_items addObject:item];
        [item release];
    }
}

- (void)rebuildItems
{
    [_items removeAllObjects];
    [self appendGroup:_page.subforums kind:FPRowForum label:@"Подразделы"];
    [self appendGroup:_page.pinned kind:FPRowForum label:@"Важное"];
    [self appendGroup:_page.topics kind:FPRowTopic label:@"Темы"];
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section
{
    (void)table;
    (void)section;
    return (NSInteger)[_items count];
}

- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path
{
    FPTopicsItem *item = [_items objectAtIndex:(NSUInteger)path.row];
    CGFloat width = table.bounds.size.width, inset = FPColumnInset(width, FPSafeInsets(self.view));
    NSString *title = nil, *summary = nil;
    if (item->kind == FPRowForum) title = [(FPForumEntry *)item->object title];
    if (item->kind == FPRowTopic) {
        FPTopicEntry *topic = item->object;
        title = topic.title;
        summary = topic.summary;
    }
    return [FPRowView heightForKind:item->kind title:title ? title : item->label subtitle:summary width:width sideInset:inset];
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path
{
    static NSString *identifier = @"row";
    FPListCell *cell = (FPListCell *)[table dequeueReusableCellWithIdentifier:identifier];
    FPTopicsItem *item = [_items objectAtIndex:(NSUInteger)path.row];
    FPRowView *row;
    if (!cell) cell = [[[FPListCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    row = cell.row;
    row.kind = item->kind;
    row.position = item->position;
    row.sideInset = FPColumnInset(table.bounds.size.width, FPSafeInsets(self.view));
    row.subtitle = nil;
    row.meta = nil;
    row.badge = nil;
    row.unread = NO;
    row.dimmed = NO;
    if (item->kind == FPRowSection) {
        row.title = item->label;
    } else if (item->kind == FPRowForum) {
        FPForumEntry *entry = item->object;
        row.title = entry.title;
        row.unread = [entry hasUnread];
    } else {
        FPTopicEntry *topic = item->object;
        NSString *date = FPFormatDate(topic.date);
        row.title = (topic.flags & FP_TOPIC_MOVED) ? [@"Перемещено: " stringByAppendingString:topic.title] : topic.title;
        row.subtitle = topic.summary;
        row.meta = [topic.lastUser length] ? [NSString stringWithFormat:@"%@ · %@", topic.lastUser, date] : date;
        row.badge = [NSString stringWithFormat:@"%lld", topic.posts];
        row.unread = (topic.flags & FP_TOPIC_UNREAD) != 0;
        row.dimmed = (topic.flags & FP_TOPIC_CLOSED) != 0;
    }
    [row setNeedsDisplay];
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path
{
    FPTopicsItem *item = [_items objectAtIndex:(NSUInteger)path.row];
    [table deselectRowAtIndexPath:path animated:YES];
    if (item->kind == FPRowTopic) {
        FPTopicEntry *topic = item->object;
        [self openTopic:topic.topicId title:topic.title offset:-1];
    } else if (item->kind == FPRowForum) {
        FPForumEntry *entry = item->object;
        if ([entry.url length]) [self openLink:entry.url];
        else if (![_page.pinned containsObject:entry]) [self openForum:entry.forumId title:entry.title];
        else {
            FPAnnouncementController *controller = [[FPAnnouncementController alloc] initWithApi:_api identifier:entry.forumId title:entry.title];
            [self.navigationController pushViewController:controller animated:YES];
            [controller release];
        }
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scroll
{
    [self.appBar setElevated:scroll.contentOffset.y > 2];
}

- (void)goToPage:(NSInteger)index direction:(NSInteger)direction
{
    if (index < 0 || index >= [self pageCount] || !_page) return;
    [self loadPage:index direction:direction];
}

- (void)pageSwipedBy:(NSInteger)direction
{
    [self goToPage:_pageIndex + direction direction:direction];
}

- (void)pagerDidSelectPrevious:(FPPager *)pager { (void)pager; [self goToPage:_pageIndex - 1 direction:-1]; }
- (void)pagerDidSelectNext:(FPPager *)pager { (void)pager; [self goToPage:_pageIndex + 1 direction:1]; }

- (void)pagerDidSelectJump:(FPPager *)pager
{
    (void)pager;
    [FPDialog presentInView:self.view title:@"Перейти к странице"
                    message:[NSString stringWithFormat:@"От 1 до %ld", (long)[self pageCount]]
                  fieldText:[NSString stringWithFormat:@"%ld", (long)_pageIndex + 1] numeric:YES confirm:@"Перейти"
                    handler:^(NSString *text) {
        NSInteger target = [text integerValue];
        if (target < 1 || target > [self pageCount]) { [self showToast:@"Такой страницы нет"]; return; }
        [self goToPage:target - 1 direction:target - 1 > _pageIndex ? 1 : -1];
    }];
}

@end
