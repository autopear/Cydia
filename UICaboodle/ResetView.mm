#import "ResetView.h"

#include <objc/objc.h>
#include <objc/runtime.h>

#include <errno.h>

#include <cstdio>
#include <cstdlib>

@implementation UIView (RVBook)

- (void) resetViewAnimated:(BOOL)animated {
    fprintf(stderr, "%s\n", class_getName(self->isa));
    _assert(false);
}

- (void) clearView {
    fprintf(stderr, "%s\n", class_getName(self->isa));
    _assert(false);
}

@end

@implementation UITableView (RVBook)

- (void) resetViewAnimated:(BOOL)animated {
    //[self selectRowAtIndexPath:nil animated:animated scrollPosition:UITableViewScrollPositionNone];
    if (NSIndexPath *path = [self indexPathForSelectedRow])
        [self deselectRowAtIndexPath:path animated:animated];
}

- (void) clearView {
    //XXX:[[self table] clearView];
}

@end
