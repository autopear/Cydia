#import "UICaboodle.h"

#import <UIKit/UIView.h>

@class NSMutableArray;
@class RVPage;
@class UINavigationBar;
@class UITransitionView;

@protocol RVDelegate
- (void) setPageActive:(BOOL)active with:(id)object;
- (void) resetViewAnimated:(BOOL)animated with:(id)object;
- (void) reloadDataWith:(id)object;
@end

@interface RVBook : UIView {
    NSMutableArray *pages_;
    UINavigationBar *navbar_;
    UITransitionView *transition_;
    BOOL resetting_;
    _transient id delegate_;
}

- (UINavigationBar *) navigationBar;

- (id) initWithFrame:(CGRect)frame;
- (void) setDelegate:(id)delegate;

- (void) setPage:(RVPage *)page;

- (void) pushPage:(RVPage *)page;
- (void) popPages:(unsigned)pages;

- (void) resetViewAnimated:(BOOL)animated;
- (void) resetViewAnimated:(BOOL)animated toPage:(RVPage *)page;

- (void) setBackButtonTitle:(NSString *)title forPage:(RVPage *)page;
- (void) reloadTitleForPage:(RVPage *)page;
- (void) reloadButtonsForPage:(RVPage *)page;
- (NSString *) getTitleForPage:(RVPage *)page;

- (void) reloadData;

- (CGRect) pageBounds;

@end
