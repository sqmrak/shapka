#import "FPLoginController.h"
#import <QuartzCore/QuartzCore.h>
#import "FPAccountStore.h"
#import "FPImageLoader.h"
#include "fp_news_http.h"
#include <stdlib.h>

@implementation FPCheckRow
@synthesize on = _on;
@synthesize label = _label;
- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _box = [[UIImageView alloc] init];
        _box.layer.cornerRadius = 7;
        _box.layer.borderWidth = 2;
        _box.contentMode = UIViewContentModeCenter;
        _box.userInteractionEnabled = NO;
        [self addSubview:_box];
        _label = [[UILabel alloc] init];
        _label.backgroundColor = [UIColor clearColor];
        _label.userInteractionEnabled = NO;
        [self addSubview:_label];
        [self addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}
- (void)dealloc { [_box release]; [_label release]; [super dealloc]; }
- (void)toggle { self.on = !_on; [self sendActionsForControlEvents:UIControlEventValueChanged]; }
- (void)setOn:(BOOL)on
{
    if (_on == on) return;
    _on = on;
    [self applyTheme];
    if (self.window && !FPReduceMotionEnabled()) {
        _box.transform = CGAffineTransformMakeScale(0.82f, 0.82f);
        FPAnimate(0.28, ^{ _box.transform = CGAffineTransformIdentity; }, nil);
    }
}
- (void)applyTheme
{
    _label.font = FPFont(15, 0, NO);
    _label.textColor = FPColor(FPRoleOnSurface);
    _box.layer.cornerRadius = FPThemeIsClassic() ? 3 : 7;
    _box.layer.borderWidth = FPThemeIsClassic() ? 1 : 2;
    _box.backgroundColor = _on ? FPColor(FPRolePrimary) : [UIColor clearColor];
    _box.layer.borderColor = (_on ? FPColor(FPRolePrimary) : FPColor(FPRoleOnVariant)).CGColor;
    _box.image = _on ? FPIcon(FPIconCheck, 18, FPColor(FPRoleOnPrimary)) : nil;
    self.accessibilityLabel = _label.text;
    self.accessibilityValue = _on ? @"включено" : @"выключено";
}
- (CGSize)sizeThatFits:(CGSize)size { (void)size; return CGSizeMake(34 + ceil(FPTextSize(_label.text, FPFont(15, 0, NO), 0).width), 44); }
- (void)layoutSubviews
{
    [super layoutSubviews];
    _box.frame = CGRectMake(0, (self.bounds.size.height - 24) / 2, 24, 24);
    _label.frame = CGRectMake(34, 0, MAX(0, self.bounds.size.width - 34), self.bounds.size.height);
}
@end

@implementation FPLoginController

- (id)initWithApi:(FPApi *)api
{
    self = [super initWithApi:api];
    if (self) {
        self.title = @"Аккаунт";
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [FPImageLoader cancelOwner:self];
    [_accountCard release]; [_accountAvatar release]; [_accountName release]; [_accountDetail release]; [_avatarURL release];
    _login.delegate = nil;
    _password.delegate = nil;
    ++_captchaSerial;
    _captchaField.delegate = nil;
    [_scroll release]; [_heading release]; [_note release]; [_login release]; [_password release];
    [_remember release]; [_hiddenLogin release]; [_captchaImage release]; [_captchaField release]; [_cannotAnswer release]; [_captchaURL release];
    [_submit release]; [_status release]; [_spinner release];
    [super dealloc];
}

- (UITextField *)makeField:(NSString *)placeholder secure:(BOOL)secure
{
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    field.secureTextEntry = secure;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.returnKeyType = secure ? UIReturnKeyGo : UIReturnKeyNext;
    field.delegate = self;
    field.layer.cornerRadius = 28;
    field.leftView = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 56)] autorelease];
    field.leftViewMode = UITextFieldViewModeAlways;
    [_scroll addSubview:field];
    return [field autorelease];
}

- (FPCheckRow *)makeCheck:(NSString *)title
{
    FPCheckRow *row = [[FPCheckRow alloc] init];
    row.label.text = title;
    [_scroll addSubview:row];
    return [row autorelease];
}

- (UILabel *)makeLabel
{
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.numberOfLines = 0;
    [_scroll addSubview:label];
    return [label autorelease];
}

