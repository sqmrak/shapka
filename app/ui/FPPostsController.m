#import "FPImageViewer.h"
#import "FPFavorites.h"
#import "FPPostsController.h"
#import "FPListKit.h"
#import "FPSettings.h"
#import "FPImageLoader.h"
#import "FPAttachmentTransfer.h"
#import "FPComposeController.h"
#import "FPAccountStore.h"
#include "fp_forum.h"
#include <float.h>
#import <QuartzCore/QuartzCore.h>

@interface FPPostsController ()
- (void)loadPage:(NSInteger)index direction:(NSInteger)direction;
- (void)buildForPage:(FPTopicPage *)page width:(CGFloat)width completion:(void (^)(NSDictionary *contents, NSDictionary *layouts))completion;
- (void)rebuildAll;
- (CGFloat)currentBodyWidth;
- (BOOL)isCollapsedHeader:(FPPost *)post;
@end

enum {
    FPPostActionQuote,
    FPPostActionMessage,
    FPPostActionVoteUp,
    FPPostActionVoteDown,
    FPPostActionKarmaUp,
    FPPostActionKarmaDown,
    FPPostActionVoters
};

@implementation FPPostsController

- (id)initWithApi:(FPApi *)api topicId:(NSInteger)topicId title:(NSString *)title offset:(NSInteger)offset
{
    self = [super initWithApi:api];
    if (self) {
        _topicId = topicId;
        _topicTitle = [title copy];
        _perPage = [FPSettings postsPerPage];
        if (offset < 0) {
            NSString *key = [NSString stringWithFormat:@"%ld.%ld", (long)[api memberId], (long)topicId];
            NSDictionary *positions = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"reading_positions"];
            NSDictionary *saved = [positions objectForKey:key];
            if ([saved isKindOfClass:[NSDictionary class]]) {
                NSInteger savedOffset = [[saved objectForKey:@"offset"] integerValue];
                offset = MAX(0, MIN(savedOffset, 10000000));
                _restorePostId = [[saved objectForKey:@"post"] integerValue];
            }
        }
        _pageIndex = offset > 0 ? offset / _perPage : 0;
        _contents = [[NSMutableDictionary alloc] init];
        _layouts = [[NSMutableDictionary alloc] init];
        _spoilers = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    if (!_page || _topicId <= 0) return;
    NSArray *visible = [_table indexPathsForVisibleRows];
    NSIndexPath *first = [visible count] ? [visible objectAtIndex:0] : nil;
    NSInteger postId = 0;
    if (first && first.row >= 0 && (NSUInteger)first.row < [_page.posts count]) {
        FPPost *post = [_page.posts objectAtIndex:(NSUInteger)first.row];
        postId = post.postId;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *existing = [defaults dictionaryForKey:@"reading_positions"];
    NSMutableDictionary *positions = existing ? [[existing mutableCopy] autorelease] : [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%ld.%ld", (long)[_api memberId], (long)_topicId];
    [positions setObject:[NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInteger:_pageIndex * _perPage], @"offset",
        [NSNumber numberWithInteger:postId], @"post",
        [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]], @"date", nil] forKey:key];
    while ([positions count] > 100) {
        NSString *oldest = nil;
        NSTimeInterval time = DBL_MAX;
        for (NSString *entry in positions) {
            id value = [positions objectForKey:entry];
            NSTimeInterval date = [value isKindOfClass:[NSDictionary class]] ? [[value objectForKey:@"date"] doubleValue] : 0;
            if (date < time) { time = date; oldest = entry; }
        }
        if (!oldest) break;
        [positions removeObjectForKey:oldest];
    }
    [defaults setObject:positions forKey:@"reading_positions"];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.delegate = nil;
    _table.dataSource = nil;
    _pager.delegate = nil;
    [_table release]; [_pager release]; [_page release]; [_topicTitle release];
    [_contents release]; [_layouts release]; [_spoilers release];
    _postActions.delegate = nil;
    [_postActions dismissWithClickedButtonIndex:_postActions.cancelButtonIndex animated:NO];
    [_postActions release]; [_documentController release]; [_selectedPost release]; [_memberLink release]; [_postActionKinds release];
    [super dealloc];
}

