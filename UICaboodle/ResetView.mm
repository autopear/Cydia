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

@implementation UITable (RVBook)

- (void) resetViewAnimated:(BOOL)animated {
    [self selectRow:-1 byExtendingSelection:NO withFade:animated];
}

- (void) clearView {
    [self clearAllData];
}

@end

@implementation UITableView (RVBook)

- (void) resetViewAnimated:(BOOL)animated {
    [self selectRowAtIndexPath:nil animated:animated scrollPosition:UITableViewScrollPositionNone];
}

- (void) clearView {
    //XXX:[[self table] clearView];
}

@end

@implementation UISectionList (RVBook)

- (void) resetViewAnimated:(BOOL)animated {
    [[self table] resetViewAnimated:animated];
}

- (void) clearView {
    [[self table] clearView];
}

@end
