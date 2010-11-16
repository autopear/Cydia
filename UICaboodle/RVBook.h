#import <UICaboodle/UCPlatform.h>

#import <UIKit/UIKit.h>

@protocol HookProtocol
- (void) didDismissModalViewController;
@end

@interface UCNavigationController : UINavigationController {
    _transient id<HookProtocol> hook_;
}
- (void) setHook:(id<HookProtocol>)hook;
@end


