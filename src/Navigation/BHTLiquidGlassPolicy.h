#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// UIKit-free policy shared by the production design and native regressions.
FOUNDATION_EXPORT NSNumber* BHTLiquidGlassNavigationOverride(BOOL enabled, BOOL classic, BOOL available);
FOUNDATION_EXPORT CGRect BHTGlassDockFrame(CGRect nativeFrame, CGRect hostBounds, CGFloat safeBottom,
                                          NSUInteger count, BOOL vertical, BOOL labels);
FOUNDATION_EXPORT CGRect BHTGlassDockItemFrame(CGSize bounds, NSUInteger index, NSUInteger count, BOOL vertical);
FOUNDATION_EXPORT CGSize BHTGlassDockContentSize(CGSize bounds, NSUInteger count, BOOL vertical);
FOUNDATION_EXPORT NSString* BHTGlassDockSymbol(NSString* page, BOOL selected);
FOUNDATION_EXPORT BOOL BHTGlassDockCanRoute(id owner, BOOL longPress);
FOUNDATION_EXPORT BOOL BHTGlassDockRoute(id owner, id originalTab, BOOL longPress);
