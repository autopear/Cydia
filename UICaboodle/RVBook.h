#import "UICaboodle.h"

#import <UIKit/UIKit.h>

@class NSMutableArray;
@class RVBook;
@class RVPage;
@class UINavigationBar;
@class UITransitionView;

@interface UIView (PopUpView)
- (void) popFromSuperviewAnimated:(BOOL)animated;
- (void) popSubview:(UIView *)view;
@end

@protocol RVNavigationBarDelegate
@end

@protocol RVDelegate
- (void) setPageActive:(BOOL)active with:(id)object;
- (void) resetViewAnimated:(BOOL)animated with:(id)object;
- (void) reloadDataWith:(id)object;
- (void) popUpBook:(RVBook *)book;
- (CGRect) popUpBounds;
@end

@interface RVBook : UIView <
    RVNavigationBarDelegate
> {
    NSMutableArray *pages_;
    UINavigationBar *navbar_;
    UITransitionView *transition_;
    BOOL resetting_;
    _transient id delegate_;
    UIToolbar *toolbar_;
}

- (UINavigationBar *) navigationBar;

- (id) initWithFrame:(CGRect)frame;
- (void) setDelegate:(id)delegate;

- (void) setPage:(RVPage *)page;

- (void) swapPage:(RVPage *)page;
- (void) pushPage:(RVPage *)page animated:(BOOL)animated;
- (void) pushPage:(RVPage *)page;
- (void) popPages:(unsigned)pages;

- (void) pushBook:(RVBook *)book;

- (void) resetViewAnimated:(BOOL)animated;
- (void) resetViewAnimated:(BOOL)animated toPage:(RVPage *)page;

- (void) setBackButtonTitle:(NSString *)title forPage:(RVPage *)page;
- (void) reloadTitleForPage:(RVPage *)page;
- (void) reloadButtonsForPage:(RVPage *)page;
- (NSString *) getTitleForPage:(RVPage *)page;

- (void) reloadData;

- (CGRect) pageBounds;
- (void) close;

@end

@interface RVPopUpBook : RVBook {
    _transient RVBook *parent_;
    bool cancel_;
}

@end
