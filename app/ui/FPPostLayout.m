#import "FPPostLayout.h"
#import "FPTheme.h"
#import "FPSettings.h"
#import "FPImageLoader.h"
#import <CoreText/CoreText.h>
#include "fp_bbcode.h"
#include "fp_text.h"

#define SPOILER_HEADER_HEIGHT 40.0f
#define TEXT_CHUNK 1400
#define THUMB_SIZE 96.0f
#define THUMB_GAP 8.0f
#define IMAGE_MAX_HEIGHT 260.0f
#define IMAGE_SLOT_HEIGHT 180.0f
#define BOX_INDENT 14.0f
#define BOX_PAD 8.0f
#define BLOCK_GAP 6.0f

static NSString *const FPAttrLink = @"FPLink";
static NSString *const FPAttrStrike = @"FPStrike";
static NSString *const FPAttrImage = @"FPImage";
/* an icon up to this many pixels each way sits in the line of text, as a smiley or the envelope before a link does in the original client */
#define INLINE_IMAGE_MAX 32.0f
#define INLINE_IMAGE_GAP 4.0f

@implementation FPPostHit
- (void)dealloc { [link release]; [fileName release]; [super dealloc]; }
@end

/* one tag or text run of a parsed message */
@interface FPBBNode : NSObject {
@public
    fp_bb_tag tag;
    NSString *argument;
    NSString *text;
    NSMutableArray *children;
    NSInteger spoilerIndex;
}
@end

@implementation FPBBNode
- (void)dealloc { [argument release]; [text release]; [children release]; [super dealloc]; }
@end

@interface FPPostContent : NSObject {
@public
    FPBBNode *body;
    FPBBNode *signature;
    NSArray *attachments;
    NSString *footer;
}
@end

@implementation FPPostContent
- (void)dealloc { [body release]; [signature release]; [attachments release]; [footer release]; [super dealloc]; }
@end

typedef enum { FPItemText, FPItemFill, FPItemBar, FPItemImage, FPItemHeader, FPItemFile } FPItemKind;

@interface FPInlineImage : NSObject {
@public
    NSString *url;
    CGRect rect;
}
@end

@implementation FPInlineImage
- (void)dealloc { [url release]; [super dealloc]; }
@end

@interface FPLayoutItem : NSObject {
@public
    FPItemKind kind;
    CGRect rect;
    CTFrameRef frame;
    NSAttributedString *string;
    FPRole color;
    CGFloat radius;
    NSString *url;
    NSString *title;
    NSInteger spoiler;
    NSInteger attachmentId;
    NSString *fileName;
    BOOL expanded;
    BOOL thumbnail;
    NSArray *inlines;
}
@end

@implementation FPLayoutItem
- (void)dealloc
{
    if (frame) CFRelease(frame);
    [string release]; [url release]; [title release]; [fileName release]; [inlines release];
    [super dealloc];
}
@end

static NSString *FPUtf8(const char *bytes, size_t length, BOOL entities)
{
    char *buffer;
    size_t written = length;
    NSString *result;
    if (!length) return @"";
    buffer = (char *)malloc(length + 1);
    if (!buffer) return @"";
    if (entities) written = fp_text_unescape_entities(bytes, length, buffer, length + 1);
    else memcpy(buffer, bytes, length);
    result = [[[NSString alloc] initWithBytes:buffer length:written encoding:NSUTF8StringEncoding] autorelease];
    free(buffer);
    return result ? result : @"";
}

/* a tag title or argument without its own tags and with entities resolved */
static NSString *FPPlainArgument(NSString *argument)
{
    NSData *data = [argument dataUsingEncoding:NSUTF8StringEncoding];
    char *buffer = (char *)malloc([data length] + 1);
    NSString *result;
    size_t written;
    if (!buffer) return @"";
    written = fp_bb_strip((const char *)[data bytes], [data length], buffer, [data length] + 1);
    result = FPUtf8(buffer, written, YES);
    free(buffer);
    return result;
}

static void FPBuildTree(const char *source, const fp_bb_node *nodes, size_t count, size_t *cursor, FPBBNode *parent, NSInteger *spoilers)
{
    while (*cursor < count) {
        const fp_bb_node *n = &nodes[*cursor];
        FPBBNode *node;
        (*cursor)++;
        if (n->kind == FP_BB_CLOSE) return;
        node = [[FPBBNode alloc] init];
        node->children = [[NSMutableArray alloc] init];
        if (n->kind == FP_BB_TEXT) {
            node->text = [FPUtf8(source + n->start, n->length, NO) retain];
        } else {
            node->tag = n->tag;
            node->argument = [FPUtf8(source + n->start, n->length, NO) retain];
            if (n->tag == FP_BB_SPOILER || n->tag == FP_BB_HIDE) node->spoilerIndex = (*spoilers)++;
            if (n->tag != FP_BB_ITEM && n->tag != FP_BB_BREAK) FPBuildTree(source, nodes, count, cursor, node, spoilers);
        }
        [parent->children addObject:node];
        [node release];
    }
}

