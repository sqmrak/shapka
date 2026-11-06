#import "FPPostViews.h"
#import "FPTheme.h"
#import "FPSettings.h"
#import "FPImageLoader.h"
#import <QuartzCore/QuartzCore.h>

#define CARD_PAD 16.0f
#define HEADER_HEIGHT 48.0f
#define AVATAR_SIZE 40.0f
#define CARD_GAP 10.0f

@interface FPTiledLayer : CATiledLayer
@end

@implementation FPTiledLayer
+ (CFTimeInterval)fadeDuration { return 0; }
@end

@implementation FPPostBodyView
@synthesize target = _target;

+ (Class)layerClass { return [FPTiledLayer class]; }

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        FPTiledLayer *tiled = (FPTiledLayer *)self.layer;
        tiled.tileSize = CGSizeMake(512, 512);
        tiled.levelsOfDetail = 1;
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.clearsContextBeforeDrawing = YES;
    }
    return self;
}

- (void)dealloc
{
    [FPImageLoader cancelOwner:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_layout release];
    [super dealloc];
}

- (FPPostLayout *)layout
{
    @synchronized(self) { return [[_layout retain] autorelease]; }
}

- (void)redraw
{
    [self.layer setNeedsDisplay];
}

- (void)setLayout:(FPPostLayout *)layout
{
    FPPostLayout *previous;
    @synchronized(self) {
        previous = _layout;
        _layout = [layout retain];
    }
    [previous release];
    [FPImageLoader cancelOwner:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(redraw) object:nil];
    [self.layer setNeedsDisplay];
    [layout enumerateImages:^(NSString *url, CGSize size, BOOL thumbnail) {
        (void)thumbnail;
        if ([FPImageLoader cachedImageForURL:url size:size circle:NO]) return;
        [FPImageLoader loadURL:url size:size circle:NO owner:self completion:^(UIImage *image) {
            (void)image;
            /* several images often finish together, so one redraw serves them all */
            [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(redraw) object:nil];
            [self performSelector:@selector(redraw) withObject:nil afterDelay:0.05];
        }];
    }];
}

- (void)drawRect:(CGRect)rect
{
    [[self layout] drawInRect:rect];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    _touchStart = [[touches anyObject] locationInView:self];
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    CGPoint end = [[touches anyObject] locationInView:self];
    BOOL moved = fabsf((float)(end.x - _touchStart.x)) > 10 || fabsf((float)(end.y - _touchStart.y)) > 10;
    FPPostHit *hit = moved ? nil : [[self layout] hitTest:end];
    /* a tap on a file, link, picture or spoiler is handled here; ended would also select the table row and open the quote menu on top of the download */
    if (hit) [super touchesCancelled:touches withEvent:event];
    else [super touchesEnded:touches withEvent:event];
    if (hit && [_target respondsToSelector:@selector(bodyHit:)]) [_target performSelector:@selector(bodyHit:) withObject:hit];
}
@end

@interface FPPostHeaderView : UIView {
    NSString *_name;
    NSString *_line;
    NSString *_avatarURL;
    UIColor *_nameColor;
    BOOL _showAvatar;
    BOOL _avatarFailed;
}
- (void)configureName:(NSString *)name line:(NSString *)line avatar:(NSString *)avatar color:(UIColor *)color;
@end

@implementation FPPostHeaderView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)dealloc
{
    [FPImageLoader cancelOwner:self];
    [_name release]; [_line release]; [_avatarURL release]; [_nameColor release];
    [super dealloc];
}

