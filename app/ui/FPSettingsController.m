#import "FPSettingsController.h"
#import "FPListKit.h"
#import "FPLoginController.h"
#import "FPSettings.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

typedef enum {
    FPSettingTheme,
    FPSettingTone,
    FPSettingTextSize,
    FPSettingMaterialEffect,
    FPSettingPerPage,
    FPSettingAvatars,
    FPSettingSignatures,
    FPSettingAccount,
    FPSettingVersion
} FPSettingId;

@interface FPSettingsRow : NSObject {
@public
    BOOL section;
    FPSettingId identifier;
    NSString *title;
    NSInteger position;
}
@end

@implementation FPSettingsRow
- (void)dealloc { [title release]; [super dealloc]; }
@end

static FPSettingsRow *FPMakeRow(BOOL section, FPSettingId identifier, NSString *title, FPRowPosition position)
{
    FPSettingsRow *row = [[[FPSettingsRow alloc] init] autorelease];
    row->section = section;
    row->identifier = identifier;
    row->title = [title copy];
    row->position = position;
    return row;
}

#define FP_LOCK_TAG 4621

@interface FPLockButton : UIButton
@end
@implementation FPLockButton
- (void)drawRect:(CGRect)rect
{
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat x = CGRectGetMidX(rect), y = CGRectGetMidY(rect);
    CGContextSetStrokeColorWithColor(c, FPColor(FPRoleOnVariant).CGColor);
    CGContextSetLineWidth(c, 2);
    CGContextAddArc(c, x, y - 3, 5, (CGFloat)M_PI, 0, 0);
    CGContextStrokePath(c);
    CGContextStrokeRect(c, CGRectMake(x - 8, y - 3, 16, 12));
}
@end

@interface FPSettingsCell : FPListCell
@end
@implementation FPSettingsCell
- (BOOL)isAccessibilityElement { return [self.contentView viewWithTag:FP_LOCK_TAG] == nil; }
@end

@implementation FPSettingsController

- (id)initWithApi:(FPApi *)api
{
    self = [super initWithApi:api];
    if (self) {
        self.title = @"Настройки";
        _rows = [[NSArray alloc] initWithObjects:
                 FPMakeRow(YES, 0, @"Оформление", FPRowSingle),
                 FPMakeRow(NO, FPSettingTheme, nil, FPRowTop),
                 FPMakeRow(NO, FPSettingTone, nil, FPRowMiddle),
                 FPMakeRow(NO, FPSettingTextSize, nil, FPRowMiddle),
                 FPMakeRow(NO, FPSettingMaterialEffect, nil, FPRowBottom),
                 FPMakeRow(YES, 0, @"Сообщения", FPRowSingle),
                 FPMakeRow(NO, FPSettingPerPage, nil, FPRowTop),
                 FPMakeRow(NO, FPSettingAvatars, nil, FPRowMiddle),
                 FPMakeRow(NO, FPSettingSignatures, nil, FPRowBottom),
                 FPMakeRow(YES, 0, @"Аккаунт", FPRowSingle),
                 FPMakeRow(NO, FPSettingAccount, nil, FPRowSingle),
                 FPMakeRow(YES, 0, @"О программе", FPRowSingle),
                 FPMakeRow(NO, FPSettingVersion, nil, FPRowSingle), nil];
    }
    return self;
}

- (void)dealloc
{
    _choices.delegate = nil;
    [_choices dismissWithClickedButtonIndex:_choices.cancelButtonIndex animated:NO];
    [_choices release];
    _table.delegate = nil;
    _table.dataSource = nil;
    [_table release]; [_rows release];
    [super dealloc];
}

- (void)loadView
{
    [super loadView];
    self.appBar.title = @"4PDA";
    self.appBar.subtitle = @"Настройки";
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.dataSource = self;
    _table.delegate = self;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.backgroundColor = [UIColor clearColor];
    [self.contentView insertSubview:_table belowSubview:self.stateView];
    _memberId = [self.api memberId];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountChanged) name:FPApiAccountNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self accountChanged];
}

