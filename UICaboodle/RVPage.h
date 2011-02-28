#import <UICaboodle/UCPlatform.h>

#import <UIKit/UIKit.h>

@interface UIViewController (Cydia)
- (BOOL) hasLoaded;
- (void) reloadData;
- (void) unloadData;
@end

@interface CYViewController : UIViewController {
    _transient id delegate_;
    BOOL loaded_;
}

// The default implementation of this method is essentially a no-op,
// but calling the superclass implementation is *required*.
- (void) reloadData;

- (void) unloadData;

// This URL is used to save the state of the view controller. Return
// nil if you cannot or should not save the URL for this page.
- (NSURL *) navigationURL;

// By default, this delegate is unused. However, it's provided here in case
// you need some kind of delegate in a subclass.
- (void) setDelegate:(id)delegate;
- (id) delegate;

// Override this in subclasses if you manage the "has seen first load" state yourself.
- (BOOL) hasLoaded;

// This is called when the view managed by the view controller is released.
// That is not always when the controller itself is released: it also can
// happen when more memory is needed by the system or whenever the controller
// just happens not to be visible.
- (void) releaseSubviews;

@end
