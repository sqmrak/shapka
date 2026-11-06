#import <UIKit/UIKit.h>

@interface FPImageViewer : UIViewController <UIScrollViewDelegate> {
    NSString *_url;
    UIScrollView *_scroll;
    UIImageView *_image;
    UILabel *_status;
}
- (id)initWithURL:(NSString *)url;
@end
