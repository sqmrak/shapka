#import "FPListKit.h"

#define CARD_OUTER 24.0f
#define CARD_INNER 6.0f
#define ROW_GAP 2.0f
#define TEXT_LEFT 20.0f

CGFloat FPColumnInset(CGFloat width, UIEdgeInsets safe)
{
    CGFloat margin = MAX(12.0f, 0), column = 720.0f;
    CGFloat sides = MAX(safe.left, safe.right) + margin;
    if (width - 2 * sides > column) sides = (width - column) / 2;
    return sides;
}

static UIFont *FPTitleFont(BOOL strong) { return FPFont(16, strong ? 2 : 1, YES); }
static UIFont *FPSubtitleFont(void) { return FPFont(13, 0, YES); }
static UIFont *FPMetaFont(void) { return FPFont(13, 0, YES); }

@implementation FPRowView
@synthesize kind = _kind, position = _position, title = _title, subtitle = _subtitle, meta = _meta, badge = _badge;
@synthesize unread = _unread, dimmed = _dimmed, expanded = _expanded, badgeActive = _badgeActive, highlighted = _highlighted, sideInset = _sideInset;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)dealloc
{
    [_title release]; [_subtitle release]; [_meta release]; [_badge release];
    [super dealloc];
}

- (void)setHighlighted:(BOOL)highlighted
{
    if (_highlighted == highlighted) return;
    _highlighted = highlighted;
    [self setNeedsDisplay];
}

+ (CGFloat)rightReserveForKind:(FPRowKind)kind
{
    return kind == FPRowTopic ? 76.0f : (kind == FPRowForum ? 52.0f : (kind == FPRowSetting ? 120.0f : 24.0f));
}

+ (CGFloat)heightForKind:(FPRowKind)kind title:(NSString *)title subtitle:(NSString *)subtitle width:(CGFloat)width sideInset:(CGFloat)sideInset
{
    CGFloat textWidth = width - 2 * sideInset - TEXT_LEFT - [self rightReserveForKind:kind];
    NSInteger lines;
    CGFloat height;
    switch (kind) {
    case FPRowSection:
        return ceilf(FPLineHeight(FPFont(13, 1, YES))) + 28;
    case FPRowCategory:
        return MAX(56, FPLineHeight(FPFont(15, 1, YES)) + 28);
    case FPRowNotice:
        lines = FPTextLines(title, FPFont(14, 0, YES), width - 2 * sideInset - 2 * TEXT_LEFT, 0);
        return lines * FPLineHeight(FPFont(14, 0, YES)) + 28;
    case FPRowSetting:
        lines = FPTextLines(title, FPTitleFont(NO), textWidth, 2);
        height = 16 + lines * FPLineHeight(FPTitleFont(NO)) + 16;
        if ([subtitle length]) height += FPTextLines(subtitle, FPSubtitleFont(), textWidth, 3) * FPLineHeight(FPSubtitleFont());
        return MAX(64, height) + ROW_GAP;
    case FPRowForum:
        lines = FPTextLines(title, FPTitleFont(NO), textWidth, 2);
        return MAX(60, lines * FPLineHeight(FPTitleFont(NO)) + 30) + ROW_GAP;
    case FPRowTopic:
        lines = FPTextLines(title, FPTitleFont(NO), textWidth, 2);
        height = 16 + lines * FPLineHeight(FPTitleFont(NO)) + 4 + FPLineHeight(FPMetaFont()) + 16;
        if ([subtitle length]) height += FPLineHeight(FPSubtitleFont());
        return MAX(72, height) + ROW_GAP;
    }
    return 56;
}