- (void)loadView
{
    [super loadView];
    self.appBar.title = [_topicTitle length] ? _topicTitle : @"Тема";
    _favoriteButton = [self.appBar addActionWithIcon:FPIconStar target:self action:@selector(toggleFavorite)];
    [self updateFavoriteButton];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(imageSizeKnown:) name:FPImageSizeKnownNotification object:nil];
    [self.appBar addActionWithIcon:FPIconRefresh target:self action:@selector(reloadFromUser)].accessibilityLabel = @"Обновить";
    [self.appBar addActionWithIcon:FPIconReply target:self action:@selector(composeReply)].accessibilityLabel = @"Ответить";
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
    [self loadPage:_pageIndex direction:0];
}

- (void)composeReply
{
    if ([_api memberId] <= 0) { [self showToast:@"Войдите, чтобы ответить"]; return; }
    FPComposeController *composer = [[FPComposeController alloc] initWithApi:_api topicId:_topicId sent:^{
        NSInteger last = _page ? (NSInteger)(_page.postTotal / _perPage) : 0;
        [self loadPage:last direction:1];
    }];
    [self presentViewController:composer animated:YES completion:nil];
    [composer release];
}

/* a picture whose size was unknown got a placeholder slot; now its message is laid out again with the real size */
- (void)imageSizeKnown:(NSNotification *)note
{
    NSString *url = [note object];
    BOOL changed = NO;
    CGFloat width = [self currentBodyWidth];
    for (FPPost *post in _page.posts) {
        NSNumber *key = [NSNumber numberWithInteger:post.postId];
        FPPostLayout *old = [_layouts objectForKey:key];
        id content = [_contents objectForKey:key];
        NSIndexSet *open = [_spoilers objectForKey:key];
        if (!old || !content || ![old awaitsSizeOfURL:url]) continue;
        [_layouts setObject:[FPPostLayout layoutContent:content width:width spoilers:open ? open : [NSIndexSet indexSet]] forKey:key];
        changed = YES;
    }
    if (changed) [_table reloadData];
}

- (void)updateFavoriteButton
{
    BOOL saved = [FPFavorites containsTopic:_topicId];
    [_favoriteButton setImage:FPIcon(saved ? FPIconStarFilled : FPIconStar, 24, FPThemeIsClassic() ? [UIColor whiteColor] : FPColor(FPRoleOnSurface)) forState:UIControlStateNormal];
    _favoriteButton.accessibilityLabel = saved ? @"Убрать из избранного" : @"Добавить в избранное";
}

- (void)toggleFavorite
{
    BOOL add = ![FPFavorites containsTopic:_topicId];
    NSInteger member = [FPFavorites member];
    NSString *title = [_page.title length] ? _page.title : _topicTitle;
    if (member <= 0) {
        if (!add) { [FPFavorites removeTopic:_topicId]; [self showToast:@"Тема удалена из избранного"]; }
        else if ([FPFavorites addTopic:_topicId title:title]) [self showToast:@"Тема добавлена в избранное"];
        else [self showToast:@"Не удалось сохранить тему"];
        [self updateFavoriteButton];
        return;
    }
    if (_favoriteBusy) return;
    if (add && ![title length]) { [self showToast:@"Не удалось сохранить тему"]; return; }
    _favoriteBusy = YES;
    [_api setTopic:_topicId favorite:add completion:^(NSError *error) {
        _favoriteBusy = NO;
        if (error) {
            [self showToast:[NSString stringWithFormat:@"Избранное не изменено: %@", [error localizedDescription]]];
            return;
        }
        /* the answer of a member who signed out or changed while the request ran belongs to a list that is not shown */
        if ([FPFavorites member] == member) {
            if (add) [FPFavorites addTopic:_topicId title:title];
            else [FPFavorites removeTopic:_topicId];
        }
        [self showToast:add ? @"Тема добавлена в избранное" : @"Тема удалена из избранного"];
        [self updateFavoriteButton];
    }];
}

/* the server knows the true state of the star; the copy on the device follows it */
- (void)adoptServerFavorite
{
    BOOL server = (_page.flags & FP_TOPIC_PAGE_FAVORITE) != 0;
    if ([FPFavorites member] <= 0 || _favoriteBusy) return;
    if (server && ![FPFavorites containsTopic:_topicId]) [FPFavorites addTopic:_topicId title:[_page.title length] ? _page.title : _topicTitle];
    else if (!server && [FPFavorites containsTopic:_topicId]) [FPFavorites removeTopic:_topicId];
    [self updateFavoriteButton];
}

