#import "RVPage.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "RVBook.h"

@implementation CYViewController

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (!loaded_)
        [self reloadData];
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
    return (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad || orientation == UIInterfaceOrientationPortrait);
}

@end
