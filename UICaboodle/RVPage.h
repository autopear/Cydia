#import "UICaboodle.h"

#import <UIKit/UIKit.h>

@class NSString;
@class RVBook;

@interface RVPage : UIView {
    _transient RVBook *book_;
    _transient id delegate_;
}

- (NSString *) title;
- (NSString *) backButtonTitle;
- (NSString *) rightButtonTitle;
- (NSString *) leftButtonTitle;
- (UIView *) accessoryView;

- (UINavigationButtonStyle) leftButtonStyle;
- (UINavigationButtonStyle) rightButtonStyle;

- (void) _rightButtonClicked;
- (void) _leftButtonClicked;

- (void) setPageActive:(BOOL)active;
- (void) resetViewAnimated:(BOOL)animated;

- (void) setTitle:(NSString *)title;
- (void) setBackButtonTitle:(NSString *)title;

- (void) reloadButtons;
- (void) reloadData;

- (id) initWithBook:(RVBook *)book;

- (void) setDelegate:(id)delegate;

@end
