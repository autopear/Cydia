#import <UICaboodle/UCPlatform.h>

#import <UIKit/UIKit.h>

@class NSString;
@class RVBook;

@interface RVPage : UIView {
    _transient RVBook *book_;
    _transient id delegate_;
}

- (NSString *) title;
- (NSString *) backButtonTitle;
- (id) rightButtonTitle;
- (NSString *) leftButtonTitle;
- (UIView *) accessoryView;

- (UIImage *) rightButtonImage;

- (UINavigationButtonStyle) leftButtonStyle;
- (UINavigationButtonStyle) rightButtonStyle;

- (void) _rightButtonClicked;
- (void) _leftButtonClicked;

- (void) setPageActive:(BOOL)active;
- (void) resetViewAnimated:(BOOL)animated;

- (void) setBackButtonTitle:(NSString *)title;

- (void) reloadButtons;
- (void) reloadData;

- (id) initWithBook:(RVBook *)book;

- (void) setDelegate:(id)delegate;
- (void) setBook:(RVBook *)book;

@end
