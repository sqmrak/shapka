#import "FPNewsController.h"
#import "FPListKit.h"
#import "FPNewsCell.h"
#import "FPFavorites.h"
#import <QuartzCore/QuartzCore.h>
#include "fp_news_http.h"
#include "fp_news_article.h"
#include <stdlib.h>

@implementation FPNewsController
- (void)dealloc { _table.delegate = nil; _table.dataSource = nil; [_table release]; [_items release]; [super dealloc]; }
- (void)loadView
{
    [super loadView]; self.appBar.title = @"4PDA"; self.appBar.subtitle = @"Главная";
    [self.appBar addActionWithIcon:FPIconRefresh target:self action:@selector(reloadFromUser)].accessibilityLabel = @"Обновить";
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.delegate = self; _table.dataSource = self; _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.backgroundColor = [UIColor clearColor];
    [self.contentView insertSubview:_table belowSubview:self.stateView];
    [self installRefreshOn:_table];
    [self reloadFromUser];
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
- (void)reloadFromUser
{
    NSUInteger serial = ++_serial;
    if (![_items count]) {
        NSArray *cached = [self.api cachedNews];
        if (cached) { [_items release]; _items = [cached retain]; [_table reloadData]; }
    }
    if (![_items count]) [self.stateView showLoading];
    else self.stateView.hidden = YES;
    [self.api loadNews:^(id items, NSError *error) {
        if (serial != _serial) return;
        [self endRefreshing];
        if (items) {
            [_items release]; _items = [items retain];
            self.stateView.hidden = YES;
            [_table reloadData];
        } else {
            NSString *message = [NSString stringWithFormat:@"Не удалось загрузить новости: %@", [error localizedDescription]];
            if ([_items count]) [self showToast:message]; else [self.stateView showMessage:message retry:YES];
        }
    }];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { (void)table; (void)section; return (NSInteger)[_items count]; }
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path
{ (void)table; (void)path; return 118; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path
{
    FPNewsCell *cell = (FPNewsCell *)[table dequeueReusableCellWithIdentifier:@"news"];
    if (!cell) cell = [[[FPNewsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"news"] autorelease];
    [cell configure:[_items objectAtIndex:(NSUInteger)path.row] inset:FPColumnInset(table.bounds.size.width, FPSafeInsets(self.view))];
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path
{
    [table deselectRowAtIndexPath:path animated:YES];
    FPNewsArticleController *controller = [[FPNewsArticleController alloc] initWithApi:self.api item:[_items objectAtIndex:(NSUInteger)path.row]];
    [self.navigationController pushViewController:controller animated:YES]; [controller release];
}
@end

/* a quotation: the text with a bar of the accent color along its left side */
@interface FPQuoteView : UIView {
@public
    UILabel *_label;
    UIView *_bar;
}
@end

static CGFloat FPNewsLabelHeight(UILabel *label, CGFloat width)
{
    if (![label.text length] || width <= 0) return 0;
    return ceilf([label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height) + 1;
}

@implementation FPQuoteView
- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _label = [[UILabel alloc] init]; _label.backgroundColor = [UIColor clearColor]; _label.numberOfLines = 0; _label.lineBreakMode = NSLineBreakByWordWrapping; [self addSubview:_label];
        _bar = [[UIView alloc] init]; [self addSubview:_bar];
    }
    return self;
}
- (void)dealloc { [_label release]; [_bar release]; [super dealloc]; }
- (void)layoutSubviews
{
    [super layoutSubviews];
    _bar.frame = CGRectMake(0, 0, 3, self.bounds.size.height);
    _label.frame = CGRectMake(14, 0, MAX(0, self.bounds.size.width - 14), self.bounds.size.height);
}
@end

static NSOperationQueue *FPArticleImageQueue;

static NSInteger FPNewsIdentifier(NSDictionary *item)
{
    NSNumber *stored = [item objectForKey:@"news_id"];
    if ([stored isKindOfClass:[NSNumber class]] && [stored longLongValue] > 0 && [stored longLongValue] <= INT32_MAX) return [stored integerValue];
    NSURL *url = [NSURL URLWithString:[item objectForKey:@"url"]];
    NSArray *parts = [[url path] pathComponents];
    if ([parts count] < 5) return 0;
    NSString *year = [parts objectAtIndex:1], *month = [parts objectAtIndex:2], *day = [parts objectAtIndex:3], *number = [parts objectAtIndex:4];
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([year length] != 4 || [month length] != 2 || [day length] != 2 || ![number length] || [number length] > 10 ||
        [year rangeOfCharacterFromSet:nonDigits].location != NSNotFound || [month rangeOfCharacterFromSet:nonDigits].location != NSNotFound ||
        [day rangeOfCharacterFromSet:nonDigits].location != NSNotFound || [number rangeOfCharacterFromSet:nonDigits].location != NSNotFound) return 0;
    long long value = [number longLongValue];
    return value > 0 && value <= INT32_MAX ? (NSInteger)value : 0;
}

@implementation FPNewsArticleController
- (id)initWithApi:(FPApi *)api item:(NSDictionary *)item
{
    self = [super initWithApi:api];
    if (self) _item = [item copy];
    return self;
}
- (void)dealloc
{
    [_heroToken setObject:[NSNumber numberWithBool:YES] forKey:@"cancelled"]; [_heroToken release]; [_item release]; [_scroll release]; [_hero release]; [_articleToken setObject:[NSNumber numberWithBool:YES] forKey:@"cancelled"]; [_articleToken release]; [_blockInfo release]; [_blockViews release]; [_statusLabel release]; [_titleLabel release]; [_summaryLabel release];
    [super dealloc];
}
- (void)loadView
{
    [super loadView]; self.appBar.title = @"Новость";
    _favoriteButton = [self.appBar addActionWithIcon:FPIconStar target:self action:@selector(toggleFavorite)];
    _scroll = [[UIScrollView alloc] init];
    [self.contentView insertSubview:_scroll belowSubview:self.stateView];
    _hero = [[UIImageView alloc] init]; _hero.contentMode = UIViewContentModeScaleAspectFit; _hero.hidden = YES; [_scroll addSubview:_hero];
    [self loadHero];
    _statusLabel = [[UILabel alloc] init]; _statusLabel.backgroundColor = [UIColor clearColor]; _statusLabel.numberOfLines = 0; _statusLabel.lineBreakMode = NSLineBreakByWordWrapping; _statusLabel.text = @"Загружаю статью…";
    [_statusLabel addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openArticleInBrowser)] autorelease]];
    [_scroll addSubview:_statusLabel];
    _blockViews = [[NSMutableArray alloc] init];
    _titleLabel = [[UILabel alloc] init]; _titleLabel.backgroundColor = [UIColor clearColor]; _titleLabel.numberOfLines = 0; _titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _titleLabel.text = [_item objectForKey:@"title"]; [_scroll addSubview:_titleLabel];
    _summaryLabel = [[UILabel alloc] init]; _summaryLabel.backgroundColor = [UIColor clearColor]; _summaryLabel.numberOfLines = 0; _summaryLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _summaryLabel.text = [_item objectForKey:@"summary"]; [_scroll addSubview:_summaryLabel];
    self.stateView.hidden = YES;
    [self themeDidChange];
    [self loadArticle];
}
/* the whole picture of the article stands first, at the width of the column and its own proportions, and the text moves down by its height */
- (void)loadHero
{
    /* the token outlives the screen: the blocks ask it, never the screen, whether the screen is still there */
    NSMutableDictionary *token = [[NSMutableDictionary alloc] init];
    _heroToken = token;
    NSString *url = [[_item objectForKey:@"url"] copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *reason = nil;
        NSString *imageURL = [_item objectForKey:@"image"];
        UIImage *image = [(imageURL ? FPNewsLoadImageAtURL(imageURL, 1280, &reason, ^BOOL{ return [token objectForKey:@"cancelled"] != nil; }) : FPNewsLoadImage(url, 1280, &reason, ^BOOL{ return [token objectForKey:@"cancelled"] != nil; })) retain];
        NSString *failure = [reason copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![token objectForKey:@"cancelled"]) {
                if (image) { _hero.image = image; _hero.hidden = NO; [self.view setNeedsLayout]; }
                else if (failure) NSLog(@"shapka: article picture not shown: %@", failure);
            }
            [image release]; [failure release];
        });
        [url release];
        [pool drain];
    });
}
- (void)openArticleInBrowser
{
    NSURL *address = [NSURL URLWithString:[_item objectForKey:@"url"]];
    if (address) [self openInBrowser:address];
}
/* the whole page is read and the text of the article is cut out of it: the paragraphs, headings, lists, quotations, pictures and the places of videos */
- (void)loadArticle
{
    NSMutableDictionary *token = [[NSMutableDictionary alloc] init];
    NSString *url = [[_item objectForKey:@"url"] copy];
    NSString *roots = [[[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"] copy];
    _articleToken = token;
    NSInteger identifier = FPNewsIdentifier(_item);
    if (identifier > 0) {
        [url release]; [roots release];
        [self.api loadNewsArticle:identifier completion:^(id blocks, NSError *error) {
            if ([token objectForKey:@"cancelled"]) return;
            if ([blocks count]) [self showArticleBlocks:blocks];
            else {
                _statusLabel.text = [NSString stringWithFormat:@"Не удалось загрузить статью: %@. Нажмите, чтобы открыть в браузере.", [error localizedDescription]];
                _statusLabel.userInteractionEnabled = YES;
                [self.view setNeedsLayout];
            }
        }];
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSMutableArray *blocks = nil;
        NSString *failure = nil;
        NSRange host = [url rangeOfString:@"4pda.to"];
        NSString *path = host.location == NSNotFound ? nil : [url substringFromIndex:NSMaxRange(host)];
        uint8_t *body = NULL; size_t length = 0; int http = 0;
        fp_session_status status = FP_SESSION_ARGUMENT;
        if ([path length]) status = fp_news_get_head([roots fileSystemRepresentation], [path UTF8String], 1024u * 1024u, &body, &length, &http);
        if (![path length]) failure = @"Адрес статьи не разобран";
        else if (status != FP_SESSION_OK) failure = [NSString stringWithFormat:@"Не удалось загрузить статью (ошибка сети %d)", (int)status];
        else if (http == 403) failure = @"4pda просит подтвердить, что вы человек, и не отдаёт статью приложению. Нажмите здесь, чтобы открыть её в браузере.";
        else if (http != 200) failure = [NSString stringWithFormat:@"Сервер ответил на запрос статьи: HTTP %d", http];
        else {
            NSString *page = [[NSString alloc] initWithBytes:body length:length encoding:NSWindowsCP1251StringEncoding];
            NSData *utf8 = [page dataUsingEncoding:NSUTF8StringEncoding];
            fp_article article;
            fp_article_status parsed = utf8 ? fp_article_parse([utf8 bytes], [utf8 length], &article) : FP_ARTICLE_ARGUMENT;
            if (parsed == FP_ARTICLE_OK || parsed == FP_ARTICLE_PARTIAL) {
                blocks = [NSMutableArray arrayWithCapacity:article.count];
                for (size_t i = 0; i < article.count; i++) {
                    NSString *text = [NSString stringWithUTF8String:fp_article_text(&article, i)];
                    if (!text) continue;
                    [blocks addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:article.blocks[i].kind], @"kind", text, @"text",
                        [NSNumber numberWithInt:article.blocks[i].width], @"width", [NSNumber numberWithInt:article.blocks[i].height], @"height", nil]];
                }
                if (parsed == FP_ARTICLE_PARTIAL) [blocks addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:FP_ARTICLE_PARAGRAPH], @"kind",
                    @"Статья показана не полностью, остальное можно прочитать в браузере.", @"text", [NSNumber numberWithInt:0], @"width", [NSNumber numberWithInt:0], @"height", nil]];
                fp_article_free(&article);
            } else NSLog(@"shapka: article text not found (parser status %d)", (int)parsed);
            [page release];
        }
        free(body);
        BOOL http403 = http == 403;
        [blocks retain]; [failure retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![token objectForKey:@"cancelled"]) {
                if ([blocks count]) [self showArticleBlocks:blocks];
                else {
                    _statusLabel.text = failure ? failure : @"";
                    _statusLabel.userInteractionEnabled = http403;
                    [self.view setNeedsLayout];
                }
            }
            [blocks release]; [failure release];
        });
        [pool drain];
    });
    [url release]; [roots release];
}

