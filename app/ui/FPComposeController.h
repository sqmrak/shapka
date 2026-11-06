#import "FPScreenController.h"

@interface FPComposeController : FPScreenController <UITextViewDelegate> {
    NSInteger _topicId;
    NSInteger _memberId;
    NSInteger _dialogId;
    NSString *_recipient;
    UITextField *_subject;
    UITextView *_editor;
    UIButton *_sendButton;
    CGFloat _keyboardHeight;
    BOOL _sending;
    NSString *_draftKey;
    NSString *_initialQuote;
    void (^_sent)(void);
}
- (id)initWithApi:(FPApi *)api topicId:(NSInteger)topicId sent:(void (^)(void))sent;
- (void)appendQuote:(NSString *)quote;
- (id)initWithApi:(FPApi *)api memberId:(NSInteger)memberId name:(NSString *)name;
- (id)initWithApi:(FPApi *)api dialogId:(NSInteger)dialogId sent:(void (^)(void))sent;
@end
