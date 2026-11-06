#import "FPQMSController.h"
#import "FPComposeController.h"
#import "FPAttachmentTransfer.h"

static NSArray *FPQMSSortedMessages(NSArray *messages)
{
    return [messages sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
        return [[left objectAtIndex:0] compare:[right objectAtIndex:0]];
    }];
}


#define FPQMS_SIDE 12.0f
#define FPQMS_PAD_X 14.0f
#define FPQMS_PAD_Y 9.0f
#define FPQMS_GAP_SAME 3.0f
#define FPQMS_GAP_OTHER 10.0f
#define FPQMS_DAY_HEIGHT 40.0f

typedef struct {
    CGFloat height;
    CGRect bubble;
    CGRect text;
    CGRect time;
    CGRect files;
    CGRect day;
    BOOL own;
    BOOL joinedAbove;
    BOOL joinedBelow;
    BOOL hasDay;
} FPQMSLayout;

static NSString *FPQMSTime(int64_t unixTime)
{
    time_t then = (time_t)unixTime;
    struct tm t;
    char text[8];
    localtime_r(&then, &t);
    snprintf(text, sizeof(text), "%02d:%02d", t.tm_hour, t.tm_min);
    return [NSString stringWithUTF8String:text];
}

static BOOL FPQMSSameDay(int64_t a, int64_t b)
{
    time_t x = (time_t)a, y = (time_t)b;
    struct tm left, right;
    localtime_r(&x, &left);
    localtime_r(&y, &right);
    return left.tm_year == right.tm_year && left.tm_yday == right.tm_yday;
}

/* the label of a day break: today and yesterday by name, other days as "10 окт" with the year when it is not the current one */
static NSString *FPQMSDay(int64_t unixTime)
{
    static const char *months[12] = {"янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"};
    time_t now = time(NULL), then = (time_t)unixTime;
    struct tm a, b;
    char text[32];
    if (FPQMSSameDay(unixTime, now)) return @"Сегодня";
    if (FPQMSSameDay(unixTime, (int64_t)now - 86400)) return @"Вчера";
    localtime_r(&then, &a);
    localtime_r(&now, &b);
    if (a.tm_year == b.tm_year) snprintf(text, sizeof(text), "%d %s", a.tm_mday, months[a.tm_mon % 12]);
    else snprintf(text, sizeof(text), "%d %s %d", a.tm_mday, months[a.tm_mon % 12], a.tm_year + 1900);
    return [NSString stringWithUTF8String:text];
}

static int64_t FPQMSDate(NSArray *message) { return [[message objectAtIndex:2] longLongValue]; }
static NSInteger FPQMSSender(NSArray *message) { return [[message objectAtIndex:1] integerValue]; }

