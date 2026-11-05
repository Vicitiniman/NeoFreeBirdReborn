#import "HookHelpers.h"
#import "Navigation/BHTComposeButtonVisibility.h"
#import "Navigation/BHTLiquidGlassDesign.h"
@interface TFNFloatingActionButton : UIView @end

%hook T1TabbedAppNavigationViewController
- (CGRect)_t1_floatingActionButtonFrame {
    CGRect native = %orig;
    UIViewController* owner = (UIViewController*)self;
    return owner.isViewLoaded ? BHTGlassDockAvoidedComposeFrame(native, BHTGlassDockAvoidanceFrame(owner.view)) : native;
}
- (void)_t1_setUpFloatingActionButton {
    %orig;
    BHTTrackComposeButtonOwner(self);
}
- (void)_t1_configureActionButtonForContext:(id)context animated:(BOOL)animated {
    %orig;
    BHTTrackComposeButtonOwner(self);
}
%end

%hook TFNFloatingActionButton
- (void)setHidden:(BOOL)hidden {
    %orig(BHTComposeButtonRequestedHidden((UIView*)self, hidden));
}
%end