static FPBBNode *FPParseBody(NSString *body)
{
    NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
    size_t length = [data length], count = 0, cursor = 0;
    NSInteger spoilers = 0;
    fp_bb_node *nodes;
    FPBBNode *root = [[[FPBBNode alloc] init] autorelease];
    root->children = [[NSMutableArray alloc] init];
    if (!length) return root;
    if (length > FP_BB_SOURCE_LIMIT) length = FP_BB_SOURCE_LIMIT;
    nodes = (fp_bb_node *)malloc(FP_BB_NODE_BOUND(length) * sizeof(*nodes));
    if (!nodes) return root;
    /* on a limit the nodes written so far are still a valid prefix of the message */
    fp_bb_parse((const char *)[data bytes], length, nodes, FP_BB_NODE_BOUND(length), &count);
    FPBuildTree((const char *)[data bytes], nodes, count, &cursor, root, &spoilers);
    free(nodes);
    return root;
}

static NSString *FPPlainText(FPBBNode *node)
{
    NSMutableString *text = [NSMutableString string];
    FPBBNode *child;
    if (node->text) return node->text;
    for (child in node->children) [text appendString:FPPlainText(child)];
    return text;
}

typedef struct {
    BOOL bold, italic, underline, strike, mono, dim;
    int rgb;
    CGFloat factor;
    int align;
    NSString *link;
} FPStyle;

typedef struct {
    NSMutableArray *items;
    NSMutableAttributedString *run;
    FPPostContent *content;
    NSIndexSet *spoilers;
    NSMutableSet *used;
    NSMutableSet *awaiting;
    CGFloat y, x, width, base;
} FPBuilder;

static CTFontRef FPBodyFont(BOOL bold, BOOL italic, BOOL mono, CGFloat size)
{
    static NSMutableDictionary *cache;
    NSString *key = [NSString stringWithFormat:@"%d%d%d/%.1f", bold, italic, mono, size];
    NSValue *value;
    CTFontRef font;
    @synchronized([FPBBNode class]) {
        if (!cache) cache = [[NSMutableDictionary alloc] init];
        value = [cache objectForKey:key];
        if (value) return (CTFontRef)[value pointerValue];
        if (mono) {
            NSString *name = [UIFont fontWithName:@"Menlo-Regular" size:size] ? @"Menlo-Regular" : @"Courier";
            font = CTFontCreateWithName((CFStringRef)name, size, NULL);
        } else {
            CGAffineTransform skew = CGAffineTransformMake(1, 0, 0.2f, 1, 0, 0);
            font = CTFontCreateWithName((CFStringRef)(bold ? @"Rubik-Bold" : @"Rubik-Regular"), size, italic ? &skew : NULL);
        }
        if (font) [cache setObject:[NSValue valueWithPointer:font] forKey:key];
    }
    return font;
}

/* black text of a message would vanish on the dark surface, and pale text on the light one */
static UIColor *FPAdaptedColor(int rgb)
{
    CGFloat r = ((rgb >> 16) & 0xFF) / 255.0f, g = ((rgb >> 8) & 0xFF) / 255.0f, b = (rgb & 0xFF) / 255.0f;
    CGFloat luma = 0.299f * r + 0.587f * g + 0.114f * b, mix;
    if (FPThemeIsDark() && luma < 0.42f) {
        mix = 0.55f;
        r += (1 - r) * mix; g += (1 - g) * mix; b += (1 - b) * mix;
    } else if (!FPThemeIsDark() && luma > 0.8f) {
        mix = 0.5f;
        r *= 1 - mix; g *= 1 - mix; b *= 1 - mix;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}

static CTParagraphStyleRef FPParagraph(int align)
{
    static CTParagraphStyleRef cache[3];
    @synchronized([FPBBNode class]) {
        if (!cache[align]) {
            CTTextAlignment alignment = align == 1 ? kCTTextAlignmentCenter : (align == 2 ? kCTTextAlignmentRight : kCTTextAlignmentLeft);
            CGFloat spacing = 3;
            CTParagraphStyleSetting settings[] = {
                {kCTParagraphStyleSpecifierAlignment, sizeof(alignment), &alignment},
                {kCTParagraphStyleSpecifierLineSpacingAdjustment, sizeof(spacing), &spacing},
            };
            cache[align] = CTParagraphStyleCreate(settings, 2);
        }
    }
    return cache[align];
}

static void FPAppend(FPBuilder *b, NSString *text, const FPStyle *style)
{
    NSMutableDictionary *attributes;
    UIColor *color;
    CGFloat size = b->base * style->factor;
    NSString *clean = text;
    if (![clean length]) return;
    /* a block never starts with the line break that follows its opening tag */
    if (![b->run length]) {
        NSUInteger skip = 0;
        while (skip < [clean length] && ([clean characterAtIndex:skip] == '\n' || [clean characterAtIndex:skip] == '\r')) skip++;
        clean = [clean substringFromIndex:skip];
        if (![clean length]) return;
    }
    if (style->link) color = FPColor(FPRoleLink);
    else if (style->rgb >= 0) color = FPAdaptedColor(style->rgb);
    else color = FPColor(style->dim ? FPRoleOnVariant : FPRoleOnSurface);
    attributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                  (id)FPBodyFont(style->bold, style->italic, style->mono, size), (id)kCTFontAttributeName,
                  (id)color.CGColor, (id)kCTForegroundColorAttributeName,
                  (id)FPParagraph(style->align), (id)kCTParagraphStyleAttributeName, nil];
    if (style->underline || style->link) [attributes setObject:[NSNumber numberWithInt:kCTUnderlineStyleSingle] forKey:(id)kCTUnderlineStyleAttributeName];
    if (style->link) [attributes setObject:style->link forKey:FPAttrLink];
    if (style->strike) [attributes setObject:[NSNumber numberWithBool:YES] forKey:FPAttrStrike];
    [b->run appendAttributedString:[[[NSAttributedString alloc] initWithString:clean attributes:attributes] autorelease]];
}

