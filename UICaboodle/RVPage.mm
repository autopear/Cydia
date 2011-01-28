#import "RVPage.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "RVBook.h"

@implementation CYViewController
- (void)setDelegate:(id)delegate {
    delegate_ = delegate;
}
- (void) reloadData {
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad || orientation == UIInterfaceOrientationPortrait);
}
@end