static FPQMSLayout FPQMSMakeLayout(NSArray *message, NSArray *above, NSArray *below, NSInteger member, CGFloat width)
{
    FPQMSLayout l;
    UIFont *bodyFont = FPFont(15, 0, YES), *smallFont = FPFont(11, 0, YES), *fileFont = FPFont(12, 1, YES);
    NSString *body = [message objectAtIndex:3];
    NSUInteger fileCount = [[message objectAtIndex:4] count];
    NSString *time = FPQMSTime(FPQMSDate(message)), *files = nil;
    CGFloat maxBubble = MIN(floorf(width * 0.78f), 520.0f), inner = maxBubble - 2 * FPQMS_PAD_X;
    CGFloat textW = 0, textH = 0, timeW, fileW = 0, fileH = 0, contentW, bubbleW, y = 0;
    memset(&l, 0, sizeof(l));
    l.own = member > 0 && FPQMSSender(message) == member;
    l.hasDay = !above || !FPQMSSameDay(FPQMSDate(above), FPQMSDate(message));
    l.joinedAbove = above && !l.hasDay && FPQMSSender(above) == FPQMSSender(message);
    l.joinedBelow = below && FPQMSSameDay(FPQMSDate(below), FPQMSDate(message)) && FPQMSSender(below) == FPQMSSender(message);
    if (l.hasDay) {
        CGSize day = FPTextSize(FPQMSDay(FPQMSDate(message)), smallFont, 0);
        CGFloat pill = ceilf(day.width) + 24;
        l.day = CGRectMake(floorf((width - pill) / 2), 10, pill, 24);
        y = FPQMS_DAY_HEIGHT;
    } else if (above) {
        y = l.joinedAbove ? FPQMS_GAP_SAME : FPQMS_GAP_OTHER;
    }
    if ([body length]) {
        CGSize size = FPTextSize(body, bodyFont, inner);
        textW = MIN(ceilf(size.width) + 1, inner);
        textH = ceilf(size.height);
    }
    timeW = ceilf(FPTextSize(time, smallFont, 0).width);
    if (fileCount) {
        files = [NSString stringWithFormat:@"Вложений: %lu", (unsigned long)fileCount];
        fileW = 20 + ceilf(FPTextSize(files, fileFont, 0).width);
        fileH = 20;
    }
    contentW = MAX(textW, MAX(timeW, fileW));
    bubbleW = contentW + 2 * FPQMS_PAD_X;
    CGFloat x = l.own ? width - FPQMS_SIDE - bubbleW : FPQMS_SIDE;
    CGFloat inside = FPQMS_PAD_Y;
    l.text = CGRectMake(x + FPQMS_PAD_X, y + inside, contentW, textH);
    if (textH > 0) inside += textH + 4;
    l.files = CGRectMake(x + FPQMS_PAD_X, y + inside, contentW, fileH);
    if (fileH > 0) inside += fileH + 4;
    l.time = CGRectMake(x + FPQMS_PAD_X, y + inside, contentW, ceilf(FPLineHeight(smallFont)));
    inside += l.time.size.height + FPQMS_PAD_Y;
    l.bubble = CGRectMake(x, y, bubbleW, inside);
    l.height = y + inside;
    return l;
}

@interface FPQMSBubbleView : UIView {
    NSString *_body;
    NSString *_time;
    NSString *_day;
    NSString *_files;
    FPQMSLayout _layout;
}
- (void)setBody:(NSString *)body time:(NSString *)time day:(NSString *)day files:(NSString *)files layout:(FPQMSLayout)layout;
@end

