#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// UIKit-free policy shared by the production design and native regressions.
FOUNDATION_EXPORT NSNumber* BHTLiquidGlassNavigationOverride(BOOL enabled, BOOL classic, BOOL available);
FOUNDATION_EXPORT CGRect BHTLiquidGlassFrame(CGRect bounds, BOOL vertical);
FOUNDATION_EXPORT CGRect BHTLiquidGlassSelectionFrame(CGRect item, CGRect glass);