/* the boxes of the pictures set in the text, in the coordinates of the layout */
static NSArray *FPInlineImages(CTFrameRef frame, CGPoint origin, CGFloat height)
{
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex count = CFArrayGetCount(lines), i;
    NSMutableArray *found = nil;
    CGPoint *origins;
    if (!count) return nil;
    origins = (CGPoint *)malloc(sizeof(CGPoint) * (size_t)count);
    if (!origins) return nil;
    CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), origins);
    for (i = 0; i < count; i++) {
        CFArrayRef runs = CTLineGetGlyphRuns((CTLineRef)CFArrayGetValueAtIndex(lines, i));
        CFIndex k, runCount = CFArrayGetCount(runs);
        for (k = 0; k < runCount; k++) {
            CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, k);
            NSString *url = [(NSDictionary *)CTRunGetAttributes(run) objectForKey:FPAttrImage];
            CGFloat ascent, descent, leading, width;
            CGPoint position;
            FPInlineImage *icon;
            if (!url) continue;
            width = (CGFloat)CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &ascent, &descent, &leading);
            CTRunGetPositions(run, CFRangeMake(0, 1), &position);
            icon = [[[FPInlineImage alloc] init] autorelease];
            icon->url = [url copy];
            icon->rect = CGRectMake(origin.x + origins[i].x + position.x, origin.y + height - (origins[i].y + position.y + ascent),
                                    width - INLINE_IMAGE_GAP, ascent);
            if (!found) found = [NSMutableArray array];
            [found addObject:icon];
        }
    }
    free(origins);
    return found;
}

static void FPAddText(FPBuilder *b, NSAttributedString *string)
{
    CTFramesetterRef setter = CTFramesetterCreateWithAttributedString((CFAttributedStringRef)string);
    CGSize size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRangeMake(0, 0), NULL, CGSizeMake(b->width, CGFLOAT_MAX), NULL);
    CGFloat height = ceilf(size.height) + 1;
    CGMutablePathRef path = CGPathCreateMutable();
    FPLayoutItem *item = [[FPLayoutItem alloc] init];
    CGPathAddRect(path, NULL, CGRectMake(0, 0, b->width, height));
    item->kind = FPItemText;
    item->rect = CGRectMake(b->x, b->y, b->width, height);
    item->string = [string retain];
    item->frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, NULL);
    item->inlines = [FPInlineImages(item->frame, item->rect.origin, height) retain];
    [b->items addObject:item];
    [item release];
    CGPathRelease(path);
    CFRelease(setter);
    b->y += height;
}

/* ends the running paragraph; long text is cut at line breaks so no frame grows past what a tile can draw cheaply */
static void FPFlush(FPBuilder *b)
{
    NSMutableAttributedString *run = b->run;
    NSString *plain = [run string];
    NSUInteger start = 0, length = [plain length];
    while (length > 0) {
        unichar c = [plain characterAtIndex:length - 1];
        if (c != '\n' && c != '\r' && c != ' ') break;
        length--;
    }
    while (start < length) {
        NSUInteger end = MIN(start + TEXT_CHUNK, length);
        if (end < length) {
            NSRange cut = [plain rangeOfString:@"\n" options:NSBackwardsSearch range:NSMakeRange(start, end - start)];
            if (cut.location != NSNotFound && cut.location > start) end = cut.location + 1;
        }
        FPAddText(b, [run attributedSubstringFromRange:NSMakeRange(start, end - start)]);
        start = end;
    }
    if (length > 0) b->y += BLOCK_GAP;
    [run deleteCharactersInRange:NSMakeRange(0, [run length])];
}

static void FPLayoutNodes(FPBuilder *b, NSArray *nodes, FPStyle style);

static FPLayoutItem *FPAddItem(FPBuilder *b, FPItemKind kind, CGRect rect)
{
    FPLayoutItem *item = [[[FPLayoutItem alloc] init] autorelease];
    item->kind = kind;
    item->rect = rect;
    [b->items addObject:item];
    return item;
}

/* a block with a bar and a tinted ground, laid out in a narrower column */
static void FPBox(FPBuilder *b, FPBBNode *node, FPStyle style, FPRole barRole, NSString *header)
{
    CGFloat savedX = b->x, savedWidth = b->width, top, height;
    FPLayoutItem *fill, *bar;
    FPFlush(b);
    top = b->y;
    fill = FPAddItem(b, FPItemFill, CGRectZero);
    bar = FPAddItem(b, FPItemBar, CGRectZero);
    fill->color = FPRoleHighest;
    fill->radius = 12;
    bar->color = barRole;
    b->y += BOX_PAD;
    b->x += BOX_INDENT;
    b->width = MAX(60, b->width - BOX_INDENT - BOX_PAD);
    if ([header length]) {
        FPStyle small = style;
        small.bold = YES;
        small.factor = 0.88f;
        small.dim = YES;
        FPAppend(b, header, &small);
        FPFlush(b);
    }
    FPLayoutNodes(b, node->children, style);
    FPFlush(b);
    b->x = savedX;
    b->width = savedWidth;
    height = MAX(b->y - top + BOX_PAD - BLOCK_GAP, 24);
    fill->rect = CGRectMake(b->x, top, b->width, height);
    bar->rect = CGRectMake(b->x, top + 4, 3, height - 8);
    b->y = top + height + BLOCK_GAP + 2;
}

