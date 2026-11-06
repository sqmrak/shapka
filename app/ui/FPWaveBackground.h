#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface FPWaveBackground : UIView {
    CAGradientLayer *_wave;
    CAShapeLayer *_shape;
}
- (void)applyTheme;
@end
