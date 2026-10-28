#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjCEntry : NSObject
+ (void)showOnWindow:(UIWindow *)window
           allowJump:(BOOL)allowJump
          completion:(void (^)(void))completion
NS_SWIFT_NAME(show(on:allowJump:completion:));
@end

NS_ASSUME_NONNULL_END