- (void)loadView
{
    [super loadView];
    self.appBar.title = @"Аккаунт";
    _scroll = [[UIScrollView alloc] init];
    _scroll.alwaysBounceVertical = YES;
    [self.contentView insertSubview:_scroll belowSubview:self.stateView];
    _accountCard = [[UIView alloc] init];
    _accountCard.layer.cornerRadius = 24;
    [_scroll addSubview:_accountCard];
    _accountAvatar = [[UIImageView alloc] init];
    _accountAvatar.layer.cornerRadius = 32;
    _accountAvatar.clipsToBounds = YES;
    _accountAvatar.contentMode = UIViewContentModeScaleAspectFill;
    [_accountCard addSubview:_accountAvatar];
    _accountName = [[UILabel alloc] init];
    _accountName.backgroundColor = [UIColor clearColor];
    [_accountCard addSubview:_accountName];
    _accountDetail = [[UILabel alloc] init];
    _accountDetail.backgroundColor = [UIColor clearColor];
    [_accountCard addSubview:_accountDetail];
    _heading = [[self makeLabel] retain];
    _note = [[self makeLabel] retain];
    _status = [[self makeLabel] retain];
    _login = [[self makeField:@"Логин" secure:NO] retain];
    _password = [[self makeField:@"Пароль" secure:YES] retain];
    _remember = [[self makeCheck:@"Запомнить"] retain];
    _remember.on = YES;
    _hiddenLogin = [[self makeCheck:@"Скрытый вход"] retain];
    _captchaImage = [[UIImageView alloc] init];
    _captchaImage.contentMode = UIViewContentModeScaleAspectFit;
    _captchaImage.layer.cornerRadius = 20;
    _captchaImage.clipsToBounds = YES;
    _captchaImage.hidden = YES;
    [_scroll addSubview:_captchaImage];
    _captchaField = [[self makeField:@"введите число цифрами" secure:NO] retain];
    _captchaField.keyboardType = UIKeyboardTypeNumberPad;
    _captchaField.textAlignment = NSTextAlignmentCenter;
    _captchaField.hidden = YES;
    _cannotAnswer = [[self makeCheck:@"Я не могу ввести ответ"] retain];
    [_cannotAnswer addTarget:self action:@selector(cannotAnswerChanged) forControlEvents:UIControlEventValueChanged];
    _cannotAnswer.hidden = YES;
    _submit = [[FPPillButton buttonWithType:UIButtonTypeCustom] retain];
    [_submit addTarget:self action:@selector(submit) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_submit];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spinner.hidesWhenStopped = YES;
    [_scroll addSubview:_spinner];
    [self refreshState];
}

- (void)themeDidChange
{
    [self refreshState];
}

- (void)refreshState
{
    BOOL signedIn;
    _memberId = [self.api memberId];
    signedIn = _memberId > 0;
    _heading.font = FPFont(22, 2, YES);
    _heading.textColor = FPColor(FPRoleOnSurface);
    _heading.text = signedIn ? @"Вы вошли" : @"Вход в 4PDA";
    _note.font = FPFont(14, 0, YES);
    _note.textColor = FPColor(FPRoleOnVariant);
    _note.text = signedIn
        ? [NSString stringWithFormat:@"Номер участника: %ld. Ключ входа хранится в связке ключей устройства, пароль не сохраняется.", (long)_memberId]
        : @"Пароль отправляется только по проверенному защищённому соединению и не сохраняется на устройстве.";
    _accountCard.hidden = !signedIn;
    _accountCard.backgroundColor = FPColor(FPRolePrimaryContainer);
    _accountAvatar.backgroundColor = FPColor(FPRoleHighest);
    _accountName.font = FPFont(19, 2, YES);
    _accountName.textColor = FPColor(FPRoleOnPrimaryContainer);
    _accountDetail.font = FPFont(13, 0, YES);
    _accountDetail.textColor = FPColor(FPRoleOnVariant);
    NSDictionary *profile = [FPAccountStore profileForMember:_memberId];
    NSString *name = [profile objectForKey:@"name"];
    NSString *avatar = [profile objectForKey:@"avatar"];
    _accountName.text = [name isKindOfClass:[NSString class]] && [name length] ? name : @"Участник 4PDA";
    _accountDetail.text = [NSString stringWithFormat:@"ID %ld", (long)_memberId];
    UIImage *placeholder = FPIcon(FPIconPerson, 32, FPColor(FPRolePrimary));
    _accountAvatar.image = placeholder;
    [FPImageLoader cancelOwner:self];
    [_avatarURL release]; _avatarURL = nil;
    if (signedIn && [avatar isKindOfClass:[NSString class]] && [avatar length]) {
        _avatarURL = [avatar copy];
        NSInteger member = _memberId;
        [FPImageLoader loadURL:avatar size:CGSizeMake(64, 64) circle:YES owner:self completion:^(UIImage *image) {
            if (image && _memberId == member) _accountAvatar.image = image;
        }];
    }
    BOOL asked = _captchaURL != nil;
    for (FPCheckRow *row in [NSArray arrayWithObjects:_remember, _hiddenLogin, nil]) { row.hidden = signedIn; [row applyTheme]; }
    _captchaImage.hidden = signedIn || !asked;
    _captchaImage.backgroundColor = [UIColor whiteColor];
    _cannotAnswer.hidden = signedIn || !asked;
    [_cannotAnswer applyTheme];
    for (UITextField *field in [NSArray arrayWithObjects:_login, _password, _captchaField, nil]) {
        field.hidden = signedIn || (field == _captchaField && !asked);
        field.font = FPFont(17, 0, NO);
        field.textColor = FPColor(FPRoleOnSurface);
        field.backgroundColor = FPColor(FPRoleContainer);
        field.keyboardAppearance = FPThemeIsDark() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    }
    [_submit setTitle:signedIn ? @"Выйти" : @"Войти" forState:UIControlStateNormal];
    [_submit applyTheme];
    _status.font = FPFont(14, 1, NO);
    _status.textColor = _statusIsError ? FPColor(FPRoleError) : FPColor(FPRoleOnVariant);
    _spinner.activityIndicatorViewStyle = FPThemeIsDark() ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray;
    [self.view setNeedsLayout];
}

