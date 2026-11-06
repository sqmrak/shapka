#import "FPAnnouncementController.h"
#import "FPImageViewer.h"
#import "FPImageLoader.h"

@implementation FPAnnouncementController
- (id)initWithApi:(FPApi *)api identifier:(NSInteger)identifier title:(NSString *)title
{
    self = [super initWithApi:api];
    if (self) { _identifier = identifier; _heading = [title copy]; _spoilers = [[NSMutableIndexSet alloc] init]; }
    return self;
}
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _bodyView.target = nil;
    [_heading release]; [_scroll release]; [_bodyView release]; [_content release]; [_layout release]; [_spoilers release];
    [super dealloc];
}
- (void)loadView
{
    [super loadView];
    self.appBar.title = _heading;
    [self.appBar addActionWithIcon:FPIconRefresh target:self action:@selector(reloadFromUser)].accessibilityLabel = @"Обновить";
    _scroll = [[UIScrollView alloc] init];
    [self.contentView insertSubview:_scroll belowSubview:self.stateView];
    _bodyView = [[FPPostBodyView alloc] init];
    _bodyView.target = self;
    [_scroll addSubview:_bodyView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(imageSizeKnown:) name:FPImageSizeKnownNotification object:nil];
    [self.stateView showLoading];
    [self reloadFromUser];
}
- (void)reloadFromUser
{
    NSUInteger serial = ++_serial;
    [_api loadAnnouncement:_identifier completion:^(id result, NSError *error) {
        if (serial != _serial) return;
        if (error) {
            if (_content) [self showToast:[error localizedDescription]];
            else [self.stateView showMessage:[error localizedDescription] retry:YES];
            return;
        }
        FPPost *post = [[FPPost alloc] init];
        post.body = [result objectForKey:@"body"];
        id content = [FPPostLayout contentForPost:post includeSignature:NO];
        [_content release]; _content = [content retain];
        [post release];
        NSString *title = [result objectForKey:@"title"];
        if ([title length]) self.appBar.title = title;
        [_spoilers removeAllIndexes];
        self.stateView.hidden = YES;
        _layoutWidth = 0;
        [self.view setNeedsLayout];
    }];
}
- (void)imageSizeKnown:(NSNotification *)note
{
    if ([_layout awaitsSizeOfURL:[note object]]) { _layoutWidth = 0; [self.view setNeedsLayout]; }
}
- (void)themeDidChange { _layoutWidth = 0; [self.view setNeedsLayout]; }
- (void)layoutContent
{
    UIEdgeInsets safe = FPSafeInsets(self.view);
    CGRect bounds = self.contentView.bounds;
    CGFloat inset = MAX(16, MAX(safe.left, safe.right) + 12);
    CGFloat width = MIN(620, MAX(1, bounds.size.width - 2 * inset));
    _scroll.frame = bounds;
    if (_content && (!_layout || fabsf((float)(_layoutWidth - width)) > 0.5f)) {
        FPPostLayout *next = [FPPostLayout layoutContent:_content width:width spoilers:_spoilers];
        [_layout release]; _layout = [next retain]; _layoutWidth = width;
        [_bodyView setLayout:_layout];
    }
    _bodyView.frame = CGRectMake((bounds.size.width - width) / 2, 16, width, _layout.height);
    _scroll.contentSize = CGSizeMake(bounds.size.width, _layout.height + safe.bottom + 32);
}
- (void)bodyHit:(FPPostHit *)hit
{
    if (hit->kind == FPHitLink) [self openLink:hit->link];
    else if (hit->kind == FPHitImage) {
        FPImageViewer *viewer = [[FPImageViewer alloc] initWithURL:hit->link];
        [self presentViewController:viewer animated:YES completion:nil];
        [viewer release];
    } else if (hit->kind == FPHitSpoiler) {
        NSUInteger index = (NSUInteger)hit->spoiler;
        if ([_spoilers containsIndex:index]) [_spoilers removeIndex:index]; else [_spoilers addIndex:index];
        _layoutWidth = 0; [self.view setNeedsLayout];
    }
}
@end