@implementation FPQMSBubbleView
- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) { self.backgroundColor = [UIColor clearColor]; self.opaque = NO; self.contentMode = UIViewContentModeRedraw; }
    return self;
}
- (void)dealloc { [_body release]; [_time release]; [_day release]; [_files release]; [super dealloc]; }
- (void)setBody:(NSString *)body time:(NSString *)time day:(NSString *)day files:(NSString *)files layout:(FPQMSLayout)layout
{
    [_body release]; _body = [body copy];
    [_time release]; _time = [time copy];
    [_day release]; _day = [day copy];
    [_files release]; _files = [files copy];
    _layout = layout;
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect
{
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    UIColor *fill = FPColor(_layout.own ? FPRolePrimaryContainer : FPRoleHighest);
    UIColor *ink = FPColor(_layout.own ? FPRoleOnPrimaryContainer : FPRoleOnSurface);
    UIColor *quiet = FPColor(_layout.own ? FPRoleOnPrimaryContainer : FPRoleOnVariant);
    CGFloat big = 20, small = 6;
    /* the corner next to the sender is squared off where bubbles join and at the tail, so a run reads as one stack */
    CGFloat topLeft = big, topRight = big, bottomRight = big, bottomLeft = big;
    if (_layout.own) { topRight = _layout.joinedAbove ? small : big; bottomRight = small; }
    else { topLeft = _layout.joinedAbove ? small : big; bottomLeft = small; }
    if (_layout.hasDay) {
        CGPathRef pill = FPCreateRoundedRect(_layout.day, 12, 12, 12, 12);
        CGContextAddPath(context, pill);
        CGContextSetFillColorWithColor(context, FPColor(FPRoleContainer).CGColor);
        CGContextFillPath(context);
        CGPathRelease(pill);
        FPDrawText(_day, FPFont(11, 1, YES), FPColor(FPRoleOnVariant), CGRectMake(_layout.day.origin.x + 12, _layout.day.origin.y + 4, _layout.day.size.width - 24, 18), 1);
    }
    CGPathRef path = FPCreateRoundedRect(_layout.bubble, topLeft, topRight, bottomRight, bottomLeft);
    CGContextAddPath(context, path);
    CGContextSetFillColorWithColor(context, fill.CGColor);
    CGContextFillPath(context);
    CGPathRelease(path);
    if ([_body length]) FPDrawText(_body, FPFont(15, 0, YES), ink, _layout.text, 0);
    if (_layout.files.size.height > 0) {
        [FPIcon(FPIconFile, 16, quiet) drawInRect:CGRectMake(_layout.files.origin.x, _layout.files.origin.y + 2, 16, 16)];
        FPDrawText(_files, FPFont(12, 1, YES), quiet, CGRectMake(_layout.files.origin.x + 20, _layout.files.origin.y + 2, _layout.files.size.width - 20, 16), 1);
    }
    {
        UIFont *font = FPFont(11, 0, YES);
        CGFloat w = ceilf(FPTextSize(_time, font, 0).width);
        FPDrawText(_time, font, quiet, CGRectMake(_layout.time.origin.x + _layout.time.size.width - w, _layout.time.origin.y, w + 1, _layout.time.size.height), 1);
    }
}
@end

@implementation FPQMSController
- (id)initWithApi:(FPApi *)api
{
    self = [super initWithApi:api];
    if (self) _heading = [@"Сообщения" copy];
    return self;
}
- (id)initWithApi:(FPApi *)api member:(NSInteger)member title:(NSString *)title
{
    self = [super initWithApi:api];
    if (self) { _member = member; _heading = [title copy]; }
    return self;
}
- (id)initWithApi:(FPApi *)api dialog:(NSInteger)dialog title:(NSString *)title
{
    self = [super initWithApi:api];
    if (self) { _dialog = dialog; _heading = [title copy]; }
    return self;
}
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.delegate = nil; _table.dataSource = nil;
    _fileSheet.delegate = nil;
    [_fileSheet dismissWithClickedButtonIndex:_fileSheet.cancelButtonIndex animated:NO];
    [_fileSheet release]; [_selectedFiles release]; [_documentController release];
    [_table release]; [_rows release]; [_heading release];
    [super dealloc];
}
- (void)loadView
{
    [super loadView];
    self.appBar.title = [_heading length] ? _heading : @"Сообщения";
    [self.appBar addActionWithIcon:FPIconRefresh target:self action:@selector(reloadFromUser)].accessibilityLabel = @"Обновить";
    if (_dialog) {
        [self.appBar addActionWithIcon:FPIconReply target:self action:@selector(compose)].accessibilityLabel = @"Ответить";
        [self.appBar addActionWithIcon:FPIconChevronUp target:self action:@selector(loadOlder)].accessibilityLabel = @"Ранее";
    }
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.delegate = self; _table.dataSource = self;
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.allowsSelection = YES;
    [self.contentView insertSubview:_table belowSubview:self.stateView];
    [self installRefreshOn:_table];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountChanged:) name:FPApiAccountNotification object:_api];
    [self.stateView showLoading];
}
- (void)accountChanged:(NSNotification *)note
{
    (void)note;
    ++_serial;
    [_rows release]; _rows = nil;
    [_table reloadData];
    [self.stateView showMessage:@"Аккаунт изменился. Обновите список" retry:YES];
}
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!_loaded) { _loaded = YES; [self reloadFromUser]; }
}
- (void)layoutContent
{
    UIEdgeInsets safe = FPSafeInsets(self.view);
    CGFloat previous = _table.bounds.size.width;
    _table.frame = self.contentView.bounds;
    if (_dialog && previous != _table.bounds.size.width) [_table reloadData];
    _table.contentInset = UIEdgeInsetsMake(4, 0, safe.bottom + 16, 0);
    _table.scrollIndicatorInsets = _table.contentInset;
}
- (void)themeDidChange { [_table reloadData]; }
- (void)reloadFromUser
{
    NSUInteger serial = ++_serial;
    NSInteger account = [_api memberId];
    if (![_rows count]) [self.stateView showLoading];
    FPApiCompletion done = ^(id result, NSError *error) {
        if (serial != _serial) return;
        [self endRefreshing];
        if (account != [_api memberId]) {
            [_rows release]; _rows = nil; [_table reloadData];
            [self.stateView showMessage:@"Аккаунт изменился. Обновите список" retry:YES];
            return;
        }
        if (error) {
            if ([_rows count]) [self showToast:[error localizedDescription]];
            else [self.stateView showMessage:[error localizedDescription] retry:YES];
            return;
        }
        NSArray *rows = result;
        if (_dialog) {
            NSArray *root = result;
            self.appBar.title = [root objectAtIndex:5];
            rows = FPQMSSortedMessages([root objectAtIndex:15]);
        } else if (_member) {
            NSArray *contacts = result;
            rows = [contacts count] ? [[contacts objectAtIndex:0] objectAtIndex:7] : [NSArray array];
        }
        [_rows release]; _rows = [rows retain];
        [_table reloadData];
        if (_dialog && [_rows count]) {
            NSIndexPath *last = [NSIndexPath indexPathForRow:(NSInteger)[_rows count] - 1 inSection:0];
            [_table scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:NO];
        }
        if ([_rows count]) self.stateView.hidden = YES;
        else [self.stateView showMessage:_dialog ? @"В диалоге нет сообщений" : @"Здесь пока пусто" retry:NO];
    };
    if (_dialog) [_api loadQMSTalk:_dialog completion:done];
    else [_api loadQMSContacts:_member completion:done];
}
- (void)compose
{
    FPQMSController *owner = self;
    FPComposeController *composer = [[FPComposeController alloc] initWithApi:_api dialogId:_dialog sent:^{ [owner reloadFromUser]; }];
    [self presentViewController:composer animated:YES completion:nil];
    [composer release];
}
- (void)loadOlder
{
    if (_olderBusy || ![_rows count]) return;
    if ([_rows count] >= 600) { [self showToast:@"Достигнут предел загруженных сообщений"]; return; }
    NSInteger anchor = [[[_rows objectAtIndex:0] objectAtIndex:0] integerValue];
    if (anchor <= 0) { [self showToast:@"Не удалось определить первое сообщение"]; return; }
    NSUInteger serial = ++_serial;
    NSInteger account = [_api memberId];
    _olderBusy = YES;
    [_api loadQMSTalk:_dialog before:anchor completion:^(id result, NSError *error) {
        _olderBusy = NO;
        if (serial != _serial || account != [_api memberId]) return;
        if (error) { [self showToast:[error localizedDescription]]; return; }
        NSArray *page = FPQMSSortedMessages([result objectAtIndex:15]);
        NSMutableSet *known = [NSMutableSet set];
        for (NSArray *message in _rows) [known addObject:[message objectAtIndex:0]];
        NSMutableArray *older = [NSMutableArray array];
        for (NSArray *message in page) if (![known containsObject:[message objectAtIndex:0]]) [older addObject:message];
        if (![older count]) { [self showToast:@"Более ранних сообщений нет"]; return; }
        CGFloat height = _table.contentSize.height;
        CGFloat offset = _table.contentOffset.y;
        NSArray *combined = [older arrayByAddingObjectsFromArray:_rows];
        [_rows release]; _rows = [combined retain];
        [_table reloadData];
        [_table layoutIfNeeded];
        [_table setContentOffset:CGPointMake(0, offset + _table.contentSize.height - height) animated:NO];
    }];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section
{
    (void)table; (void)section; return (NSInteger)[_rows count];
}
- (FPQMSLayout)layoutForRow:(NSInteger)row width:(CGFloat)width
{
    NSArray *above = row > 0 ? [_rows objectAtIndex:(NSUInteger)row - 1] : nil;
    NSArray *below = (NSUInteger)row + 1 < [_rows count] ? [_rows objectAtIndex:(NSUInteger)row + 1] : nil;
    return FPQMSMakeLayout([_rows objectAtIndex:(NSUInteger)row], above, below, [_api memberId], width);
}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path
{
    if (!_dialog) return 64;
    /* the last bubble gets room below it so it does not sit against the tab bar */
    return [self layoutForRow:path.row width:table.bounds.size.width].height + ((NSUInteger)path.row + 1 == [_rows count] ? 8 : 0);
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path
{
    if (_dialog) {
        static NSString *bubbleIdentifier = @"qms-bubble";
        UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:bubbleIdentifier];
        FPQMSBubbleView *bubble;
        NSArray *item = [_rows objectAtIndex:(NSUInteger)path.row];
        FPQMSLayout layout = [self layoutForRow:path.row width:table.bounds.size.width];
        NSUInteger attachments = [[item objectAtIndex:4] count];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:bubbleIdentifier] autorelease];
            cell.backgroundColor = [UIColor clearColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            bubble = [[[FPQMSBubbleView alloc] initWithFrame:cell.contentView.bounds] autorelease];
            bubble.tag = 77;
            bubble.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [cell.contentView addSubview:bubble];
        }
        cell.backgroundView = nil;
        bubble = (FPQMSBubbleView *)[cell.contentView viewWithTag:77];
        bubble.frame = CGRectMake(0, 0, table.bounds.size.width, layout.height);
        [bubble setBody:[item objectAtIndex:3] time:FPQMSTime(FPQMSDate(item)) day:layout.hasDay ? FPQMSDay(FPQMSDate(item)) : nil
                  files:attachments ? [NSString stringWithFormat:@"Вложений: %lu", (unsigned long)attachments] : nil layout:layout];
        return cell;
    }
    static NSString *identifier = @"qms";
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier] autorelease];
    NSArray *item = [_rows objectAtIndex:(NSUInteger)path.row];
    cell.backgroundColor = FPColor(FPRoleContainer);
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.detailTextLabel.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = FPColor(FPRoleOnSurface);
    cell.textLabel.font = FPFont(15, 0, YES);
    cell.textLabel.numberOfLines = 1;
    cell.textLabel.text = [item objectAtIndex:_member ? 3 : 1];
    cell.detailTextLabel.text = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path
{
    [table deselectRowAtIndexPath:path animated:YES];
    if (_dialog) {
        NSArray *files = [[_rows objectAtIndex:(NSUInteger)path.row] objectAtIndex:4];
        if (![files count] || _fileSheet) return;
        _selectedFiles = [files retain];
        _fileSheet = [[UIActionSheet alloc] initWithTitle:@"Вложения" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
        for (NSArray *file in files) [_fileSheet addButtonWithTitle:[file objectAtIndex:2]];
        _fileSheet.cancelButtonIndex = [_fileSheet addButtonWithTitle:@"Отмена"];
        [_fileSheet showInView:self.view];
        return;
    }
    NSArray *item = [_rows objectAtIndex:(NSUInteger)path.row];
    long long identifier = [[item objectAtIndex:0] longLongValue];
    if (identifier < -INT32_MAX || identifier > INT32_MAX) { [self showToast:@"Неверный номер диалога"]; return; }
    if (identifier < 0) identifier = -identifier;
    if (identifier <= 0 || identifier > INT32_MAX) { [self showToast:@"Неверный номер диалога"]; return; }
    FPQMSController *next = _member ? [[FPQMSController alloc] initWithApi:_api dialog:(NSInteger)identifier title:[item objectAtIndex:3]] :
        [[FPQMSController alloc] initWithApi:_api member:(NSInteger)identifier title:[item objectAtIndex:1]];
    [self.navigationController pushViewController:next animated:YES];
    [next release];
}
- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)index
{
    if (index >= 0 && index < (NSInteger)[_selectedFiles count]) {
        NSArray *file = [_selectedFiles objectAtIndex:(NSUInteger)index];
        NSInteger identifier = [[file objectAtIndex:0] integerValue];
        NSString *name = [file objectAtIndex:2];
        if (identifier <= 0) [self showToast:@"Неверный номер вложения"];
        else {
            BOOL started = [FPAttachmentTransfer startWithApi:_api identifier:identifier name:name completion:^(NSString *path, NSError *error) {
                if (error) { [self showToast:[error localizedDescription]]; return; }
                [self showToast:@"Файл сохранён в Documents"];
                if ([FPAttachmentTransfer activeCount] || !self.view.window) return;
                [_documentController release];
                _documentController = [[UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:path]] retain];
                [_documentController presentOpenInMenuFromRect:self.view.bounds inView:self.view animated:YES];
            }];
            [self showToast:started ? @"Загрузка файла…" : @"Одновременно можно загружать до трёх файлов"];
        }
    }
    sheet.delegate = nil;
    [_fileSheet release]; _fileSheet = nil;
    [_selectedFiles release]; _selectedFiles = nil;
}
@end