- (void)layoutContent
{
    UIEdgeInsets safe = FPSafeInsets(self.view);
    CGRect bounds = self.contentView.bounds;
    CGFloat width = MIN(bounds.size.width - 2 * MAX(24, MAX(safe.left, safe.right) + 12), 420), x = (bounds.size.width - width) / 2, y = 28;
    CGSize size;
    BOOL signedIn = _memberId > 0;
    _scroll.frame = bounds;
    size = FPTextSize(_heading.text, _heading.font, width);
    _heading.frame = CGRectMake(x, y, width, size.height);
    y += size.height + 10;
    size = FPTextSize(_note.text, _note.font, width);
    _note.frame = CGRectMake(x, y, width, size.height);
    y += size.height + 24;
    if (signedIn) {
        _accountCard.frame = CGRectMake(x, y, width, 96);
        _accountAvatar.frame = CGRectMake(16, 16, 64, 64);
        _accountName.frame = CGRectMake(96, 20, MAX(0, width - 112), 28);
        _accountDetail.frame = CGRectMake(96, 49, MAX(0, width - 112), 23);
        y += 112;
    }
    if (!signedIn) {
        _login.frame = CGRectMake(x, y, width, 56);
        y += 56 + 12;
        _password.frame = CGRectMake(x, y, width, 56);
        y += 56 + 8;
        {
            CGFloat half = floor((width - 12) / 2);
            _remember.frame = CGRectMake(x, y, half, 44);
            _hiddenLogin.frame = CGRectMake(x + half + 12, y, width - half - 12, 44);
            y += 44 + 12;
        }
        if (_captchaURL) {
            _captchaImage.frame = CGRectMake(x, y, width, MIN(width * 100 / 240, 140));
            y += _captchaImage.frame.size.height + 12;
            _captchaField.frame = CGRectMake(x, y, width, 56);
            y += 56 + 8;
            _cannotAnswer.frame = CGRectMake(x, y, width, 44);
            y += 44 + 12;
        }
        y += 8;
    }
    {
        CGSize pill = [_submit sizeThatFits:CGSizeZero];
        _submit.frame = CGRectMake(x, y, MAX(pill.width, 140), 48);
        _submit.layer.cornerRadius = FPThemeIsClassic() ? 6 : 24;
        _spinner.frame = CGRectMake(CGRectGetMaxX(_submit.frame) + 16, y + 6, 37, 37);
        y += 48 + 16;
    }
    size = FPTextSize(_status.text, _status.font, width);
    _status.frame = CGRectMake(x, y, width, size.height);
    y += size.height + 24;
    _scroll.contentSize = CGSizeMake(bounds.size.width, y);
    _scroll.contentInset = UIEdgeInsetsMake(0, 0, MAX(_keyboardHeight, safe.bottom), 0);
}

- (void)setStatus:(NSString *)text error:(BOOL)error
{
    _statusIsError = error;
    _status.text = text;
    _status.textColor = error ? FPColor(FPRoleError) : FPColor(FPRoleOnVariant);
    [self.view setNeedsLayout];
}

- (void)setBusy:(BOOL)busy
{
    _busy = busy;
    _submit.enabled = !busy;
    _login.enabled = !busy;
    _password.enabled = !busy;
    _captchaField.enabled = !busy;
    _remember.enabled = !busy;
    _hiddenLogin.enabled = !busy;
    _cannotAnswer.enabled = !busy;
    if (busy) [_spinner startAnimating];
    else [_spinner stopAnimating];
}

