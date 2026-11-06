#import "FPComposeController.h"
#import <QuartzCore/QuartzCore.h>

@implementation FPComposeController
- (id)initWithApi:(FPApi *)api topicId:(NSInteger)topicId sent:(void (^)(void))sent
{
    self = [super initWithApi:api];
    if (self) { _topicId = topicId; _sent = [sent copy]; }
    return self;
}
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _editor.delegate = nil;
    [_draftKey release]; [_initialQuote release];
    [_editor release];
    [_subject release]; [_recipient release];
    [_sent release];
    [super dealloc];
}
- (id)initWithApi:(FPApi *)api memberId:(NSInteger)memberId name:(NSString *)name
{
    self = [super initWithApi:api];
    if (self) { _memberId = memberId; _recipient = [name copy]; }
    return self;
}
- (id)initWithApi:(FPApi *)api dialogId:(NSInteger)dialogId sent:(void (^)(void))sent
{
    self = [super initWithApi:api];
    if (self) { _dialogId = dialogId; _sent = [sent copy]; }
    return self;
}
- (void)loadView
{
    [super loadView];
    self.appBar.title = _memberId > 0 ? _recipient : (_dialogId > 0 ? @"Ответ в диалоге" : @"Ответ в теме");
    [self.appBar addActionWithIcon:FPIconClose target:self action:@selector(close)].accessibilityLabel = @"Закрыть";
    _sendButton = [self.appBar addActionWithIcon:FPIconCheck target:self action:@selector(send)];
    _sendButton.accessibilityLabel = @"Отправить";
    NSInteger account = [_api memberId];
    NSString *kind = _topicId > 0 ? @"topic" : (_dialogId > 0 ? @"dialog" : @"member");
    NSInteger destination = _topicId > 0 ? _topicId : (_dialogId > 0 ? _dialogId : _memberId);
    _draftKey = [[NSString alloc] initWithFormat:@"compose.%ld.%@.%ld", (long)account, kind, (long)destination];
    NSDictionary *draft = [[NSUserDefaults standardUserDefaults] dictionaryForKey:_draftKey];
    _editor = [[UITextView alloc] initWithFrame:CGRectZero];
    _editor.delegate = self;
    id savedText = [draft objectForKey:@"text"];
    if ([savedText isKindOfClass:[NSString class]]) _editor.text = savedText;
    if ([_initialQuote length]) {
        _editor.text = [_editor.text length] ? [NSString stringWithFormat:@"%@\n\n%@", _editor.text, _initialQuote] : _initialQuote;
    }
    _editor.font = FPFont(16, 0, YES);
    _editor.layer.cornerRadius = 16;
    _editor.backgroundColor = FPColor(FPRoleContainer);
    _editor.textColor = FPColor(FPRoleOnSurface);
    [self.contentView addSubview:_editor];
    if (_memberId > 0) {
        _subject = [[UITextField alloc] initWithFrame:CGRectZero];
        _subject.borderStyle = UITextBorderStyleRoundedRect;
        _subject.placeholder = @"Тема диалога";
        id savedSubject = [draft objectForKey:@"subject"];
        if ([savedSubject isKindOfClass:[NSString class]]) _subject.text = savedSubject;
        [_subject addTarget:self action:@selector(saveDraft) forControlEvents:UIControlEventEditingChanged];
        _subject.font = FPFont(16, 0, YES);
        [self.contentView addSubview:_subject];
    }
    if ([_initialQuote length]) [self saveDraft];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationEnteredBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillHideNotification object:nil];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [_editor becomeFirstResponder]; }
- (void)layoutContent
{
    UIEdgeInsets safe = FPSafeInsets(self.view);
    CGRect bounds = self.contentView.bounds;
    CGFloat top = _subject ? 56 : 8;
    if (_subject) _subject.frame = CGRectMake(safe.left + 12, 8, MAX(0, bounds.size.width - safe.left - safe.right - 24), 40);
    _editor.frame = CGRectMake(safe.left + 12, top, MAX(0, bounds.size.width - safe.left - safe.right - 24),
                               MAX(44, bounds.size.height - _keyboardHeight - top - 12));
}
- (void)themeDidChange
{
    _editor.backgroundColor = FPColor(FPRoleContainer);
    _editor.textColor = FPColor(FPRoleOnSurface);
}
- (void)keyboard:(NSNotification *)note
{
    CGRect screenFrame = [[[note userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect frame = [self.contentView convertRect:screenFrame fromView:nil];
    CGRect overlap = CGRectIntersection(self.contentView.bounds, frame);
    _keyboardHeight = CGRectIsNull(overlap) ? 0 : overlap.size.height;
    [UIView animateWithDuration:0.2 animations:^{ [self layoutContent]; }];
}
- (void)appendQuote:(NSString *)quote
{
    if (![_editor isFirstResponder] && ![self isViewLoaded]) {
        [_initialQuote release];
        _initialQuote = [quote copy];
    }
}

- (void)saveDraft
{
    if (!_draftKey || _sending) return;
    NSString *text = _editor.text ? _editor.text : @"";
    NSString *subject = _subject.text ? _subject.text : @"";
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![text length] && ![subject length]) [defaults removeObjectForKey:_draftKey];
    else [defaults setObject:[NSDictionary dictionaryWithObjectsAndKeys:text, @"text", subject, @"subject", nil] forKey:_draftKey];
}

- (void)applicationEnteredBackground:(NSNotification *)notification
{
    (void)notification;
    [self saveDraft];
}

- (void)textViewDidChange:(UITextView *)textView
{
    (void)textView;
    [self saveDraft];
}

- (void)close
{
    if (_sending) return;
    [self saveDraft];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)send
{
    if (_sending) return;
    NSString *text = [_editor.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![text length]) { [self showToast:@"Введите сообщение"]; return; }
    [self saveDraft];
    _sending = YES;
    _sendButton.enabled = NO;
    _editor.editable = NO;
    _subject.enabled = NO;
    void (^done)(NSError *) = ^(NSError *error) {
        _sending = NO;
        _sendButton.enabled = YES;
        _editor.editable = YES;
        _subject.enabled = YES;
        if (error) { [self showToast:[error localizedDescription]]; return; }
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:_draftKey];
        if (_sent) _sent();
        [self dismissViewControllerAnimated:YES completion:nil];
    };
    if (_memberId > 0) {
        NSString *subject = [_subject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [_api sendMessage:text subject:subject member:_memberId completion:done];
    } else if (_dialogId > 0) [_api sendQMSText:text dialog:_dialogId completion:done];
    else [_api sendReply:text topic:_topicId completion:done];
}
@end