- (void)showArticleBlocks:(NSArray *)blocks
{
    NSMutableDictionary *token = _articleToken;
    [_blockInfo release]; _blockInfo = [blocks retain];
    _statusLabel.hidden = YES;
    _summaryLabel.hidden = YES;
    if (!FPArticleImageQueue) { FPArticleImageQueue = [[NSOperationQueue alloc] init]; [FPArticleImageQueue setMaxConcurrentOperationCount:2]; }
    for (NSUInteger i = 0; i < [blocks count]; i++) {
        NSDictionary *block = [blocks objectAtIndex:i];
        int kind = [[block objectForKey:@"kind"] intValue];
        NSString *text = [block objectForKey:@"text"];
        UIView *view;
        if (kind == FP_ARTICLE_IMAGE) {
            UIImageView *picture = [[[UIImageView alloc] init] autorelease];
            picture.contentMode = UIViewContentModeScaleAspectFit;
            picture.clipsToBounds = YES;
            picture.layer.cornerRadius = 14;
            view = picture;
            [FPArticleImageQueue addOperationWithBlock:^{
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                NSString *reason = nil;
                UIImage *image = [FPNewsLoadImageAtURL(text, 1024, &reason, ^BOOL{ return [token objectForKey:@"cancelled"] != nil; }) retain];
                NSString *failure = [reason copy];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (![token objectForKey:@"cancelled"]) {
                        if (image) { picture.image = image; picture.backgroundColor = [UIColor clearColor]; [self.view setNeedsLayout]; }
                        else if (failure) NSLog(@"shapka: article picture not shown: %@", failure);
                    }
                    [image release]; [failure release];
                });
                [pool drain];
            }];
        } else if (kind == FP_ARTICLE_VIDEO) {
            FPPillButton *watch = [FPPillButton buttonWithType:UIButtonTypeCustom];
            [watch setTitle:@"Смотреть видео" forState:UIControlStateNormal];
            watch.tag = (NSInteger)i;
            [watch addTarget:self action:@selector(openVideo:) forControlEvents:UIControlEventTouchUpInside];
            view = watch;
        } else if (kind == FP_ARTICLE_QUOTE) {
            FPQuoteView *quote = [[[FPQuoteView alloc] init] autorelease];
            quote->_label.text = text;
            view = quote;
        } else {
            UILabel *label = [[[UILabel alloc] init] autorelease];
            label.backgroundColor = [UIColor clearColor];
            label.numberOfLines = 0;
            label.lineBreakMode = NSLineBreakByWordWrapping;
            label.text = kind == FP_ARTICLE_ITEM ? [@"\u2022  " stringByAppendingString:text] : text;
            view = label;
        }
        view.tag = kind == FP_ARTICLE_VIDEO ? (NSInteger)i : kind + 1000;
        [_scroll addSubview:view];
        [_blockViews addObject:view];
    }
    [self themeDidChange];
}