static void FPSpoiler(FPBuilder *b, FPBBNode *node, FPStyle style, NSString *fallback)
{
    NSString *title = FPPlainArgument(node->argument);
    BOOL open = [b->spoilers containsIndex:(NSUInteger)node->spoilerIndex];
    FPLayoutItem *header;
    FPFlush(b);
    header = FPAddItem(b, FPItemHeader, CGRectMake(b->x, b->y, b->width, SPOILER_HEADER_HEIGHT));
    header->title = [([title length] ? title : fallback) retain];
    header->spoiler = node->spoilerIndex;
    header->expanded = open;
    b->y += SPOILER_HEADER_HEIGHT + 4;
    if (open) FPBox(b, node, style, FPRoleOutline, nil);
}

static void FPInlineDealloc(void *ref) { [(id)ref release]; }
static CGFloat FPInlineAscent(void *ref) { return [(NSValue *)ref CGSizeValue].height; }
static CGFloat FPInlineDescent(void *ref) { (void)ref; return 0; }
static CGFloat FPInlineWidth(void *ref) { return [(NSValue *)ref CGSizeValue].width + INLINE_IMAGE_GAP; }

/* a placeholder run of the size of the picture; the picture itself is drawn over it once it is decoded */
static void FPAppendInlineImage(FPBuilder *b, NSString *url, CGSize size, const FPStyle *style)
{
    CTRunDelegateCallbacks callbacks = {kCTRunDelegateVersion1, FPInlineDealloc, FPInlineAscent, FPInlineDescent, FPInlineWidth};
    CTRunDelegateRef delegate = CTRunDelegateCreate(&callbacks, [[NSValue valueWithCGSize:size] retain]);
    NSMutableDictionary *attributes;
    if (!delegate) return;
    attributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                  (id)FPBodyFont(NO, NO, NO, b->base * style->factor), (id)kCTFontAttributeName,
                  (id)delegate, (id)kCTRunDelegateAttributeName,
                  (id)[UIColor clearColor].CGColor, (id)kCTForegroundColorAttributeName,
                  (id)FPParagraph(style->align), (id)kCTParagraphStyleAttributeName,
                  url, FPAttrImage, nil];
    if (style->link) [attributes setObject:style->link forKey:FPAttrLink];
    [b->run appendAttributedString:[[[NSAttributedString alloc] initWithString:@"\uFFFC" attributes:attributes] autorelease]];
    CFRelease(delegate);
}

/* a message is laid out before its pictures arrive: a size known from an earlier download decides between a place in the
   line and a block of the real proportions, and an unknown one gets a slot that is laid out again when the size is read */
static void FPImage(FPBuilder *b, NSString *url, NSString *title, const FPStyle *style)
{
    FPLayoutItem *item;
    CGSize natural = CGSizeZero;
    CGFloat width = MIN(b->width, 360), height = IMAGE_SLOT_HEIGHT;
    BOOL known = [FPImageLoader knownSizeForURL:url size:&natural];
    if (known && natural.width <= INLINE_IMAGE_MAX && natural.height <= INLINE_IMAGE_MAX) {
        FPAppendInlineImage(b, url, natural, style);
        return;
    }
    if (known) {
        width = MIN(natural.width, b->width);
        height = natural.height * width / natural.width;
        if (height > IMAGE_MAX_HEIGHT) { width = width * IMAGE_MAX_HEIGHT / height; height = IMAGE_MAX_HEIGHT; }
        width = ceilf(width);
        height = ceilf(height);
    } else {
        [b->awaiting addObject:url];
    }
    FPFlush(b);
    item = FPAddItem(b, FPItemImage, CGRectMake(b->x, b->y, width, height));
    item->url = [url copy];
    item->title = [title copy];
    b->y += height + BLOCK_GAP;
}

static void FPAttachmentImage(FPBuilder *b, FPAttachment *a)
{
    CGFloat width = MIN(b->width, 360), height = IMAGE_SLOT_HEIGHT;
    FPLayoutItem *item;
    FPFlush(b);
    if (a.width > 0 && a.height > 0) {
        height = width * a.height / a.width;
        if (height > IMAGE_MAX_HEIGHT) { width = width * IMAGE_MAX_HEIGHT / height; height = IMAGE_MAX_HEIGHT; }
    }
    item = FPAddItem(b, FPItemImage, CGRectMake(b->x, b->y, ceilf(width), ceilf(height)));
    item->url = [a.url copy];
    item->title = [a.name copy];
    b->y += ceilf(height) + BLOCK_GAP;
}

