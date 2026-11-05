#import <UIKit/UIKit.h>
FOUNDATION_EXPORT BOOL BHTApplySurfaceBackingColor(UIView* view, UIColor* color);
FOUNDATION_EXPORT UIColor* BHTThemedSurfaceBackground(UIView* view, UIColor* nativeColor, BOOL registerSurface);
FOUNDATION_EXPORT void BHTApplyPostSurfaceTheme(UIView* view);
FOUNDATION_EXPORT void BHTApplySurfaceBackdropTheme(UIView* view);
FOUNDATION_EXPORT void BHTApplyAppContainerTheme(UIViewController* controller);
FOUNDATION_EXPORT void BHTApplyProfileContainerTheme(UIViewController* controller);
FOUNDATION_EXPORT void BHTApplyProfileStatsTheme(UIViewController* controller);
FOUNDATION_EXPORT NSDictionary* BHTPostSurfaceThemeDiagnostics(void);
