#import <UIKit/UIKit.h>
#import "FPTheme.h"

typedef enum {
    FPRowSection,
    FPRowCategory,
    FPRowForum,
    FPRowTopic,
    FPRowNotice,
    FPRowSetting
} FPRowKind;

/* where a row sits in its group: groups are drawn as one rounded card cut into pieces */
typedef enum {
    FPRowSingle,
    FPRowTop,
    FPRowMiddle,
    FPRowBottom
} FPRowPosition;

/* the horizontal inset of the cards: a fixed margin, widened on wide screens so the column stays readable */
CGFloat FPColumnInset(CGFloat width, UIEdgeInsets safe);

/* one opaque view draws a whole row, so scrolling builds no label hierarchy */
@interface FPRowView : UIView {
    FPRowKind _kind;
    FPRowPosition _position;
    NSString *_title;
    NSString *_subtitle;
    NSString *_meta;
    NSString *_badge;
    BOOL _unread;
    BOOL _dimmed;
    BOOL _expanded;
    BOOL _badgeActive;
    BOOL _highlighted;
    CGFloat _sideInset;
}
@property (nonatomic, assign) FPRowKind kind;
@property (nonatomic, assign) FPRowPosition position;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *meta;
@property (nonatomic, copy) NSString *badge;
@property (nonatomic, assign) BOOL unread;
@property (nonatomic, assign) BOOL dimmed;
@property (nonatomic, assign) BOOL expanded;
/* a setting value drawn as the selected pill instead of the quiet one */
@property (nonatomic, assign) BOOL badgeActive;
@property (nonatomic, assign) BOOL highlighted;
@property (nonatomic, assign) CGFloat sideInset;
+ (CGFloat)heightForKind:(FPRowKind)kind title:(NSString *)title subtitle:(NSString *)subtitle width:(CGFloat)width sideInset:(CGFloat)sideInset;
@end

@interface FPListCell : UITableViewCell {
    FPRowView *_row;
}
@property (nonatomic, readonly) FPRowView *row;
@end
