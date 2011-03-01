#import "RVPage.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern bool IsWildcat_;

@implementation UIViewController (Cydia)

- (BOOL) hasLoaded {
    return YES;
}

- (void) reloadData {
}

- (void) unloadData {
    if (UIViewController *modal = [self modalViewController])
        [modal unloadData];
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

    // Load on first appearance. We don't need to set the loaded flag here
    // because it is set for us the first time -reloadData is called.
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
    // Nasty hack for 2.x-compatibility. In 3.0+, we can and
    // should just override -viewDidUnload instead.
    if (view == nil)
        [self releaseSubviews];

    [super setView:view];
}

- (void) reloadData {
    [super reloadData];

    // This is called automatically on the first appearance of a controller,
    // or any other time it needs to reload the information shown. However (!),
    // this is not called by any tab bar or navigation controller's -reloadData
    // method unless this controller returns YES from -hadLoaded.
    loaded_ = YES;
}

- (void) unloadData {
    loaded_ = NO;
    [super unloadData];
}

- (NSURL *) navigationURL {
    return nil;
}

- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return IsWildcat_ || orientation == UIInterfaceOrientationPortrait;
}

@end
