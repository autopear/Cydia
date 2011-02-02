#import <UICaboodle/UCPlatform.h>

#import <UIKit/UIKit.h>

@interface CYViewController : UIViewController {
    id delegate_;
    BOOL loaded_;
}
- (NSURL *)navigationURL;
- (void) setDelegate:(id)delegate;
- (void) reloadData;
- (void) releaseSubviews;
@end

