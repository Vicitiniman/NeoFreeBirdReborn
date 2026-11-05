#import <UIKit/UIKit.h>
FOUNDATION_EXPORT BOOL BHTPostSurfaceIsBackground(NSString* className, CGRect frame, CGRect bounds);
FOUNDATION_EXPORT void BHTApplyPostSurfaceTheme(UIView* view, BOOL includePlanes);
FOUNDATION_EXPORT void BHTApplyAppContainerTheme(UIViewController* controller);
FOUNDATION_EXPORT NSDictionary* BHTPostSurfaceThemeDiagnostics(void);
