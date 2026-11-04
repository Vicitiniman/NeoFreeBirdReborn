#import "BHTTimelineModelRuntime.h"
#import <objc/runtime.h>

Class BHTURTStatusItemViewModelClass(void) {
    // Do not cache a failed lookup: Swift classes can be registered after the
    // injection constructor. Lookups use the runtime's cached Objective-C class table.
    return objc_lookUpClass("URTTimelineStatusItemViewModel") ?:
           objc_lookUpClass("T1URTTimelineStatusItemViewModel");
}

BOOL BHTIsURTStatusItemViewModel(id object) {
    Class current = BHTURTStatusItemViewModelClass();
    if (current && [object isKindOfClass:current]) return YES;
    Class legacy = objc_lookUpClass("T1URTTimelineStatusItemViewModel");
    return legacy && [object isKindOfClass:legacy];
}