- (void)configureName:(NSString *)name line:(NSString *)line avatar:(NSString *)avatar color:(UIColor *)color
{
    CGSize size = CGSizeMake(AVATAR_SIZE, AVATAR_SIZE);
    [FPImageLoader cancelOwner:self];
    [_name release]; _name = [name copy];
    [_line release]; _line = [line copy];
    [_avatarURL release]; _avatarURL = [avatar copy];
    [_nameColor release]; _nameColor = [color retain];
    _showAvatar = [FPSettings showAvatars];
    _avatarFailed = NO;
    if (_showAvatar && [avatar length] && ![FPImageLoader cachedImageForURL:avatar size:size circle:YES]) {
        [FPImageLoader loadURL:avatar size:size circle:YES owner:self completion:^(UIImage *image) {
            if (!image) _avatarFailed = YES;
            [self setNeedsDisplay];
        }];
    }
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGFloat textX = _showAvatar ? AVATAR_SIZE + 12 : 0, width = self.bounds.size.width - textX;
    (void)rect;
    if (_showAvatar) {
        UIImage *image = [_avatarURL length] ? [FPImageLoader cachedImageForURL:_avatarURL size:CGSizeMake(AVATAR_SIZE, AVATAR_SIZE) circle:YES] : nil;
        CGRect circle = CGRectMake(0, 4, AVATAR_SIZE, AVATAR_SIZE);
        if (image) {
            [image drawInRect:circle];
        } else {
            /* the first letter stands in while the picture loads and when the member has none */
            NSString *letter = [_name length] ? [[_name substringToIndex:1] uppercaseString] : @"?";
            UIFont *font = FPFont(18, 1, NO);
            CGSize size = FPTextSize(letter, font, 0);
            [FPColor(FPRolePrimaryContainer) setFill];
            CGContextFillEllipseInRect(c, circle);
            FPDrawText(letter, font, FPColor(FPRoleOnPrimaryContainer),
                       CGRectMake(circle.origin.x + (AVATAR_SIZE - size.width) / 2 + 0.5f, circle.origin.y + (AVATAR_SIZE - FPLineHeight(font)) / 2, size.width, FPLineHeight(font)), 1);
        }
    }
    FPDrawText(_name, FPFont(16, 1, NO), _nameColor, CGRectMake(textX, 3, width, 22), 1);
    FPDrawText(_line, FPFont(12, 0, NO), FPColor(FPRoleOutline), CGRectMake(textX, 26, width, 18), 1);
}
@end

@implementation FPPostCell
@synthesize delegate = _delegate;

+ (CGFloat)bodyWidthForWidth:(CGFloat)width sideInset:(CGFloat)sideInset
{
    return MAX(80, width - 2 * sideInset - 2 * CARD_PAD);
}

+ (CGFloat)heightForLayout:(FPPostLayout *)layout
{
    return CARD_PAD + HEADER_HEIGHT + 6 + layout.height + CARD_PAD + CARD_GAP;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        _card = [[UIView alloc] init];
        _card.layer.cornerRadius = 24;
        [self.contentView addSubview:_card];
        _header = [[FPPostHeaderView alloc] init];
        [_card addSubview:_header];
        _body = [[FPPostBodyView alloc] init];
        _body.target = self;
        [_card addSubview:_body];
    }
    return self;
}

- (void)dealloc
{
    _body.target = nil;
    [_card release]; [_header release]; [_body release];
    [super dealloc];
}

- (void)bodyHit:(FPPostHit *)hit
{
    [_delegate postCell:self didHit:hit];
}

- (void)configureWithPost:(FPPost *)post layout:(FPPostLayout *)layout width:(CGFloat)width sideInset:(CGFloat)sideInset
{
    CGFloat cardWidth = width - 2 * sideInset, height = [FPPostCell heightForLayout:layout] - CARD_GAP;
    NSMutableString *line = [NSMutableString stringWithString:FPFormatDate(post.date)];
    [line appendFormat:@"  \u00b7  карма %lld", post.reputation];
    if ([post hasRating]) [line appendFormat:@"  \u00b7  оценка %@%ld", [post rating] > 0 ? @"+" : @"", (long)[post rating]];
    self.backgroundColor = [UIColor clearColor];
    _card.backgroundColor = FPColor(FPRoleContainer);
    _card.frame = CGRectMake(sideInset, 0, cardWidth, height);
    _header.frame = CGRectMake(CARD_PAD, CARD_PAD, cardWidth - 2 * CARD_PAD, HEADER_HEIGHT);
    _body.frame = CGRectMake(CARD_PAD, CARD_PAD + HEADER_HEIGHT + 6, cardWidth - 2 * CARD_PAD, layout.height);
    [(FPPostHeaderView *)_header configureName:post.userName line:line avatar:post.avatar color:FPGroupColor(post.group)];
    [_body setLayout:layout];
}
@end
