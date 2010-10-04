#import <UICaboodle/UCPlatform.h>

#import <UIKit/UIKit.h>

@interface UCViewController : UIViewController {
    id delegate_;
}
- (void)setDelegate:(id)delegate;
- (void) reloadData;
@end

