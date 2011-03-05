#import <BackRow/BRAppliance.h>
#import <BackRow/BRApplianceCategory.h>
#import <BackRow/BRBaseAppliance.h>
#import <BackRow/BRTopShelfController.h>
#import <BackRow/BRTopShelfView.h>
#import <BackRow/BRViewController.h>

#include <CydiaSubstrate/CydiaSubstrate.h>

@interface CydiaTopShelfController : NSObject <BRTopShelfController> {
    _H<BRTopShelfView> view_;
}

@end

@implementation CydiaTopShelfController

- (BRTopShelfView *) topShelfView {
    return view_;
}

- (void) selectCategoryWithIdentifier:(NSString *)identifier {
}

@end


@interface CydiaManageViewController : BRViewController {
}
@end

@implementation CydiaManageViewController
@end


@interface CydiaAppliance : BRBaseAppliance {
}
@end

@implementation CydiaAppliance

- (id) applianceCategories {
    return [NSArray arrayWithObjects:
        [BRApplianceCategory categoryWithName:@"Install" identifier:@"cydia-install" preferredOrder:0],
        [BRApplianceCategory categoryWithName:@"Manage" identifier:@"cydia-manage" preferredOrder:0],
        [BRApplianceCategory categoryWithName:@"Search" identifier:@"cydia-search" preferredOrder:0],
    nil];
}

- (id) controllerForIdentifier:(NSString *)identifier args:(NSDictionary *)args {
    return nil;
}

- (id) topShelfController {
    return [[[CydiaTopShelfController alloc] init] autorelease];
}

- (int) noContentBRError {
    // XXX: research
    return 0;
}

@end
