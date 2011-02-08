#import "RVPage.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "RVBook.h"

extern bool IsWildcat_;

@implementation CYViewController
- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}
- (void) reloadData {
}
- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return IsWildcat_ || orientation == UIInterfaceOrientationPortrait;
}
@end
