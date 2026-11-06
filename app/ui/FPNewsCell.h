#import <UIKit/UIKit.h>
@interface FPNewsCell : UITableViewCell {
    UIImageView *_preview;
    UILabel *_headline;
    UILabel *_previewStatus;
    UIView *_card;
    id _job;
    NSString *_url;
    CGFloat _inset;
}
- (void)configure:(NSDictionary *)item inset:(CGFloat)inset;
@end

/* the picture of the article at a url on 4pda.to, found in the head of its page and decoded no larger than maxPixel on a side. nil on a failure, with the
   reason in failure; cancelled is asked between the two downloads. Runs on the calling thread, which must not be the main one */
UIImage *FPNewsLoadImage(NSString *articleURL, int maxPixel, NSString **failure, BOOL (^cancelled)(void));

/* the same for a picture at a known address on 4pda.to */
UIImage *FPNewsLoadImageAtURL(NSString *imageURL, int maxPixel, NSString **failure, BOOL (^cancelled)(void));