- (void)didReceiveMemoryWarning
{
    /* layouts are rebuilt from the kept contents when a row needs them again */
    [_layouts removeAllObjects];
    [super didReceiveMemoryWarning];
}

- (NSInteger)pageCount
{
    long long total = _page ? _page.postTotal : 0;
    return total > 0 ? (NSInteger)((total + _perPage - 1) / _perPage) : 1;
}

- (CGFloat)currentBodyWidth
{
    CGFloat width = _table.bounds.size.width;
    return [FPPostCell bodyWidthForWidth:width sideInset:FPColumnInset(width, FPSafeInsets(self.view))];
}

- (void)layoutContent
{
    UIEdgeInsets safe = FPSafeInsets(self.view);
    CGRect bounds = self.contentView.bounds;
    CGFloat pagerHeight = _pager.hidden ? 0 : [FPPager contentHeight] + safe.bottom;
    CGFloat previousWidth = _table.bounds.size.width;
    _pager.frame = CGRectMake(0, bounds.size.height - pagerHeight, bounds.size.width, pagerHeight);
    _pager.bottomInset = safe.bottom;
    _table.frame = CGRectMake(0, 0, bounds.size.width, bounds.size.height - pagerHeight);
    _table.contentInset = UIEdgeInsetsMake(4, 0, pagerHeight ? 8 : safe.bottom + 16, 0);
    _table.scrollIndicatorInsets = _table.contentInset;
    if (_page && fabsf((float)([self currentBodyWidth] - _buildWidth)) > 0.5f) [self rebuildAll];
    else if (previousWidth != bounds.size.width) [_table reloadData];
}

- (void)themeDidChange
{
    _table.backgroundColor = [UIColor clearColor];
    [self updateFavoriteButton];
    [_pager applyTheme];
    /* colors and text sizes are part of a layout */
    if (_page) {
        NSInteger perPage = [FPSettings postsPerPage];
        if (perPage != _perPage) {
            _perPage = perPage;
            [self loadPage:0 direction:0];
            return;
        }
        [_contents removeAllObjects];
        [self rebuildAll];
    }
}

- (void)reloadFromUser
{
    [self loadPage:_pageIndex direction:0];
}

- (BOOL)isCollapsedHeader:(FPPost *)post
{
    return _pageIndex > 0 && [post isHeader] && !_headerOpen;
}

- (void)buildForPage:(FPTopicPage *)page width:(CGFloat)width completion:(void (^)(NSDictionary *contents, NSDictionary *layouts))completion
{
    NSArray *posts = [[page.posts copy] autorelease];
    NSDictionary *known = [[_contents copy] autorelease];
    NSDictionary *spoilers = [[[NSDictionary alloc] initWithDictionary:_spoilers copyItems:YES] autorelease];
    BOOL signatures = [FPSettings showSignatures];
    void (^done)(NSDictionary *, NSDictionary *) = [completion copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSMutableDictionary *contents = [[NSMutableDictionary alloc] init];
        NSMutableDictionary *layouts = [[NSMutableDictionary alloc] init];
        NSUInteger workers = MIN((NSUInteger)2, [posts count]);
        NSMutableArray *contentParts = [NSMutableArray arrayWithCapacity:workers];
        NSMutableArray *layoutParts = [NSMutableArray arrayWithCapacity:workers];
        for (NSUInteger i = 0; i < workers; i++) {
            [contentParts addObject:[NSMutableDictionary dictionary]];
            [layoutParts addObject:[NSMutableDictionary dictionary]];
        }
        dispatch_apply(workers, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t worker) {
            NSAutoreleasePool *workerPool = [[NSAutoreleasePool alloc] init];
            NSMutableDictionary *localContents = [contentParts objectAtIndex:worker];
            NSMutableDictionary *localLayouts = [layoutParts objectAtIndex:worker];
            for (NSUInteger i = worker; i < [posts count]; i += workers) {
                FPPost *post = [posts objectAtIndex:i];
                NSNumber *key = [NSNumber numberWithInteger:post.postId];
                id content = [known objectForKey:key];
                NSIndexSet *open = [spoilers objectForKey:key];
                if (!content) content = [FPPostLayout contentForPost:post includeSignature:signatures];
                [localContents setObject:content forKey:key];
                [localLayouts setObject:[FPPostLayout layoutContent:content width:width spoilers:open ? open : [NSIndexSet indexSet]] forKey:key];
            }
            [workerPool drain];
        });
        for (NSUInteger i = 0; i < workers; i++) {
            [contents addEntriesFromDictionary:[contentParts objectAtIndex:i]];
            [layouts addEntriesFromDictionary:[layoutParts objectAtIndex:i]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            done(contents, layouts);
            [done release];
            [contents release];
            [layouts release];
        });
        [pool drain];
    });
}