- (void)submit
{
    if (_busy) return;
    [self.view endEditing:YES];
    if (_memberId > 0) {
        [self setBusy:YES];
        [self setStatus:@"Выход…" error:NO];
        [self.api logout:^(NSError *error) {
            [self setBusy:NO];
            [self refreshState];
            if (error) [self setStatus:[error localizedDescription] error:YES];
            else [self setStatus:@"Вы вышли из аккаунта" error:NO];
        }];
        return;
    }
    if (![_login.text length] || ![_password.text length]) {
        [self setStatus:@"Введите логин и пароль" error:YES];
        return;
    }
    NSInteger captcha = 0;
    if (_captchaURL) {
        NSString *answer = [_captchaField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        long long value = [answer length] && [answer length] <= 9 ? [answer longLongValue] : 0;
        BOOL digits = [answer length] > 0 && [answer length] <= 9;
        for (NSUInteger i = 0; i < [answer length]; i++) { unichar c = [answer characterAtIndex:i]; if (c < '0' || c > '9') digits = NO; }
        if (!digits || value <= 0) { [self setStatus:@"Введите число с картинки цифрами" error:YES]; return; }
        captcha = (NSInteger)value;
    }
    [self setBusy:YES];
    [self setStatus:@"Вход…" error:NO];
    [self.api loginWithName:_login.text password:_password.text hidden:_hiddenLogin.on captcha:captcha remember:_remember.on
                 completion:^(NSError *error, NSString *captchaURL) {
        [self setBusy:NO];
        if (captchaURL) {
            [self showCaptcha:captchaURL];
            [self setStatus:[error localizedDescription] error:YES];
            return;
        }
        if (error) {
            [self setStatus:[error localizedDescription] error:YES];
            return;
        }
        _password.text = @"";
        _login.text = @"";
        _captchaField.text = @"";
        [self hideCaptcha];
        [self setStatus:nil error:NO];
        [self refreshState];
        [self showToast:_remember.on && ![FPAccountStore isPersisted] ? @"Вход выполнен, но ключ не сохранился: после закрытия приложения войдите снова" : @"Вход выполнен"];
    }];
}

/* the picture comes from the forum's own file server over verified tls, and a later answer or a newer picture drops an older download */
- (void)showCaptcha:(NSString *)url
{
    NSUInteger serial = ++_captchaSerial;
    NSString *roots = [[[NSBundle mainBundle] pathForResource:@"roots" ofType:@"pem"] copy];
    NSString *path = [url substringFromIndex:[@"https://4pda.to" length]];
    [_captchaURL release]; _captchaURL = [url copy];
    _captchaField.text = @"";
    _captchaImage.image = nil;
    [self refreshState];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        uint8_t *body = NULL; size_t length = 0; int http = 0;
        fp_session_status status = fp_news_get([roots fileSystemRepresentation], [path UTF8String], 64u * 1024u, &body, &length, &http);
        UIImage *image = nil;
        if (status == FP_SESSION_OK && http == 200 && length > 6 && memcmp(body, "GIF8", 4) == 0) image = [[UIImage imageWithData:[NSData dataWithBytes:body length:length]] retain];
        free(body); [roots release];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (serial == _captchaSerial) {
                if (image) _captchaImage.image = image;
                else [self setStatus:@"Не удалось загрузить картинку капчи, нажмите ниже, чтобы получить другую" error:YES];
            }
            [image release];
        });
        [pool drain];
    });
}

- (void)hideCaptcha
{
    ++_captchaSerial;
    [_captchaURL release]; _captchaURL = nil;
    _cannotAnswer.on = NO;
}

/* the server has no separate answer for someone who cannot read the picture, so this asks it for another one */
- (void)cannotAnswerChanged
{
    NSUInteger serial = ++_captchaSerial;
    [self setStatus:@"Загружаю другую картинку…" error:NO];
    [self.api loadCaptcha:^(NSString *url, NSError *error) {
        if (serial != _captchaSerial) return;
        _cannotAnswer.on = NO;
        if (error) { [self setStatus:[error localizedDescription] error:YES]; return; }
        [self showCaptcha:url];
        [self setStatus:@"Введите число с картинки" error:NO];
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field
{
    if (field == _login) [_password becomeFirstResponder];
    else if (field == _password && _captchaURL) [_captchaField becomeFirstResponder];
    else [self submit];
    return NO;
}

- (void)keyboardChanged:(NSNotification *)notification
{
    CGRect frame = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    BOOL show = [[notification name] isEqualToString:UIKeyboardWillShowNotification];
    if (![self isViewLoaded] || !self.view.window) return;
    frame = [self.view convertRect:frame fromView:nil];
    _keyboardHeight = show ? MAX(0, CGRectGetMaxY(self.contentView.frame) - frame.origin.y) : 0;
    [self.view setNeedsLayout];
    if (show && _password.isFirstResponder) {
        [_scroll scrollRectToVisible:CGRectInset(_submit.frame, 0, -24) animated:YES];
    }
}

@end