static FPAttachment *FPFindAttachment(FPBuilder *b, NSString *argument)
{
    NSInteger identifier = [argument integerValue];
    FPAttachment *a;
    for (a in b->content->attachments) if (a.attachmentId == identifier) return a;
    return nil;
}

static void FPLayoutNodes(FPBuilder *b, NSArray *nodes, FPStyle style)
{
    FPBBNode *node;
    for (node in nodes) {
        FPStyle inner = style;
        if (!node->tag) {
            NSString *text = node->text;
            NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
            char *buffer = (char *)malloc([data length] + 1);
            if (buffer) {
                size_t written = fp_text_unescape_entities((const char *)[data bytes], [data length], buffer, [data length] + 1);
                FPAppend(b, FPUtf8(buffer, written, NO), &style);
                free(buffer);
            }
            continue;
        }
        switch (node->tag) {
        case FP_BB_B: inner.bold = YES; FPLayoutNodes(b, node->children, inner); break;
        case FP_BB_I: inner.italic = YES; FPLayoutNodes(b, node->children, inner); break;
        case FP_BB_U: inner.underline = YES; FPLayoutNodes(b, node->children, inner); break;
        case FP_BB_S: inner.strike = YES; FPLayoutNodes(b, node->children, inner); break;
        case FP_BB_OFFTOP: inner.dim = YES; inner.factor *= 0.9f; FPLayoutNodes(b, node->children, inner); break;
        case FP_BB_SUB:
        case FP_BB_SUP: inner.factor *= 0.8f; FPLayoutNodes(b, node->children, inner); break;
        case FP_BB_COLOR: {
            NSData *data = [node->argument dataUsingEncoding:NSUTF8StringEncoding];
            uint32_t rgb;
            if (fp_bb_color((const char *)[data bytes], [data length], &rgb)) inner.rgb = (int)rgb;
            FPLayoutNodes(b, node->children, inner);
            break;
        }
        case FP_BB_SIZE: {
            static const CGFloat factors[] = {0.7f, 0.85f, 1.0f, 1.2f, 1.45f, 1.8f, 2.3f};
            NSInteger level = [node->argument integerValue];
            if (level >= 1 && level <= 7) inner.factor = style.factor * factors[level - 1];
            FPLayoutNodes(b, node->children, inner);
            break;
        }
        case FP_BB_URL: {
            NSString *address = [node->argument length] ? node->argument : FPPlainText(node);
            address = FPPlainArgument([address stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
            NSURL *parsed = [NSURL URLWithString:address];
            NSString *extension = [[[parsed path] pathExtension] lowercaseString];
            NSString *label = [FPPlainText(node) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            BOOL image = [[parsed scheme] isEqualToString:@"https"] &&
                ([extension isEqualToString:@"jpg"] || [extension isEqualToString:@"jpeg"] ||
                 [extension isEqualToString:@"png"] || [extension isEqualToString:@"gif"]);
            if (image && [label isEqualToString:address] && [address length] < 2048) FPImage(b, address, nil, &style);
            else {
                if ([address length] && [address length] < 2048) inner.link = address;
                FPLayoutNodes(b, node->children, inner);
            }
            break;
        }
        case FP_BB_CENTER:
        case FP_BB_LEFT:
        case FP_BB_RIGHT:
            FPFlush(b);
            inner.align = node->tag == FP_BB_CENTER ? 1 : (node->tag == FP_BB_RIGHT ? 2 : 0);
            FPLayoutNodes(b, node->children, inner);
            FPFlush(b);
            break;
        case FP_BB_LIST:
            FPFlush(b);
            FPLayoutNodes(b, node->children, style);
            FPFlush(b);
            break;
        case FP_BB_ITEM: {
            NSMutableString *plain = [b->run mutableString];
            /* an item starts its own line; the break left by the previous item's text is reused */
            while ([plain length] && [plain characterAtIndex:[plain length] - 1] == '\n') [plain deleteCharactersInRange:NSMakeRange([plain length] - 1, 1)];
            if ([b->run length]) FPAppend(b, @"\n", &style);
            FPAppend(b, @"• ", &style);
            break;
        }
        case FP_BB_BREAK: FPAppend(b, @"\n", &style); break;
        case FP_BB_QUOTE: {
            NSData *data = [node->argument dataUsingEncoding:NSUTF8StringEncoding];
            size_t start = 0, length = 0;
            NSString *header = @"Цитата";
            if (fp_bb_attribute((const char *)[data bytes], [data length], "name", &start, &length) && length > 0) {
                header = [FPUtf8((const char *)[data bytes] + start, length, YES) stringByAppendingString:@":"];
            }
            FPBox(b, node, style, FPRolePrimary, header);
            break;
        }
        case FP_BB_MOD: FPBox(b, node, style, FPRoleLink, @"Модератор"); break;
        case FP_BB_EX: FPBox(b, node, style, FPRoleError, @"Важно"); break;
        case FP_BB_CUR: FPBox(b, node, style, FPRoleLink, @"Куратор"); break;
        case FP_BB_SPOILER: FPSpoiler(b, node, style, @"Спойлер"); break;
        case FP_BB_HIDE: FPSpoiler(b, node, style, @"Скрытый текст"); break;
        case FP_BB_CODE: {
            FPStyle code = style;
            CGFloat savedX = b->x, savedWidth = b->width, top;
            FPLayoutItem *fill;
            FPFlush(b);
            top = b->y;
            fill = FPAddItem(b, FPItemFill, CGRectZero);
            fill->color = FPRoleHighest;
            fill->radius = 12;
            code.mono = YES;
            code.rgb = -1;
            code.factor = 0.85f;
            b->x += BOX_PAD;
            b->width = MAX(60, b->width - 2 * BOX_PAD);
            b->y += BOX_PAD;
            FPAppend(b, FPPlainText(node), &code);
            FPFlush(b);
            b->x = savedX;
            b->width = savedWidth;
            fill->rect = CGRectMake(b->x, top, b->width, b->y - top + BOX_PAD - BLOCK_GAP);
            b->y = CGRectGetMaxY(fill->rect) + BLOCK_GAP;
            break;
        }
        case FP_BB_IMG: {
            NSString *url = [FPPlainText(node) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            url = FPPlainArgument(url);
            if ([url length] && [url length] < 2048) FPImage(b, url, nil, &style);
            break;
        }
        case FP_BB_ATTACHMENT: {
            NSString *argument = [node->argument length] ? node->argument : FPPlainText(node);
            FPAttachment *a = FPFindAttachment(b, argument);
            if (a && a.image && [a.url length]) {
                [b->used addObject:[NSNumber numberWithInteger:a.attachmentId]];
                FPAttachmentImage(b, a);
            }
            break;
        }
        case FP_BB_ROW:
            FPLayoutNodes(b, node->children, style);
            FPAppend(b, @"\n", &style);
            break;
        case FP_BB_CELL:
            if ([b->run length] && [[[b->run string] substringFromIndex:[b->run length] - 1] rangeOfString:@"\n"].location == NSNotFound) FPAppend(b, @"   ", &style);
            FPLayoutNodes(b, node->children, style);
            break;
        case FP_BB_TABLE:
            FPFlush(b);
            FPLayoutNodes(b, node->children, style);
            FPFlush(b);
            break;
        default:
            FPLayoutNodes(b, node->children, style);
            break;
        }
    }
}

static NSString *FPByteText(long long bytes)
{
    if (bytes >= 1024 * 1024) return [NSString stringWithFormat:@"%.1f МБ", bytes / (1024.0 * 1024.0)];
    if (bytes >= 1024) return [NSString stringWithFormat:@"%.0f КБ", bytes / 1024.0];
    return [NSString stringWithFormat:@"%lld Б", bytes];
}

@implementation FPPostLayout
@synthesize width = _width, height = _height;

+ (id)contentForPost:(FPPost *)post includeSignature:(BOOL)signature
{
    FPPostContent *content = [[[FPPostContent alloc] init] autorelease];
    content->body = [FPParseBody(post.body) retain];
    if (signature && [post.signature length]) content->signature = [FPParseBody(post.signature) retain];
    content->attachments = [post.attachments retain];
    if (post.editDate > 0) {
        NSString *who = [post.editor length] ? post.editor : @"модератор";
        NSString *line = [NSString stringWithFormat:@"Отредактировал %@ · %@", who, FPFormatDate(post.editDate)];
        content->footer = [([post.editReason length] ? [line stringByAppendingFormat:@"\nПричина: %@", post.editReason] : line) retain];
    }
    return content;
}

+ (FPPostLayout *)layoutContent:(id)contentObject width:(CGFloat)width spoilers:(NSIndexSet *)spoilers
{
    FPPostContent *content = contentObject;
    FPBuilder b;
    FPStyle style;
    FPPostLayout *layout = [[[FPPostLayout alloc] init] autorelease];
    FPAttachment *a;
    NSMutableArray *rest = [NSMutableArray array];
    memset(&b, 0, sizeof(b));
    b.items = [NSMutableArray array];
    b.run = [[[NSMutableAttributedString alloc] init] autorelease];
    b.content = content;
    b.spoilers = spoilers;
    b.used = [NSMutableSet set];
    b.awaiting = [NSMutableSet set];
    b.x = 0;
    b.width = MAX(width, 80);
    b.base = 15 * [FPSettings textScale];
    memset(&style, 0, sizeof(style));
    style.rgb = -1;
    style.factor = 1;
    FPLayoutNodes(&b, content->body->children, style);
    FPFlush(&b);
    if (content->signature) {
        FPStyle sig = style;
        FPLayoutItem *rule = FPAddItem(&b, FPItemFill, CGRectMake(0, b.y + 2, b.width, 1));
        rule->color = FPRoleDivider;
        b.y += 12;
        sig.dim = YES;
        sig.factor = 0.88f;
        FPLayoutNodes(&b, content->signature->children, sig);
        FPFlush(&b);
    }
    for (a in content->attachments) if (![b.used containsObject:[NSNumber numberWithInteger:a.attachmentId]]) [rest addObject:a];
    if ([rest count]) {
        CGFloat x = 0, rowTop = b.y;
        NSInteger columns = MAX(1, (NSInteger)floorf((b.width + THUMB_GAP) / (THUMB_SIZE + THUMB_GAP))), column = 0;
        b.y += 4;
        rowTop = b.y;
        for (a in rest) {
            if (a.image && [a.url length]) {
                FPLayoutItem *thumb = FPAddItem(&b, FPItemImage, CGRectMake(x, rowTop, THUMB_SIZE, THUMB_SIZE));
                thumb->url = [a.url copy];
                thumb->title = [a.name copy];
                thumb->thumbnail = YES;
                column++;
                x += THUMB_SIZE + THUMB_GAP;
                if (column == columns) { column = 0; x = 0; rowTop += THUMB_SIZE + THUMB_GAP; }
            }
        }
        if (column > 0) rowTop += THUMB_SIZE + THUMB_GAP;
        b.y = rowTop;
        for (a in rest) {
            if (!(a.image && [a.url length])) {
                FPLayoutItem *file = FPAddItem(&b, FPItemFile, CGRectMake(0, b.y, b.width, 36));
                file->title = [[NSString stringWithFormat:@"%@ · %@", a.name, FPByteText(a.size)] retain];
                file->fileName = [a.name copy];
                file->attachmentId = a.attachmentId;
                b.y += 36 + 4;
            }
        }
        b.y += 2;
    }
    if (content->footer) {
        FPStyle foot = style;
        foot.dim = YES;
        foot.factor = 0.8f;
        b.y += 4;
        FPAppend(&b, content->footer, &foot);
        FPFlush(&b);
    }
    layout->_items = [b.items retain];
    layout->_awaiting = [b.awaiting retain];
    layout->_width = b.width;
    layout->_height = ceilf(MAX(b.y - BLOCK_GAP, 0));
    return layout;
}

- (void)dealloc
{
    [_items release]; [_awaiting release];
    [super dealloc];
}

static void FPDrawStrikes(CTFrameRef frame, CGContextRef c)
{
    CFArrayRef lines = CTFrameGetLines(frame);
    CFIndex count = CFArrayGetCount(lines), i;
    CGPoint *origins;
    if (!count) return;
    origins = (CGPoint *)malloc(sizeof(CGPoint) * (size_t)count);
    if (!origins) return;
    CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), origins);
    for (i = 0; i < count; i++) {
        CFArrayRef runs = CTLineGetGlyphRuns((CTLineRef)CFArrayGetValueAtIndex(lines, i));
        CFIndex k, runCount = CFArrayGetCount(runs);
        for (k = 0; k < runCount; k++) {
            CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, k);
            NSDictionary *attributes = (NSDictionary *)CTRunGetAttributes(run);
            CGFloat ascent, descent, leading, width;
            CGPoint position;
            if (![attributes objectForKey:FPAttrStrike]) continue;
            width = (CGFloat)CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &ascent, &descent, &leading);
            CTRunGetPositions(run, CFRangeMake(0, 1), &position);
            CGContextSetStrokeColorWithColor(c, (CGColorRef)[attributes objectForKey:(id)kCTForegroundColorAttributeName]);
            CGContextSetLineWidth(c, 1);
            CGContextMoveToPoint(c, origins[i].x + position.x, origins[i].y + ascent * 0.3f);
            CGContextAddLineToPoint(c, origins[i].x + position.x + width, origins[i].y + ascent * 0.3f);
            CGContextStrokePath(c);
        }
    }
    free(origins);
}

