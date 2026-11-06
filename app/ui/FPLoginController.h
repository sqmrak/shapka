#import "FPScreenController.h"

/* a labeled check box: a rounded square that fills with the primary color and shows a check when it is on */
@interface FPCheckRow : UIControl {
    UIImageView *_box;
    UILabel *_label;
    BOOL _on;
}
@property (nonatomic, assign) BOOL on;
@property (nonatomic, readonly) UILabel *label;
- (void)applyTheme;
@end

@interface FPLoginController : FPScreenController <UITextFieldDelegate> {
    UIScrollView *_scroll;
    UILabel *_heading;
    UILabel *_note;
    UIView *_accountCard;
    UIImageView *_accountAvatar;
    UILabel *_accountName;
    UILabel *_accountDetail;
    NSString *_avatarURL;
    UITextField *_login;
    UITextField *_password;
    FPCheckRow *_remember;
    FPCheckRow *_hiddenLogin;
    UIImageView *_captchaImage;
    UITextField *_captchaField;
    FPCheckRow *_cannotAnswer;
    NSString *_captchaURL;
    NSUInteger _captchaSerial;
    FPPillButton *_submit;
    UILabel *_status;
    UIActivityIndicatorView *_spinner;
    NSInteger _memberId;
    BOOL _busy;
    BOOL _statusIsError;
    CGFloat _keyboardHeight;
}
@end
