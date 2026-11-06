#import <UIKit/UIKit.h>

typedef void (^FPImageBlock)(UIImage *image);

/* downloads images over https and decodes them at the size they are shown, never at full size;
   results live in a cost-limited cache, equal requests share one download, and a failed address is not asked twice */
@interface FPImageLoader : NSObject
/* posted on the main thread, with the address as the object, when the pixel size of an image became known for the first time */
extern NSString *const FPImageSizeKnownNotification;

/* a decoded image for the url and size in points, or nil when it is not cached yet */
+ (UIImage *)cachedImageForURL:(NSString *)url size:(CGSize)size circle:(BOOL)circle;
/* the block runs on the main thread with the image or nil when the download or decoding failed;
   the owner lets a reused cell or a closed screen drop its pending blocks */
+ (void)loadURL:(NSString *)url size:(CGSize)size circle:(BOOL)circle owner:(id)owner completion:(FPImageBlock)completion;
+ (void)cancelOwner:(id)owner;
/* the pixel size of an image that was downloaded before, read from its header; safe on any thread; a message is laid out
   before its pictures arrive, and a 16 pixel icon in a link must not get the slot of a photo */
+ (BOOL)knownSizeForURL:(NSString *)url size:(CGSize *)size;
@end