- (void)openVideo:(UIButton *)button
{
    if (button.tag >= 0 && (NSUInteger)button.tag < [_blockInfo count]) [self openLink:[[_blockInfo objectAtIndex:(NSUInteger)button.tag] objectForKey:@"text"]];
}

- (void)updateFavorite
{
    BOOL saved = [FPFavorites containsNews:[_item objectForKey:@"url"]];
    [_favoriteButton setImage:FPIcon(saved ? FPIconStarFilled : FPIconStar, 24, FPThemeIsClassic() ? [UIColor whiteColor] : FPColor(FPRoleOnSurface)) forState:UIControlStateNormal];
    _favoriteButton.accessibilityLabel = saved ? @"Убрать из избранного" : @"Добавить в избранное";
}
- (void)toggleFavorite
{
    NSString *url = [_item objectForKey:@"url"];
    if ([FPFavorites containsNews:url]) { [FPFavorites removeNews:url]; [self showToast:@"Новость удалена из избранного"]; }
    else if ([FPFavorites addNews:_item]) [self showToast:@"Новость добавлена в избранное"];
    else [self showToast:@"Не удалось сохранить новость"];
    [self updateFavorite];
}
- (void)themeDidChange
{
    _titleLabel.font = FPFont(22, 2, YES); _titleLabel.textColor = FPColor(FPRoleOnSurface);
    _summaryLabel.font = FPFont(16, 0, YES); _summaryLabel.textColor = FPColor(FPRoleOnVariant);
    _statusLabel.font = FPFont(14, 1, NO); _statusLabel.textColor = FPColor(FPRoleOnVariant);
    for (UIView *view in _blockViews) {
        NSInteger kind = view.tag - 1000;
        if ([view isKindOfClass:[UIImageView class]]) { if (!((UIImageView *)view).image) view.backgroundColor = FPColor(FPRoleHighest); }
        else if ([view isKindOfClass:[FPPillButton class]]) [(FPPillButton *)view applyTheme];
        else if ([view isKindOfClass:[FPQuoteView class]]) {
            FPQuoteView *quote = (FPQuoteView *)view;
            quote->_label.font = FPFont(16, 0, YES); quote->_label.textColor = FPColor(FPRoleOnVariant); quote->_bar.backgroundColor = FPColor(FPRolePrimary);
        } else if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;
            label.font = kind == FP_ARTICLE_HEADING ? FPFont(19, 2, YES) : FPFont(16, 0, YES);
            label.textColor = FPColor(FPRoleOnSurface);
        }
    }
    [self updateFavorite]; [self.view setNeedsLayout];
}
- (void)layoutContent
{
    UIEdgeInsets safe = FPSafeInsets(self.view);
    _scroll.frame = self.contentView.bounds;
    CGFloat width = MIN(_scroll.bounds.size.width - 2 * MAX(24, MAX(safe.left, safe.right) + 12), 620);
    CGFloat x = (_scroll.bounds.size.width - width) / 2, y = 24;
    if (!_hero.hidden && _hero.image.size.width > 0) {
        CGFloat height = ceil(width * _hero.image.size.height / _hero.image.size.width);
        _hero.frame = CGRectMake(x, y, width, MIN(height, 1.6f * width)); y += _hero.frame.size.height + 16;
    }
    CGFloat titleHeight = FPNewsLabelHeight(_titleLabel, width);
    _titleLabel.frame = CGRectMake(x, y, width, titleHeight); y += titleHeight + 16;
    if (_blockInfo) {
        NSInteger previous = -1;
        for (NSUInteger i = 0; i < [_blockViews count]; i++) {
            UIView *view = [_blockViews objectAtIndex:i];
            NSInteger kind = [[[_blockInfo objectAtIndex:i] objectForKey:@"kind"] intValue];
            CGFloat height;
            /* a heading stands closer to what it introduces than to what came before */
            y += previous < 0 ? 0 : (kind == FP_ARTICLE_HEADING ? 22 : (previous == FP_ARTICLE_ITEM && kind == FP_ARTICLE_ITEM ? 6 : 14));
            if (kind == FP_ARTICLE_IMAGE) {
                UIImage *image = ((UIImageView *)view).image;
                int w = [[[_blockInfo objectAtIndex:i] objectForKey:@"width"] intValue], h = [[[_blockInfo objectAtIndex:i] objectForKey:@"height"] intValue];
                CGFloat ratio = image && image.size.width > 0 ? image.size.height / image.size.width : (w > 0 && h > 0 ? (CGFloat)h / w : 0.5625f);
                height = ceil(width * MIN(MAX(ratio, 0.2f), 1.6f));
            } else if (kind == FP_ARTICLE_VIDEO) {
                height = 44;
            } else if (kind == FP_ARTICLE_QUOTE) {
                FPQuoteView *quote = (FPQuoteView *)view;
                height = FPNewsLabelHeight(quote->_label, width - 14);
            } else {
                UILabel *label = (UILabel *)view;
                height = FPNewsLabelHeight(label, width);
            }
            if (kind == FP_ARTICLE_VIDEO) view.frame = CGRectMake(x, y, MIN(width, MAX(180, [(FPPillButton *)view sizeThatFits:CGSizeZero].width)), height);
            else view.frame = CGRectMake(x, y, width, height);
            y += height;
            previous = kind;
        }
        y += 24;
    } else if (!_statusLabel.hidden) {
        CGFloat height = FPNewsLabelHeight(_summaryLabel, width);
        _summaryLabel.frame = CGRectMake(x, y, width, height); y += height + 12;
        height = FPNewsLabelHeight(_statusLabel, width);
        _statusLabel.frame = CGRectMake(x, y, width, height); y += height + 24;
    }
    _scroll.contentSize = CGSizeMake(_scroll.bounds.size.width, y + safe.bottom);
}
@end
