#import "HookHelpers.h"
#import "Navigation/BHTGlassNavigation.h"

%hook _TtC14T1TwitterSwift34XTabbedAppNavigationViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    BHTUpdateGlassNavigation((UIViewController*)self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    BHTUpdateGlassNavigation((UIViewController*)self);
}
%end
