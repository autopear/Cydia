#import "RVBook.h"

#import <UIKit/UIKit.h>

#import <Foundation/Foundation.h>
#import <CoreGraphics/CGGeometry.h>

#include <cstdio>
#include <cstdlib>

#include <errno.h>

#import "RVPage.h"


@implementation UCNavigationController
- (void) setHook:(id)hook {
    hook_ = hook;
}
- (void) dismissModalViewControllerAnimated:(BOOL)animated {
    [super dismissModalViewControllerAnimated:YES];

    if (hook_ != nil)
        [hook_ didDismissModalViewController];
}
@end


