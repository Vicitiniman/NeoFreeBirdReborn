#import <UIKit/UIKit.h>
#import "BHTLiquidGlassPolicy.h"

FOUNDATION_EXPORT BOOL BHTNativeLiquidGlassAvailable(void);
FOUNDATION_EXPORT void BHTUpdateLiquidGlassTabBar(UIViewController* controller);
FOUNDATION_EXPORT void BHTUpdateLiquidGlassNavigationBar(UINavigationBar* bar);
FOUNDATION_EXPORT void BHTRefreshLiquidGlassDesign(void);
FOUNDATION_EXPORT NSDictionary* BHTLiquidGlassDesignDiagnosticSnapshot(void);