- (void)rebuildAll
{
    NSUInteger serial = ++_buildSerial;
    CGFloat width = [self currentBodyWidth];
    FPTopicPage *page = _page;
    if (!page) return;
    [self buildForPage:page width:width completion:^(NSDictionary *contents, NSDictionary *layouts) {
        if (serial != _buildSerial || page != _page) return;
        [_contents setDictionary:contents];
        [_layouts setDictionary:layouts];
        _buildWidth = width;
        [_table reloadData];
    }];
}

- (void)loadPage:(NSInteger)index direction:(NSInteger)direction
{
    NSUInteger serial = ++_serial;
    if (_page) FPAnimate(0.2, ^{ _table.alpha = 0.55f; }, nil);
    [self.api loadTopic:_topicId offset:index * _perPage count:_perPage completion:^(id result, NSError *error) {
        FPTopicPage *page;
        CGFloat width;
        if (serial != _serial) return;
        if (error) {
            [self endRefreshing];
            FPAnimate(0.2, ^{ _table.alpha = 1; }, nil);
            if (_page) [self showToast:[NSString stringWithFormat:@"Не удалось загрузить: %@", [error localizedDescription]]];
            else [self.stateView showMessage:[error localizedDescription] retry:YES];
            return;
        }
        page = result;
        width = [self currentBodyWidth];
        ++_buildSerial;
        /* the new page shows once its layouts exist, so the old one stays readable meanwhile */
        [self buildForPage:page width:width completion:^(NSDictionary *contents, NSDictionary *layouts) {
            if (serial != _serial) return;
            if (direction != 0 && !FPReduceMotionEnabled()) {
                CATransition *transition = [CATransition animation];
                transition.type = kCATransitionPush;
                transition.subtype = direction > 0 ? kCATransitionFromRight : kCATransitionFromLeft;
                transition.duration = 0.28;
                transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                [_table.layer addAnimation:transition forKey:@"page"];
            }
            [self endRefreshing];
            [_page release];
            _page = [page retain];
            NSInteger member = [_api memberId];
            if (member > 0) {
                for (FPPost *post in _page.posts) {
                    if (post.userId == member && [post.userName length]) {
                        [FPAccountStore rememberName:post.userName avatar:post.avatar forMember:member];
                        break;
                    }
                }
            }
            [self adoptServerFavorite];
            [_contents setDictionary:contents];
            [_layouts setDictionary:layouts];
            [_spoilers removeAllObjects];
            _buildWidth = width;
            _headerOpen = NO;
            _pageIndex = MIN(index, [self pageCount] - 1);
            FPAnimate(0.2, ^{ _table.alpha = 1; }, nil);
            if ([_page.title length]) self.appBar.title = _page.title;
            self.appBar.subtitle = [self pageCount] > 1 ? [NSString stringWithFormat:@"Страница %ld из %ld", (long)_pageIndex + 1, (long)[self pageCount]] : nil;
            self.stateView.hidden = YES;
            if (![_page.posts count]) [self.stateView showMessage:@"В теме нет сообщений" retry:NO];
            _pager.hidden = [self pageCount] < 2;
            [_pager setPage:_pageIndex count:[self pageCount]];
            [self.view setNeedsLayout];
            [_table reloadData];
            [_table setContentOffset:CGPointMake(0, -_table.contentInset.top) animated:NO];
            if (_restorePostId > 0) {
                for (NSUInteger i = 0; i < [_page.posts count]; i++) {
                    FPPost *post = [_page.posts objectAtIndex:i];
                    if (post.postId == _restorePostId) {
                        [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)i inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
                        break;
                    }
                }
                _restorePostId = 0;
            }
        }];
    }];
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section
{
    (void)table;
    (void)section;
    return (NSInteger)[_page.posts count];
}

- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path
{
    FPPost *post = [_page.posts objectAtIndex:(NSUInteger)path.row];
    FPPostLayout *layout;
    if ([self isCollapsedHeader:post]) return 70;
    layout = [_layouts objectForKey:[NSNumber numberWithInteger:post.postId]];
    return layout ? [FPPostCell heightForLayout:layout] : 90;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path
{
    FPPost *post = [_page.posts objectAtIndex:(NSUInteger)path.row];
    CGFloat width = table.bounds.size.width, inset = FPColumnInset(width, FPSafeInsets(self.view));
    if ([self isCollapsedHeader:post]) {
        static NSString *headIdentifier = @"head";
        FPListCell *cell = (FPListCell *)[table dequeueReusableCellWithIdentifier:headIdentifier];
        if (!cell) cell = [[[FPListCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:headIdentifier] autorelease];
        cell.row.kind = FPRowForum;
        cell.row.position = FPRowSingle;
        cell.row.title = @"Шапка темы";
        cell.row.unread = NO;
        cell.row.sideInset = inset;
        [cell.row setNeedsDisplay];
        return cell;
    }
    {
        static NSString *identifier = @"post";
        FPPostCell *cell = (FPPostCell *)[table dequeueReusableCellWithIdentifier:identifier];
        FPPostLayout *layout = [_layouts objectForKey:[NSNumber numberWithInteger:post.postId]];
        if (!cell) {
            cell = [[[FPPostCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
            cell.delegate = self;
        }
        if (!layout) {
            id content = [_contents objectForKey:[NSNumber numberWithInteger:post.postId]];
            if (!content) content = [FPPostLayout contentForPost:post includeSignature:[FPSettings showSignatures]];
            layout = [FPPostLayout layoutContent:content width:[self currentBodyWidth] spoilers:[NSIndexSet indexSet]];
            [_contents setObject:content forKey:[NSNumber numberWithInteger:post.postId]];
            [_layouts setObject:layout forKey:[NSNumber numberWithInteger:post.postId]];
        }
        [cell configureWithPost:post layout:layout width:width sideInset:inset];
        return cell;
    }
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path
{
    FPPost *post = [_page.posts objectAtIndex:(NSUInteger)path.row];
    [table deselectRowAtIndexPath:path animated:YES];
    if ([self isCollapsedHeader:post]) {
        _headerOpen = YES;
        [table reloadRowsAtIndexPaths:[NSArray arrayWithObject:path] withRowAnimation:UITableViewRowAnimationFade];
    } else if (post.userId > 0) {
        if (_postActions) return;
        [_selectedPost release];
        _selectedPost = [post retain];
        [self showActionsForPost:post];
    }
}

/* what the sheet of a post offers follows the vote word of the post and the account, and the kinds array maps a button to its action */
- (void)showActionsForPost:(FPPost *)post
{
    BOOL signedIn = [_api memberId] > 0, others = signedIn && post.userId != [_api memberId];
    NSMutableArray *titles = [NSMutableArray arrayWithObjects:@"Цитировать", @"Написать личное сообщение", nil];
    [_postActionKinds release];
    _postActionKinds = [[NSMutableArray alloc] initWithObjects:[NSNumber numberWithInt:FPPostActionQuote], [NSNumber numberWithInt:FPPostActionMessage], nil];
    if (others && [post canBeRated]) {
        [titles addObject:@"Оценить пост: плюс"]; [_postActionKinds addObject:[NSNumber numberWithInt:FPPostActionVoteUp]];
        [titles addObject:@"Оценить пост: минус"]; [_postActionKinds addObject:[NSNumber numberWithInt:FPPostActionVoteDown]];
    }
    if (others) {
        [titles addObject:@"Повысить репутацию автора"]; [_postActionKinds addObject:[NSNumber numberWithInt:FPPostActionKarmaUp]];
        [titles addObject:@"Понизить репутацию автора"]; [_postActionKinds addObject:[NSNumber numberWithInt:FPPostActionKarmaDown]];
    }
    if ([post hasRating]) { [titles addObject:@"Кто оценил пост"]; [_postActionKinds addObject:[NSNumber numberWithInt:FPPostActionVoters]]; }
    _postActions = [[UIActionSheet alloc] initWithTitle:post.userName delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSString *title in titles) [_postActions addButtonWithTitle:title];
    _postActions.cancelButtonIndex = [_postActions addButtonWithTitle:@"Отмена"];
    [_postActions showInView:self.view];
}

- (void)votePost:(FPPost *)post up:(BOOL)up
{
    [_api votePost:post.postId up:up completion:^(NSError *error) {
        if (error) { [self showToast:[error localizedDescription]]; return; }
        [self showToast:@"Голос засчитан"];
        [self reloadFromUser];
    }];
}

- (void)askKarmaReasonForPost:(FPPost *)post up:(BOOL)up
{
    [FPDialog presentInView:self.view title:up ? @"Причина повышения репутации" : @"Причина понижения репутации"
                    message:post.userName fieldText:@"" numeric:NO confirm:up ? @"Повысить" : @"Понизить" handler:^(NSString *reason) {
        NSString *trimmed = [reason stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (![trimmed length]) { [self showToast:@"Укажите причину"]; return; }
        [_api changeKarmaOfMember:post.userId post:post.postId up:up reason:trimmed completion:^(NSError *error) {
            [self showToast:error ? [error localizedDescription] : @"Репутация изменена"];
        }];
    }];
}

- (void)showVotersOfPost:(FPPost *)post
{
    [_api loadVotesOfPost:post.postId completion:^(id votes, NSError *error) {
        if (error) { [self showToast:[NSString stringWithFormat:@"Не удалось загрузить оценки: %@", [error localizedDescription]]]; return; }
        NSMutableString *text = [NSMutableString string];
        NSUInteger shown = MIN([votes count], 25u);
        for (NSUInteger i = 0; i < shown; i++) {
            NSDictionary *vote = [votes objectAtIndex:i];
            [text appendFormat:@"%@ %@\n", [[vote objectForKey:@"value"] intValue] > 0 ? @"+" : @"\u2212", [vote objectForKey:@"name"]];
        }
        if ([votes count] > shown) [text appendFormat:@"и ещё %lu", (unsigned long)([votes count] - shown)];
        if (![votes count]) [text setString:@"Никто не оценивал этот пост"];
        [FPDialog presentInView:self.view title:@"Оценки поста" message:text fieldText:nil numeric:NO confirm:@"Закрыть" handler:nil];
    }];
}

/* a nick in the text offers a private message first, the profile page exists only in the browser */
- (BOOL)openMember:(NSInteger)memberId link:(NSString *)url
{
    if (_postActions) return YES;
    NSString *name = nil;
    for (FPPost *post in _page.posts) if (post.userId == memberId) { name = post.userName; break; }
    [_memberLink release]; _memberLink = [url copy];
    _memberId = memberId;
    [_selectedPost release]; _selectedPost = nil;
    _postActions = [[UIActionSheet alloc] initWithTitle:name delegate:self cancelButtonTitle:@"Отмена"
                                 destructiveButtonTitle:nil otherButtonTitles:@"Написать личное сообщение", @"Профиль в браузере", nil];
    [_postActions showInView:self.view];
    return YES;
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (_memberLink) {
        NSString *link = [[_memberLink retain] autorelease];
        NSInteger member = _memberId;
        NSString *name = [[sheet.title copy] autorelease];
        [_memberLink release]; _memberLink = nil;
        _postActions.delegate = nil;
        [_postActions release]; _postActions = nil;
        if (buttonIndex == sheet.cancelButtonIndex) return;
        if (buttonIndex == 1) {
            NSURL *address = [NSURL URLWithString:link];
            if (address) [self openInBrowser:address];
        } else if ([_api memberId] <= 0) [self showToast:@"Войдите, чтобы написать"];
        else {
            FPComposeController *composer = [[FPComposeController alloc] initWithApi:_api memberId:member name:name ? name : @"Участник"];
            [self presentViewController:composer animated:YES completion:nil];
            [composer release];
        }
        return;
    }
    if (buttonIndex != sheet.cancelButtonIndex && _selectedPost && (NSUInteger)buttonIndex < [_postActionKinds count]) {
        FPPost *post = _selectedPost;
        int kind = [[_postActionKinds objectAtIndex:(NSUInteger)buttonIndex] intValue];
        if ([_api memberId] <= 0 && kind != FPPostActionVoters) [self showToast:@"Войдите, чтобы продолжить"];
        else if (kind == FPPostActionQuote) {
            FPComposeController *composer = [[FPComposeController alloc] initWithApi:_api topicId:_topicId sent:^{
                NSInteger last = _page ? (NSInteger)(_page.postTotal / _perPage) : 0;
                [self loadPage:last direction:1];
            }];
            [composer appendQuote:[NSString stringWithFormat:@"[quote]\n%@\n[/quote]\n", post.body ? post.body : @""]];
            [self presentViewController:composer animated:YES completion:nil];
            [composer release];
        } else if (kind == FPPostActionMessage) {
            FPComposeController *composer = [[FPComposeController alloc] initWithApi:_api memberId:post.userId name:post.userName];
            [self presentViewController:composer animated:YES completion:nil];
            [composer release];
        } else if (kind == FPPostActionVoteUp || kind == FPPostActionVoteDown) [self votePost:post up:kind == FPPostActionVoteUp];
        else if (kind == FPPostActionKarmaUp || kind == FPPostActionKarmaDown) [self askKarmaReasonForPost:post up:kind == FPPostActionKarmaUp];
        else if (kind == FPPostActionVoters) [self showVotersOfPost:post];
    }
    [_selectedPost release]; _selectedPost = nil;
    [_postActionKinds release]; _postActionKinds = nil;
    _postActions.delegate = nil;
    [_postActions release]; _postActions = nil;
}

- (void)postCell:(FPPostCell *)cell didHit:(FPPostHit *)hit
{
    NSIndexPath *path = [_table indexPathForCell:cell];
    FPPost *post;
    NSNumber *key;
    NSMutableIndexSet *open;
    id content;
    CGFloat width;
    if (!path) return;
    post = [_page.posts objectAtIndex:(NSUInteger)path.row];
    if (hit->kind == FPHitFile) {
        BOOL started = [FPAttachmentTransfer startWithApi:_api identifier:hit->attachmentId name:hit->fileName completion:^(NSString *savedPath, NSError *error) {
            if (error) { [self showToast:[error localizedDescription]]; return; }
            [self showToast:@"Файл сохранён в Documents"];
            if ([FPAttachmentTransfer activeCount] || !self.view.window) return;
            [_documentController release];
            _documentController = [[UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:savedPath]] retain];
            [_documentController presentOpenInMenuFromRect:self.view.bounds inView:self.view animated:YES];
        }];
        [self showToast:started ? @"Загрузка файла…" : @"Одновременно можно загружать до трёх файлов"];
        return;
    }
    if (hit->kind == FPHitImage) {
        FPImageViewer *viewer = [[FPImageViewer alloc] initWithURL:hit->link];
        [self presentViewController:viewer animated:YES completion:nil];
        [viewer release];
        return;
    }
    if (hit->kind == FPHitLink) {
        [self openLink:hit->link];
        return;
    }
    if (hit->kind != FPHitSpoiler) return;
    key = [NSNumber numberWithInteger:post.postId];
    open = [_spoilers objectForKey:key];
    if (!open) {
        open = [NSMutableIndexSet indexSet];
        [_spoilers setObject:open forKey:key];
    }
    if ([open containsIndex:(NSUInteger)hit->spoiler]) [open removeIndex:(NSUInteger)hit->spoiler];
    else [open addIndex:(NSUInteger)hit->spoiler];
    content = [_contents objectForKey:key];
    width = [self currentBodyWidth];
    if (!content) return;
    {
        NSIndexSet *snapshot = [[open copy] autorelease];
        FPTopicPage *page = _page;
        NSUInteger serial = _buildSerial;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            FPPostLayout *layout = [[FPPostLayout layoutContent:content width:width spoilers:snapshot] retain];
            dispatch_async(dispatch_get_main_queue(), ^{
                NSUInteger row = page == _page ? [_page.posts indexOfObjectIdenticalTo:post] : NSNotFound;
                if (row != NSNotFound && serial == _buildSerial) {
                    [_layouts setObject:layout forKey:key];
                    [_table reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:(NSInteger)row inSection:0]]
                                  withRowAnimation:UITableViewRowAnimationFade];
                }
                [layout release];
            });
            [pool drain];
        });
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