- (BOOL)awaitsSizeOfURL:(NSString *)url
{
    return [_awaiting containsObject:url];
}

- (void)drawInRect:(CGRect)dirty
{
    CGContextRef c = UIGraphicsGetCurrentContext();
    FPLayoutItem *item;
    CGRect area = CGRectInset(dirty, -4, -4);
    for (item in _items) {
        if (!CGRectIntersectsRect(item->rect, area)) continue;
        switch (item->kind) {
        case FPItemFill:
        case FPItemBar: {
            CGFloat r = item->kind == FPItemBar ? 1.5f : item->radius;
            CGPathRef path = FPCreateRoundedRect(item->rect, r, r, r, r);
            CGContextAddPath(c, path);
            CGPathRelease(path);
            [FPColor(item->color) setFill];
            CGContextFillPath(c);
            break;
        }
        case FPItemText:
            CGContextSaveGState(c);
            CGContextTranslateCTM(c, item->rect.origin.x, item->rect.origin.y + item->rect.size.height);
            CGContextScaleCTM(c, 1, -1);
            CGContextSetTextMatrix(c, CGAffineTransformIdentity);
            CTFrameDraw(item->frame, c);
            FPDrawStrikes(item->frame, c);
            CGContextRestoreGState(c);
            for (FPInlineImage *icon in item->inlines) {
                UIImage *image = [FPImageLoader cachedImageForURL:icon->url size:icon->rect.size circle:NO];
                if (image) [image drawInRect:icon->rect];
            }
            break;
        case FPItemHeader: {
            CGPathRef path = FPCreateRoundedRect(item->rect, 20, 20, 20, 20);
            CGContextAddPath(c, path);
            CGPathRelease(path);
            [FPColor(FPRoleHighest) setFill];
            CGContextFillPath(c);
            FPDrawText(item->title, FPFont(14, 1, NO), FPColor(FPRoleOnSurface),
                       CGRectMake(item->rect.origin.x + 16, item->rect.origin.y + 10, item->rect.size.width - 56, 20), 1);
            [FPIcon(item->expanded ? FPIconChevronUp : FPIconChevronDown, 20, FPColor(FPRoleOnVariant))
                drawAtPoint:CGPointMake(CGRectGetMaxX(item->rect) - 32, item->rect.origin.y + 10)];
            break;
        }
        case FPItemImage: {
            UIImage *image = [FPImageLoader cachedImageForURL:item->url size:item->rect.size circle:NO];
            CGPathRef path = FPCreateRoundedRect(item->rect, 12, 12, 12, 12);
            CGContextAddPath(c, path);
            [FPColor(FPRoleHighest) setFill];
            CGContextFillPath(c);
            if (image) {
                CGSize s = image.size;
                CGRect target = CGRectMake(item->rect.origin.x + (item->rect.size.width - s.width) / 2,
                                           item->rect.origin.y + (item->rect.size.height - s.height) / 2, s.width, s.height);
                CGContextSaveGState(c);
                CGContextAddPath(c, path);
                CGContextClip(c);
                [image drawInRect:target];
                CGContextRestoreGState(c);
            } else {
                [FPIcon(FPIconFile, 24, FPColor(FPRoleOutline)) drawAtPoint:CGPointMake(CGRectGetMidX(item->rect) - 12, CGRectGetMidY(item->rect) - 12)];
            }
            CGPathRelease(path);
            break;
        }
        case FPItemFile: {
            CGPathRef path = FPCreateRoundedRect(item->rect, 18, 18, 18, 18);
            CGContextAddPath(c, path);
            CGPathRelease(path);
            [FPColor(FPRoleHighest) setFill];
            CGContextFillPath(c);
            [FPIcon(FPIconFile, 20, FPColor(FPRoleOnVariant)) drawAtPoint:CGPointMake(item->rect.origin.x + 12, item->rect.origin.y + 8)];
            FPDrawText(item->title, FPFont(13, 0, NO), FPColor(FPRoleOnSurface),
                       CGRectMake(item->rect.origin.x + 40, item->rect.origin.y + 8, item->rect.size.width - 52, 20), 1);
            break;
        }
        }
    }
}

