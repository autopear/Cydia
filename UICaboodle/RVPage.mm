#import "RVPage.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "RVBook.h"

@implementation RVPage

- (NSString *) title {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (NSString *) backButtonTitle {
    return nil;
}

- (NSString *) leftButtonTitle {
    return nil;
}

- (NSString *) rightButtonTitle {
    return nil;
}

- (UINavigationButtonStyle) leftButtonStyle {
    return [self leftButtonTitle] == nil ? UINavigationButtonStyleBack : UINavigationButtonStyleNormal;
}

- (UINavigationButtonStyle) rightButtonStyle {
    return UINavigationButtonStyleNormal;
}

- (void) _rightButtonClicked {
    [self doesNotRecognizeSelector:_cmd];
}

- (void) _leftButtonClicked {
    [self doesNotRecognizeSelector:_cmd];
}

- (UIView *) accessoryView {
    return nil;
}

- (void) setPageActive:(BOOL)active {
}

- (void) resetViewAnimated:(BOOL)animated {
    [self doesNotRecognizeSelector:_cmd];
}

- (void) setBackButtonTitle:(NSString *)title {
    [book_ setBackButtonTitle:title forPage:self];
}

- (void) reloadButtons {
    [book_ reloadButtonsForPage:self];
}

- (void) reloadData {
}

- (id) initWithBook:(RVBook *)book {
    if ((self = [super initWithFrame:[book pageBounds]]) != nil) {
        book_ = book;
    } return self;
}

- (void) setDelegate:(id)delegate {
    delegate_ = delegate;
}

@end
