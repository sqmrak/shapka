#import <Foundation/Foundation.h>

extern NSString *const FPFavoritesChangedNotification;

/* the topics belong to the member the app is signed in as: a guest has a list on the device alone, and each member has a
   copy of the server list, so one account never shows the topics of another; news stay on the device for everyone */
@interface FPFavorites : NSObject
+ (void)setMember:(NSInteger)member;
+ (NSInteger)member;
/* replaces the copy of the member with the list the server sent, as FPTopicEntry values */
+ (void)replaceTopics:(NSArray *)entries;
+ (NSArray *)topics;
+ (NSArray *)news;
+ (BOOL)containsNews:(NSString *)url;
+ (BOOL)addNews:(NSDictionary *)item;
+ (void)removeNews:(NSString *)url;
+ (BOOL)containsTopic:(NSInteger)topicId;
+ (BOOL)addTopic:(NSInteger)topicId title:(NSString *)title;
+ (void)removeTopic:(NSInteger)topicId;
@end
