#import <UIKit/UIKit.h>
#import "FPPostLayout.h"
#import "FPModels.h"

@class FPPostCell;

@protocol FPPostCellDelegate <NSObject>
- (void)postCell:(FPPostCell *)cell didHit:(FPPostHit *)hit;
@end

/* draws a layout in tiles, so a message taller than the screen never needs one huge bitmap */
@interface FPPostBodyView : UIView {
    FPPostLayout *_layout;
    id _target;
    CGPoint _touchStart;
}
@property (nonatomic, assign) id target;
- (void)setLayout:(FPPostLayout *)layout;
- (FPPostLayout *)layout;
@end

@interface FPPostCell : UITableViewCell {
    UIView *_card;
    UIView *_header;
    FPPostBodyView *_body;
    id<FPPostCellDelegate> _delegate;
}
@property (nonatomic, assign) id<FPPostCellDelegate> delegate;
+ (CGFloat)heightForLayout:(FPPostLayout *)layout;
+ (CGFloat)bodyWidthForWidth:(CGFloat)width sideInset:(CGFloat)sideInset;
- (void)configureWithPost:(FPPost *)post layout:(FPPostLayout *)layout width:(CGFloat)width sideInset:(CGFloat)sideInset;
@end
