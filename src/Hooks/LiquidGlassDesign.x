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

%hook T1TabBarViewController
- (CGRect)visibleTabBarFrame {
    CGRect native = %orig;
    return BHTGlassDockVisibleFrame(native, BHTGlassDockUsesOverlayLayout((UIViewController*)self));
}
%end

%hook T1AppSplitViewController
- (double)private_bottomTabBarHeight {
    double native = %orig;
    return BHTGlassDockNativeStockHeight((UIViewController*)self, native);
}
- (void)viewDidLayoutSubviews {
    %orig;
    BHTUpdateGlassAppContainer((UIViewController*)self);
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