- (void)drawRect:(CGRect)dirty
{
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    CGRect card;
    CGFloat top, bottom, tl, tr, br, bl, textLeft, textWidth, y;
    CGPathRef path;
    (void)dirty;
    if (_kind == FPRowSection) {
        FPDrawText(_title, FPFont(13, 1, YES), FPColor(FPRolePrimary), CGRectMake(_sideInset + 8, 18, bounds.size.width - 2 * _sideInset - 16, 24), 1);
        return;
    }
    if (_kind == FPRowCategory) {
        UIFont *font = FPFont(15, 1, YES);
        CGFloat midY = bounds.size.height / 2;
        UIImage *chevron = FPIcon(_expanded ? FPIconChevronUp : FPIconChevronDown, 20, FPColor(FPRoleOnVariant));
        FPDrawText(_title, font, FPColor(FPRolePrimary), CGRectMake(_sideInset + 8, midY - FPLineHeight(font) / 2 + 4, bounds.size.width - 2 * _sideInset - 56, FPLineHeight(font)), 1);
        [chevron drawAtPoint:CGPointMake(bounds.size.width - _sideInset - 28, midY - 8)];
        return;
    }
    if (_kind == FPRowNotice) {
        UIFont *font = FPFont(14, 0, YES);
        FPDrawText(_title, font, FPColor(FPRoleOnVariant), CGRectMake(_sideInset + TEXT_LEFT, 14, bounds.size.width - 2 * _sideInset - 2 * TEXT_LEFT, bounds.size.height - 14), 0);
        return;
    }
    top = (_position == FPRowTop || _position == FPRowSingle) ? 0 : ROW_GAP / 2;
    bottom = (_position == FPRowBottom || _position == FPRowSingle) ? ROW_GAP : ROW_GAP / 2;
    card = CGRectMake(_sideInset, top, bounds.size.width - 2 * _sideInset, bounds.size.height - top - bottom);
    tl = tr = (_position == FPRowTop || _position == FPRowSingle) ? CARD_OUTER : CARD_INNER;
    bl = br = (_position == FPRowBottom || _position == FPRowSingle) ? CARD_OUTER : CARD_INNER;
    if (FPThemeIsClassic()) { tl = tr = MIN(tl, 7); bl = br = MIN(bl, 7); }
    path = FPCreateRoundedRect(card, tl, tr, br, bl);
    CGContextAddPath(c, path);
    [_highlighted ? FPColor(FPRoleHighest) : FPColor(FPRoleContainer) setFill];
    CGContextFillPath(c);
    if (FPThemeIsClassic()) {
        CGContextAddPath(c, path);
        [FPColor(FPRoleDivider) setStroke];
        CGContextSetLineWidth(c, 1);
        CGContextStrokePath(c);
    }
    CGPathRelease(path);
    textLeft = card.origin.x + TEXT_LEFT;
    textWidth = card.size.width - TEXT_LEFT - [FPRowView rightReserveForKind:_kind];
    if (_kind == FPRowSetting) {
        UIFont *font = FPTitleFont(NO);
        NSInteger lines = FPTextLines(_title, font, textWidth, 2);
        y = card.origin.y + 16;
        y += FPDrawText(_title, font, FPColor(FPRoleOnSurface), CGRectMake(textLeft, y, textWidth, lines * FPLineHeight(font)), 2);
        if ([_subtitle length]) FPDrawText(_subtitle, FPSubtitleFont(), FPColor(FPRoleOnVariant), CGRectMake(textLeft, y, textWidth, FPTextLines(_subtitle, FPSubtitleFont(), textWidth, 3) * FPLineHeight(FPSubtitleFont())), 3);
        if ([_badge length]) {
            UIFont *badgeFont = FPFont(13, 1, NO);
            CGSize size = FPTextSize(_badge, badgeFont, 0);
            CGFloat pillWidth = MIN(size.width + 24, 150);
            CGRect pill = CGRectMake(CGRectGetMaxX(card) - 16 - pillWidth, CGRectGetMidY(card) - 16, pillWidth, 32);
            CGFloat radius = FPThemeIsClassic() ? 5 : 16;
            CGPathRef pillPath = FPCreateRoundedRect(pill, radius, radius, radius, radius);
            CGContextAddPath(c, pillPath);
            [_badgeActive ? FPColor(FPRolePrimary) : FPColor(FPRoleHighest) setFill];
            CGContextFillPath(c);
            if (FPThemeIsClassic()) {
                CGContextAddPath(c, pillPath);
                [FPColor(FPRoleOutline) setStroke];
                CGContextSetLineWidth(c, 1);
                CGContextStrokePath(c);
            }
            CGPathRelease(pillPath);
            FPDrawText(_badge, badgeFont, _badgeActive ? FPColor(FPRoleOnPrimary) : FPColor(FPRoleOnSurface),
                       CGRectMake(pill.origin.x + 12, pill.origin.y + 6, pillWidth - 24, 20), 1);
        }
        return;
    }
    if (_kind == FPRowForum) {
        UIFont *font = FPTitleFont(_unread);
        NSInteger lines = FPTextLines(_title, font, textWidth, 2);
        CGFloat block = lines * FPLineHeight(font);
        y = card.origin.y + (card.size.height - block) / 2;
        FPDrawText(_title, font, FPColor(FPRoleOnSurface), CGRectMake(textLeft, y, textWidth, block), 2);
        [FPIcon(FPIconChevronRight, 20, FPColor(FPRoleOutline)) drawAtPoint:CGPointMake(CGRectGetMaxX(card) - 34, CGRectGetMidY(card) - 10)];
        if (_unread) {
            [FPColor(FPRolePrimary) setFill];
            CGContextFillEllipseInRect(c, CGRectMake(CGRectGetMaxX(card) - 46, CGRectGetMidY(card) - 4, 8, 8));
        }
        return;
    }
    {
        UIFont *font = FPTitleFont(_unread);
        UIColor *titleColor = _dimmed ? FPColor(FPRoleOnVariant) : FPColor(FPRoleOnSurface);
        NSInteger lines = FPTextLines(_title, font, textWidth, 2);
        y = card.origin.y + 16;
        y += FPDrawText(_title, font, titleColor, CGRectMake(textLeft, y, textWidth, lines * FPLineHeight(font)), 2);
        if ([_subtitle length]) y += FPDrawText(_subtitle, FPSubtitleFont(), FPColor(FPRoleOnVariant), CGRectMake(textLeft, y, textWidth, FPLineHeight(FPSubtitleFont())), 1);
        y += 4;
        FPDrawText(_meta, FPMetaFont(), FPColor(FPRoleOutline), CGRectMake(textLeft, y, textWidth, FPLineHeight(FPMetaFont())), 1);
        if ([_badge length]) {
            UIFont *badgeFont = FPFont(12, 1, NO);
            CGSize size = FPTextSize(_badge, badgeFont, 0);
            CGRect pill = CGRectMake(CGRectGetMaxX(card) - 16 - size.width - 16, card.origin.y + 16, size.width + 16, 26);
            CGPathRef pillPath = FPCreateRoundedRect(pill, 13, 13, 13, 13);
            CGContextAddPath(c, pillPath);
            CGPathRelease(pillPath);
            [FPColor(FPRolePrimaryContainer) setFill];
            CGContextFillPath(c);
            FPDrawText(_badge, badgeFont, FPColor(FPRoleOnPrimaryContainer), CGRectMake(pill.origin.x + 8, pill.origin.y + 4, size.width, 18), 1);
        }
        if (_unread) {
            [FPColor(FPRolePrimary) setFill];
            CGContextFillEllipseInRect(c, CGRectMake(CGRectGetMaxX(card) - 28, CGRectGetMaxY(card) - 28, 10, 10));
        }
    }
}
@end

@implementation FPListCell
@synthesize row = _row;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        _row = [[FPRowView alloc] initWithFrame:self.contentView.bounds];
        _row.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.contentView addSubview:_row];
    }
    return self;
}

- (void)dealloc
{
    [_row release];
    [super dealloc];
}

- (BOOL)isAccessibilityElement { return YES; }

- (NSString *)accessibilityLabel
{
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *part in [NSArray arrayWithObjects:_row.title ?: @"", _row.subtitle ?: @"", _row.meta ?: @"", _row.badge ?: @"", nil]) {
        if ([part length]) [parts addObject:part];
    }
    if (_row.unread) [parts addObject:@"Непрочитанное"];
    return [parts componentsJoinedByString:@", "];
}

- (UIAccessibilityTraits)accessibilityTraits
{
    return _row.kind == FPRowSection ? UIAccessibilityTraitHeader : UIAccessibilityTraitButton;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
    [super setHighlighted:highlighted animated:animated];
    _row.highlighted = highlighted;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
    _row.highlighted = selected || self.highlighted;
}
@end
