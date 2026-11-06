#import <UIKit/UIKit.h>
#import "FPTheme.h"

/* the raised button face used by classic bars and controls */
void FPClassicButtonFace(UIButton *button, BOOL onBar);

/* a button with a tonal pill face: primary container fill by default, outlined when quiet */
@interface FPPillButton : UIButton {
    BOOL _quiet;
}
@property (nonatomic, assign) BOOL quiet;
- (void)applyTheme;
@end

/* the top bar: back button, a title with an optional subtitle and round icon actions on the right */
@interface FPAppBar : UIView {
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    UIButton *_backButton;
    NSMutableArray *_actions;
    CGFloat _topInset;
    UIEdgeInsets _sideInsets;
    BOOL _elevated;
}
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, assign) CGFloat topInset;
@property (nonatomic, assign) UIEdgeInsets sideInsets;
@property (nonatomic, readonly) UIButton *backButton;
+ (CGFloat)contentHeight;
- (UIButton *)addActionWithIcon:(FPIconKind)kind target:(id)target action:(SEL)action;
- (void)setBackVisible:(BOOL)visible;
- (void)setElevated:(BOOL)elevated;
- (void)applyTheme;
@end

/* the empty, loading and failed face of a screen that has no content yet */
@interface FPStateView : UIView {
    UIActivityIndicatorView *_spinner;
    UILabel *_message;
    FPPillButton *_retry;
}
@property (nonatomic, readonly) FPPillButton *retryButton;
- (void)showLoading;
- (void)showMessage:(NSString *)message retry:(BOOL)retry;
- (void)applyTheme;
@end

typedef void (^FPDialogHandler)(NSString *text);

/* a rounded card over a scrim; the text field is optional */
@interface FPDialog : UIView <UITextFieldDelegate> {
    UIView *_card;
    UILabel *_titleLabel;
    UILabel *_messageLabel;
    UITextField *_field;
    FPPillButton *_confirm;
    FPPillButton *_cancel;
    FPDialogHandler _handler;
}
+ (FPDialog *)presentInView:(UIView *)host title:(NSString *)title message:(NSString *)message
                fieldText:(NSString *)fieldText numeric:(BOOL)numeric confirm:(NSString *)confirm handler:(FPDialogHandler)handler;
- (void)dismiss;
@end
