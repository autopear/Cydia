#import <UICaboodle/RVPage.h>
#import <UICaboodle/RVBook.h>

#import <UIKit/UIKit.h>

@interface UIView (RVBook)
- (void) resetViewAnimated:(BOOL)animated;
- (void) clearView;
@end

@interface UITable (RVBook)
- (void) resetViewAnimated:(BOOL)animated;
- (void) clearView;
@end

@interface UISectionList (RVBook)
- (void) resetViewAnimated:(BOOL)animated;
- (void) clearView;
@end