- (FPPostHit *)hitTest:(CGPoint)point
{
    NSInteger index = (NSInteger)[_items count];
    while (index--) {
        FPLayoutItem *item = [_items objectAtIndex:(NSUInteger)index];
        FPPostHit *hit;
        CGRect area = CGRectInset(item->rect, -4, -4);
        if (!CGRectContainsPoint(area, point)) continue;
        if (item->kind == FPItemHeader) {
            hit = [[[FPPostHit alloc] init] autorelease];
            hit->kind = FPHitSpoiler;
            hit->spoiler = item->spoiler;
            return hit;
        }
        if (item->kind == FPItemImage && [item->url length]) {
            hit = [[[FPPostHit alloc] init] autorelease];
            hit->kind = FPHitImage;
            hit->link = [item->url copy];
            return hit;
        }
        if (item->kind == FPItemFile && item->attachmentId > 0) {
            hit = [[[FPPostHit alloc] init] autorelease];
            hit->kind = FPHitFile;
            hit->attachmentId = item->attachmentId;
            hit->fileName = [item->fileName copy];
            return hit;
        }
        if (item->kind == FPItemText) {
            CFArrayRef lines = CTFrameGetLines(item->frame);
            CFIndex count = CFArrayGetCount(lines), i, best = -1;
            CGPoint *origins;
            CGFloat local = item->rect.size.height - (point.y - item->rect.origin.y), distance = 1e9f;
            if (!count) continue;
            origins = (CGPoint *)malloc(sizeof(CGPoint) * (size_t)count);
            if (!origins) continue;
            CTFrameGetLineOrigins(item->frame, CFRangeMake(0, 0), origins);
            for (i = 0; i < count; i++) {
                CGFloat ascent, descent, leading, d;
                CTLineGetTypographicBounds((CTLineRef)CFArrayGetValueAtIndex(lines, i), &ascent, &descent, &leading);
                d = local > origins[i].y + ascent ? local - origins[i].y - ascent : (local < origins[i].y - descent ? origins[i].y - descent - local : 0);
                if (d < distance) { distance = d; best = i; }
            }
            if (best >= 0 && distance <= 6) {
                CFIndex at = CTLineGetStringIndexForPosition((CTLineRef)CFArrayGetValueAtIndex(lines, best),
                                                             CGPointMake(point.x - item->rect.origin.x - origins[best].x, 0));
                if (at >= 0 && (NSUInteger)at < [item->string length]) {
                    NSString *link = [item->string attribute:FPAttrLink atIndex:(NSUInteger)at effectiveRange:NULL];
                    if (link) {
                        hit = [[[FPPostHit alloc] init] autorelease];
                        hit->kind = FPHitLink;
                        hit->link = [link copy];
                        free(origins);
                        return hit;
                    }
                }
            }
            free(origins);
        }
    }
    return nil;
}

- (void)enumerateImages:(void (^)(NSString *url, CGSize size, BOOL thumbnail))block
{
    FPLayoutItem *item;
    for (item in _items) {
        FPInlineImage *icon;
        if (item->kind == FPItemImage && [item->url length]) block(item->url, item->rect.size, item->thumbnail);
        for (icon in item->inlines) block(icon->url, icon->rect.size, NO);
    }
}

@end
