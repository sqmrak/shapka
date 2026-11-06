#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/* immutable-by-convention values built once from a server reply; strings are utf-8 decoded, html entities are
   resolved in titles and names and kept in post bodies for the bbcode layout to resolve per text run */

extern NSString *const FPModelErrorDomain;

@interface FPForumEntry : NSObject {
    NSInteger _forumId;
    NSString *_title;
    NSInteger _flags;
    NSString *_url;
}
@property (nonatomic, assign) NSInteger forumId;
@property (nonatomic, retain) NSString *title;
@property (nonatomic, assign) NSInteger flags;
/* empty for a plain forum */
@property (nonatomic, retain) NSString *url;
- (BOOL)isCategory;
- (BOOL)hasUnread;
@end

@interface FPTopicEntry : NSObject {
    NSInteger _topicId;
    NSString *_title;
    NSString *_summary;
    NSInteger _flags;
    long long _posts;
    long long _date;
    NSString *_lastUser;
    CGFloat _titleHeight;
    CGFloat _heightWidth;
}
@property (nonatomic, assign) NSInteger topicId;
@property (nonatomic, retain) NSString *title;
@property (nonatomic, retain) NSString *summary;
@property (nonatomic, assign) NSInteger flags;
@property (nonatomic, assign) long long posts;
@property (nonatomic, assign) long long date;
@property (nonatomic, retain) NSString *lastUser;
/* the measured title height for the width in heightWidth, owned by the list that shows the topic */
@property (nonatomic, assign) CGFloat titleHeight;
@property (nonatomic, assign) CGFloat heightWidth;
@end

@interface FPForumPage : NSObject {
    NSInteger _forumId;
    NSString *_title;
    NSArray *_subforums;
    NSArray *_pinned;
    NSArray *_topics;
    long long _topicTotal;
}
@property (nonatomic, assign) NSInteger forumId;
@property (nonatomic, retain) NSString *title;
@property (nonatomic, retain) NSArray *subforums;
@property (nonatomic, retain) NSArray *pinned;
@property (nonatomic, retain) NSArray *topics;
@property (nonatomic, assign) long long topicTotal;
@end

@interface FPAttachment : NSObject {
    NSInteger _attachmentId;
    BOOL _image;
    NSString *_name;
    long long _size;
    NSString *_url;
    NSInteger _width;
    NSInteger _height;
}
@property (nonatomic, assign) NSInteger attachmentId;
@property (nonatomic, assign) BOOL image;
@property (nonatomic, retain) NSString *name;
@property (nonatomic, assign) long long size;
@property (nonatomic, retain) NSString *url;
@property (nonatomic, assign) NSInteger width;
@property (nonatomic, assign) NSInteger height;
@end

@interface FPPost : NSObject {
    NSInteger _postId;
    NSInteger _flags;
    NSInteger _userId;
    NSString *_userName;
    NSInteger _group;
    long long _lastSeen;
    long long _reputation;
    long long _date;
    NSString *_body;
    NSString *_avatar;
    NSString *_signature;
    NSArray *_attachments;
    long long _editDate;
    NSString *_editor;
    NSString *_editReason;
    NSInteger _voteWord;
}
@property (nonatomic, assign) NSInteger postId;
@property (nonatomic, assign) NSInteger flags;
@property (nonatomic, assign) NSInteger userId;
@property (nonatomic, retain) NSString *userName;
@property (nonatomic, assign) NSInteger group;
@property (nonatomic, assign) long long lastSeen;
@property (nonatomic, assign) long long reputation;
@property (nonatomic, assign) long long date;
@property (nonatomic, retain) NSString *body;
@property (nonatomic, retain) NSString *avatar;
@property (nonatomic, retain) NSString *signature;
@property (nonatomic, retain) NSArray *attachments;
@property (nonatomic, assign) long long editDate;
@property (nonatomic, retain) NSString *editor;
@property (nonatomic, retain) NSString *editReason;
@property (nonatomic, assign) NSInteger voteWord;
- (BOOL)isHeader;
/* the post carries a rating, and the score is shown with it */
- (BOOL)hasRating;
- (NSInteger)rating;
/* the signed-in member may rate the post: it carries a rating and the member has not voted on it yet */
- (BOOL)canBeRated;
@end

@interface FPTopicPage : NSObject {
    NSInteger _topicId;
    NSString *_title;
    NSString *_summary;
    NSInteger _flags;
    long long _postTotal;
    NSArray *_posts;
}
@property (nonatomic, assign) NSInteger topicId;
@property (nonatomic, retain) NSString *title;
@property (nonatomic, retain) NSString *summary;
@property (nonatomic, assign) NSInteger flags;
@property (nonatomic, assign) long long postTotal;
@property (nonatomic, retain) NSArray *posts;
@end

/* one window of the favorites of the signed in member; entries counts forums too, so the next offset is known */
@interface FPFavoritesPage : NSObject {
    long long _total;
    NSUInteger _entries;
    NSArray *_topics;
}
@property (nonatomic, assign) long long total;
@property (nonatomic, assign) NSUInteger entries;
/* FPTopicEntry values with id, title and flags; favorite forums are not shown by the app */
@property (nonatomic, retain) NSArray *topics;
@end

/* the parsers return nil and fill error when the reply is malformed; they are safe on any thread */
NSArray *FPParseForumIndex(NSData *reply, NSError **error);
FPForumPage *FPParseForumPage(NSData *reply, NSError **error);
FPTopicPage *FPParseTopicPage(NSData *reply, NSError **error);
/* the members who rated a post, newest first as the server sends them: dictionaries with member, name, value (+1 or -1) and time */
NSArray *FPParseVotes(NSData *reply, NSError **error);
FPFavoritesPage *FPParseFavorites(NSData *reply, NSError **error);
