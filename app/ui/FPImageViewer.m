#import "FPImageViewer.h"
#import "FPImageLoader.h"
#import "FPTheme.h"
#import "FPChrome.h"

@implementation FPImageViewer
- (id)initWithURL:(NSString *)url
{
    self = [super init];
    if (self) _url = [url copy];
    return self;
}

- (void)dealloc
{
    [FPImageLoader cancelOwner:self];
    [_url release]; [_scroll release]; [_image release]; [_status release];
    [super dealloc];
}

- (void)loadView
{
    UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    view.backgroundColor = [UIColor blackColor];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.view = view;
    [view release];
    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.delegate = self;
    _scroll.minimumZoomScale = 1;
    _scroll.maximumZoomScale = 4;
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:_scroll];
    _image = [[UIImageView alloc] initWithFrame:_scroll.bounds];
    _image.contentMode = UIViewContentModeScaleAspectFit;
    [_scroll addSubview:_image];
    _status = [[UILabel alloc] initWithFrame:CGRectZero];
    _status.backgroundColor = [UIColor clearColor];
    _status.textColor = [UIColor whiteColor];
    _status.textAlignment = NSTextAlignmentCenter;
    _status.text = @"Загрузка изображения…";
    [self.view addSubview:_status];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeCustom];
    close.frame = CGRectMake(12, 24, 52, 44);
    close.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    [close setImage:FPIcon(FPIconClose, 24, [UIColor whiteColor]) forState:UIControlStateNormal];
    FPClassicButtonFace(close, YES);
    close.accessibilityLabel = @"Закрыть";
    [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [_scroll addGestureRecognizer:doubleTap];
    [doubleTap release];
    CGFloat side = MIN(1024.0f, 2048.0f / [[UIScreen mainScreen] scale]);
    [FPImageLoader loadURL:_url size:CGSizeMake(side, side) circle:NO owner:self completion:^(UIImage *image) {
        _image.image = image;
        _status.text = image ? @"" : @"Не удалось загрузить изображение";
    }];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    if (_scroll.zoomScale <= 1.001f) {
        _image.frame = _scroll.bounds;
        _scroll.contentSize = _scroll.bounds.size;
    }
    _status.frame = CGRectMake(12, (self.view.bounds.size.height - 44) / 2, self.view.bounds.size.width - 24, 44);
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scroll
{
    (void)scroll;
    return _image;
}

- (void)doubleTap:(UITapGestureRecognizer *)gesture
{
    if (_scroll.zoomScale > 1.001f) [_scroll setZoomScale:1 animated:YES];
    else {
        CGPoint point = [gesture locationInView:_image];
        CGSize size = _scroll.bounds.size;
        [_scroll zoomToRect:CGRectMake(point.x - size.width / 5, point.y - size.height / 5, size.width / 2.5f, size.height / 2.5f) animated:YES];
    }
}

- (void)close
{
    [FPImageLoader cancelOwner:self];
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end
