#import <Foundation/Foundation.h>
#import "FPNetwork.h"
#import "FPModels.h"

typedef void (^FPApiCompletion)(id result, NSError *error);
typedef void (^FPApiDone)(NSError *error);
/* captchaURL is set when the server asks for the picture to be answered before it lets the member in */
typedef void (^FPApiLoginDone)(NSError *error, NSString *captchaURL);
typedef void (^FPApiCaptchaDone)(NSString *captchaURL, NSError *error);

extern NSString *const FPApiAccountNotification;

/* connects on demand, runs the forum requests and parses their replies off the main thread;
   every completion runs on the main thread, and stale results are the caller's to drop by request identity */
@interface FPApi : NSObject {
    FPNetwork *_network;
    dispatch_queue_t _parseQueues[2];
    NSUInteger _nextParseQueue;
    NSMutableArray *_waiters;
    BOOL _connected;
    BOOL _connecting;
    BOOL _active;
}
- (id)initWithNetwork:(FPNetwork *)network;
/* the application became active: connect ahead of the first request */
- (void)resume;
/* the application resigns: close the connection and fail the requests waiting for it */
- (void)pause;
/* the index of the last successful load kept on disk, or nil; the forum list changes rarely, so it shows at once */
- (NSArray *)cachedForumIndex;
- (NSArray *)cachedNews;
- (void)loadNews:(FPApiCompletion)completion;
- (void)loadNewsArticle:(NSInteger)identifier completion:(FPApiCompletion)completion;
- (void)loadForumIndex:(FPApiCompletion)completion;
- (void)loadForum:(NSInteger)forumId offset:(NSInteger)offset count:(NSInteger)count completion:(FPApiCompletion)completion;
- (void)loadTopic:(NSInteger)topicId offset:(NSInteger)offset count:(NSInteger)count completion:(FPApiCompletion)completion;
- (void)loadAnnouncement:(NSInteger)identifier completion:(FPApiCompletion)completion;
/* resolves an attachment id to the address returned by the server */
- (void)resolveAttachment:(NSInteger)attachmentId completion:(FPApiCompletion)completion;
/* posts a new reply to a topic */
- (void)sendReply:(NSString *)text topic:(NSInteger)topicId completion:(FPApiDone)completion;
/* rates a post: up is a plus, otherwise a minus; the server answers once per member and post */
- (void)votePost:(NSInteger)postId up:(BOOL)up completion:(FPApiDone)completion;
/* the members who rated the post, as FPParseVotes returns them */
- (void)loadVotesOfPost:(NSInteger)postId completion:(FPApiCompletion)completion;
/* raises or lowers the karma of a member for one of his posts; the server names the reason of a refusal in the error */
- (void)changeKarmaOfMember:(NSInteger)memberId post:(NSInteger)postId up:(BOOL)up reason:(NSString *)reason completion:(FPApiDone)completion;
- (void)sendMessage:(NSString *)text subject:(NSString *)subject member:(NSInteger)memberId completion:(FPApiDone)completion;
- (void)loadQMSContacts:(NSInteger)memberId completion:(FPApiCompletion)completion;
- (void)loadQMSTalk:(NSInteger)dialogId completion:(FPApiCompletion)completion;
- (void)loadQMSTalk:(NSInteger)dialogId before:(NSInteger)messageId completion:(FPApiCompletion)completion;
- (void)sendQMSText:(NSString *)text dialog:(NSInteger)dialogId completion:(FPApiDone)completion;
/* every favorite topic of the signed in member as FPTopicEntry values, read in windows of 30 up to the app limit of 500;
   a guest has no server list and gets the error of the server */
- (void)loadFavorites:(FPApiCompletion)completion;
/* adds the topic to the favorites of the member on the server or removes it */
- (void)setTopic:(NSInteger)topicId favorite:(BOOL)favorite completion:(FPApiDone)completion;
/* captcha is the number the picture says, zero for none; remember keeps the key on the device, otherwise it lasts until the app ends */
- (void)loginWithName:(NSString *)name password:(NSString *)password hidden:(BOOL)hidden captcha:(NSInteger)captcha remember:(BOOL)remember completion:(FPApiLoginDone)completion;
/* a fresh picture to answer */
- (void)loadCaptcha:(FPApiCaptchaDone)completion;
/* forgets the saved account and reconnects as a guest */
- (void)logout:(FPApiDone)completion;
/* the saved member id, or 0 for a guest */
- (NSInteger)memberId;
@end
