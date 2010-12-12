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
    if ([self parentViewController]) {
        return [[self parentViewController] shouldAutorotateToInterfaceOrientation:orientation];
    } else {
        return [super shouldAutorotateToInterfaceOrientation:orientation];
    }
}
@end
