#import "HookHelpers.h"
#import "Navigation/BHTLiquidGlassDesign.h"

@interface TFNNavigationBar : UINavigationBar @end

%hook TFNNavigationBar
- (void)layoutSubviews {
    %orig;
    BHTUpdateLiquidGlassNavigationBar((UINavigationBar*)self);
}
- (void)traitCollectionDidChange:(UITraitCollection*)previousTraits {
    %orig(previousTraits);
    BHTUpdateLiquidGlassNavigationBar((UINavigationBar*)self);
}
%end
