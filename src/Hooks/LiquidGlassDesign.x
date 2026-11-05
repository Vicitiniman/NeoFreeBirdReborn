#import "HookHelpers.h"
#import "Navigation/BHTLiquidGlassDesign.h"

@interface TFNNavigationBar : UINavigationBar @end

%hook TFNDataViewController
- (void)scrollViewDidScroll:(UIScrollView*)scrollView {
    %orig;
    BHTObserveGlassDockScroll((UIViewController*)self, scrollView);
}
%end

%hook T1URTViewController
- (void)scrollViewDidScroll:(UIScrollView*)scrollView {
    %orig;
    BHTObserveGlassDockScroll((UIViewController*)self, scrollView);
}
%end

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
