#import "RVPage.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "RVBook.h"

@implementation UCViewController 
- (void)setDelegate:(id)delegate {
	delegate_ = delegate;
}
- (BOOL) shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
	return NO; /* XXX: return YES; */
}
- (void) reloadData {
}
@end
