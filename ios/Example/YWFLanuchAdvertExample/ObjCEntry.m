#import "ObjCEntry.h"
#import <WebKit/WebKit.h>
#import <YWFLanuchAdvert/YWFLanuchAdvert-Swift.h>

static ObjCEntry *YWFHolder;
static BOOL YWFAllowJump = YES;
static void (^YWFCompletion)(void);

@interface ObjCEntry () <YWFLanuchAdvertDelegate>
@end

@implementation ObjCEntry

+ (void)showOnWindow:(UIWindow *)window
           allowJump:(BOOL)allowJump
          completion:(void (^)(void))completion {
    if (YWFHolder == nil) {
        YWFHolder = [ObjCEntry new];
    }
    YWFAllowJump = allowJump;
    YWFCompletion = [completion copy];
    YWFLanuchAdvert.shared.delegate = YWFHolder;
    [YWFLanuchAdvert.shared showOnWindow:window completion:^{
        if (YWFCompletion != nil) {
            YWFCompletion();
        }
    }];
}

- (BOOL)ywfLanuchAdvertShouldJumpWhenTimeReachedZero:(YWFLanuchAdvert *)advert {
    return YWFAllowJump;
}

- (WKWebView *)ywfLanuchAdvertCustomWebView:(YWFLanuchAdvert *)advert {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    return [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
}

@end
