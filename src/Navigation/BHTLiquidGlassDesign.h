#import <UIKit/UIKit.h>
#import "BHTLiquidGlassPolicy.h"

FOUNDATION_EXPORT BOOL BHTNativeLiquidGlassAvailable(void);
FOUNDATION_EXPORT void BHTUpdateLiquidGlassTabBar(UIViewController* controller);
FOUNDATION_EXPORT void BHTUpdateLiquidGlassNavigationBar(UINavigationBar* bar);
FOUNDATION_EXPORT void BHTRefreshLiquidGlassDesign(void);
FOUNDATION_EXPORT void BHTRefreshGlassDockForTabView(UIView* view);
FOUNDATION_EXPORT void BHTObserveGlassDockScroll(UIViewController* source, UIScrollView* scrollView);
FOUNDATION_EXPORT BOOL BHTGlassDockUsesOverlayLayout(UIViewController* owner);
FOUNDATION_EXPORT BOOL BHTGlassDockHasActiveDockedContent(UIViewController* owner);
FOUNDATION_EXPORT CGRect BHTGlassDockAvoidanceFrame(UIView* view);
FOUNDATION_EXPORT NSDictionary* BHTLiquidGlassDesignDiagnosticSnapshot(void);