- (void)accountChanged
{
    _memberId = [self.api memberId];
    [_table reloadData];
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

- (NSString *)valueForSetting:(FPSettingId)identifier title:(NSString **)title hint:(NSString **)hint active:(BOOL *)active
{
    static NSString *const sizes[] = {@"Мелкий", @"Обычный", @"Крупный"};
    *active = NO;
    switch (identifier) {
    case FPSettingTheme: *title = @"Тема"; *hint = @"Стиль оформления"; return [FPSettings themeStyle] == FPThemeStyleClassic ? @"Классическая" : @"Современная";
    case FPSettingTone: *title = @"Цветовая схема"; *hint = @"Светлая или тёмная"; return [FPSettings themeMode] == FPThemeModeDark ? @"Тёмная" : @"Светлая";
    case FPSettingTextSize: *title = @"Размер текста"; *hint = @"Для сообщений и списков"; return sizes[[FPSettings textSize]];
    case FPSettingMaterialEffect: *title = @"Material эффект"; *hint = @"Волна в углу экрана"; *active = [FPSettings showMaterialEffect]; return FPThemeIsClassic() ? nil : (*active ? @"Вкл" : @"Выкл");
    case FPSettingPerPage:
        *title = @"Сообщений на странице";
        *hint = @"Меньше сообщений загружаются быстрее на старых устройствах";
        return [NSString stringWithFormat:@"%ld", (long)[FPSettings postsPerPage]];
    case FPSettingAvatars: *title = @"Аватары"; *hint = nil; *active = [FPSettings showAvatars]; return *active ? @"Вкл" : @"Выкл";
    case FPSettingSignatures: *title = @"Подписи"; *hint = nil; *active = [FPSettings showSignatures]; return *active ? @"Вкл" : @"Выкл";
    case FPSettingAccount:
        *title = @"Аккаунт";
        *hint = _memberId > 0 ? @"Нажмите, чтобы выйти" : @"Нажмите, чтобы войти";
        *active = _memberId > 0;
        return _memberId > 0 ? [NSString stringWithFormat:@"ID %ld", (long)_memberId] : @"Гость";
    case FPSettingVersion:
        *title = @"Shapka";
        *hint = @"Неофициальный клиент 4PDA";
        return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"FPVersionLabel"];
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section
{
    (void)table;
    (void)section;
    return (NSInteger)[_rows count];
}

- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path
{
    FPSettingsRow *row = [_rows objectAtIndex:(NSUInteger)path.row];
    CGFloat width = table.bounds.size.width, inset = FPColumnInset(width, FPSafeInsets(self.view));
    NSString *title = row->title, *hint = nil;
    BOOL active;
    if (row->section) return [FPRowView heightForKind:FPRowSection title:title subtitle:nil width:width sideInset:inset];
    [self valueForSetting:row->identifier title:&title hint:&hint active:&active];
    return [FPRowView heightForKind:FPRowSetting title:title subtitle:hint width:width sideInset:inset];
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path
{
    static NSString *identifier = @"row";
    FPListCell *cell = (FPListCell *)[table dequeueReusableCellWithIdentifier:identifier];
    FPSettingsRow *item = [_rows objectAtIndex:(NSUInteger)path.row];
    FPRowView *row;
    NSString *title = item->title, *hint = nil, *value = nil;
    BOOL active = NO;
    if (!cell) cell = [[[FPSettingsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    [[cell.contentView viewWithTag:FP_LOCK_TAG] removeFromSuperview];
    row = cell.row;
    row.sideInset = FPColumnInset(table.bounds.size.width, FPSafeInsets(self.view));
    row.subtitle = nil;
    row.badge = nil;
    row.badgeActive = NO;
    if (item->section) {
        row.kind = FPRowSection;
        row.title = title;
    } else {
        value = [self valueForSetting:item->identifier title:&title hint:&hint active:&active];
        row.kind = FPRowSetting;
        row.position = (FPRowPosition)item->position;
        row.title = title;
        row.subtitle = hint;
        row.badge = value;
        row.badgeActive = active;
    }
    if (!item->section && item->identifier == FPSettingMaterialEffect && FPThemeIsClassic()) {
        FPLockButton *lock = [[[FPLockButton alloc] initWithFrame:CGRectZero] autorelease];
        lock.backgroundColor = [UIColor clearColor];
        CGFloat height = [self tableView:table heightForRowAtIndexPath:path];
        lock.frame = CGRectMake(table.bounds.size.width - row.sideInset - 60, (height - 44) / 2, 44, 44);
        lock.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        lock.tag = FP_LOCK_TAG;
        lock.accessibilityLabel = @"Material эффект, недоступен в классической теме";
        [lock addTarget:self action:@selector(materialLocked) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:lock];
    }
    [row setNeedsDisplay];
    return cell;
}

- (void)materialLocked
{
    [FPDialog presentInView:self.view title:@"Material эффект" message:@"В классической теме Material эффект недоступен. Выберите современную тему, чтобы изменить его." fieldText:nil numeric:NO confirm:@"Понятно" handler:nil];
}

- (NSIndexPath *)tableView:(UITableView *)table willSelectRowAtIndexPath:(NSIndexPath *)path
{
    (void)table;
    FPSettingsRow *row = [_rows objectAtIndex:(NSUInteger)path.row];
    if (row->section || (row->identifier == FPSettingMaterialEffect && FPThemeIsClassic())) return nil;
    return path;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path
{
    FPSettingsRow *row = [_rows objectAtIndex:(NSUInteger)path.row];
    [table deselectRowAtIndexPath:path animated:YES];
    if (row->section) return;
    UIImageView *oldRow = nil;
    BOOL toggle = row->identifier == FPSettingMaterialEffect || row->identifier == FPSettingAvatars || row->identifier == FPSettingSignatures;
    UITableViewCell *cell = [table cellForRowAtIndexPath:path];
    if (toggle && cell && cell.bounds.size.width > 0 && cell.bounds.size.height > 0 && !FPReduceMotionEnabled()) {
        UIGraphicsBeginImageContextWithOptions(cell.bounds.size, NO, MIN([[UIScreen mainScreen] scale], 2));
        [cell.layer renderInContext:UIGraphicsGetCurrentContext()];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        oldRow = [[[UIImageView alloc] initWithImage:image] autorelease];
        oldRow.frame = [cell convertRect:cell.bounds toView:self.view];
        oldRow.userInteractionEnabled = NO;
        [self.view addSubview:oldRow];
    }
    switch (row->identifier) {
    case FPSettingTheme:
    case FPSettingTone:
    case FPSettingTextSize:
    case FPSettingPerPage: {
        if (_choices) break;
        CGRect rowFrame = [table rectForRowAtIndexPath:path];
        _themeOrigin = [table convertPoint:CGPointMake(CGRectGetMidX(rowFrame), CGRectGetMidY(rowFrame)) toView:self.view.window];
        NSString *title = row->identifier == FPSettingTheme ? @"Тема" : (row->identifier == FPSettingTone ? @"Цветовая схема" : (row->identifier == FPSettingTextSize ? @"Размер текста" : @"Сообщений на странице"));
        _choices = [[UIActionSheet alloc] initWithTitle:title delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
        _choices.tag = row->identifier;
        NSArray *values = row->identifier == FPSettingTheme ? [NSArray arrayWithObjects:@"Современная", @"Классическая", nil] :
            (row->identifier == FPSettingTone ? [NSArray arrayWithObjects:@"Светлая", @"Тёмная", nil] : (row->identifier == FPSettingTextSize ? [NSArray arrayWithObjects:@"Мелкий", @"Обычный", @"Крупный", nil] : [FPSettings postsPerPageChoices]));
        for (id value in values) [_choices addButtonWithTitle:[value description]];
        _choices.cancelButtonIndex = [_choices addButtonWithTitle:@"Отмена"];
        [_choices showFromRect:rowFrame inView:table animated:YES];
        break;
    }
    case FPSettingMaterialEffect: if (!FPThemeIsClassic()) [FPSettings setShowMaterialEffect:![FPSettings showMaterialEffect]]; break;
    case FPSettingAvatars: [FPSettings setShowAvatars:![FPSettings showAvatars]]; break;
    case FPSettingSignatures: [FPSettings setShowSignatures:![FPSettings showSignatures]]; break;
    case FPSettingAccount: {
        FPLoginController *controller = [[FPLoginController alloc] initWithApi:self.api];
        [self.navigationController pushViewController:controller animated:YES];
        [controller release];
        break;
    }
    case FPSettingVersion: break;
    }
    if (oldRow) {
        FPAnimate(0.25, ^{ oldRow.alpha = 0; oldRow.transform = CGAffineTransformMakeScale(0.98f, 0.98f); }, ^(BOOL finished) {
            (void)finished;
            [oldRow removeFromSuperview];
        });
    }
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (sheet != _choices) return;
    if (buttonIndex != sheet.cancelButtonIndex && buttonIndex >= 0) {
        if (sheet.tag == FPSettingTheme && buttonIndex < 2) {
            FPThemeStyle style = (FPThemeStyle)buttonIndex;
            if (style != [FPSettings themeStyle]) [FPSettings setThemeStyle:style origin:_themeOrigin];
        } else if (sheet.tag == FPSettingTone && buttonIndex < 2) {
            FPThemeMode mode = (FPThemeMode)(buttonIndex + 1);
            if (mode != [FPSettings themeMode]) [FPSettings setThemeMode:mode origin:_themeOrigin];
        } else if (sheet.tag == FPSettingTextSize && buttonIndex < 3) {
            [FPSettings setTextSize:buttonIndex];
        } else if (sheet.tag == FPSettingPerPage && buttonIndex < (NSInteger)[[FPSettings postsPerPageChoices] count]) {
            [FPSettings setPostsPerPage:[[[FPSettings postsPerPageChoices] objectAtIndex:(NSUInteger)buttonIndex] integerValue]];
        }
    }
    sheet.delegate = nil;
    [_choices release];
    _choices = nil;
}

@end
