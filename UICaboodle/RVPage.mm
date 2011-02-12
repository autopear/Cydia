#import "RVPage.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "RVBook.h"

extern bool IsWildcat_;

@implementation UIViewController (Cydia)

- (BOOL) hasLoaded {
    return YES;
}

@end

@implementation CYViewController

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (id) delegate {
    return delegate_;
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (![self hasLoaded])
        [self reloadData];
}

- (BOOL) hasLoaded {
    return loaded_;
}

- (void) releaseSubviews {
    // Do nothing.
}

- (void) setView:(UIView *)view {
    if (view == nil)
        [self releaseSubviews];

    [super setView:view];
}

- (void) reloadData {
    loaded_ = YES;
}

- (NSURL *) navigationURL {
    return nil;
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return IsWildcat_ || orientation == UIInterfaceOrientationPortrait;
}

@end
