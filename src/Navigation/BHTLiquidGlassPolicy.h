#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// UIKit-free policy shared by the production design and native regressions.
FOUNDATION_EXPORT NSNumber* BHTLiquidGlassNavigationOverride(BOOL enabled, BOOL classic, BOOL available);
FOUNDATION_EXPORT CGRect BHTGlassDockFrame(CGRect nativeFrame, CGRect hostBounds, CGFloat safeBottom,
                                          NSUInteger count, BOOL vertical, BOOL labels);
FOUNDATION_EXPORT CGRect BHTGlassDockItemFrame(CGSize bounds, NSUInteger index, NSUInteger count, BOOL vertical);
FOUNDATION_EXPORT CGSize BHTGlassDockContentSize(CGSize bounds, NSUInteger count, BOOL vertical);
FOUNDATION_EXPORT CGRect BHTGlassDockCompactFrame(CGRect expanded, BOOL rightToLeft);
typedef struct {
    CGFloat lastOffset;
    CGFloat distance;
    NSInteger direction;
    BOOL hasOffset;
    BOOL collapsed;
    BOOL manuallyExpanded;
} BHTGlassDockScrollState;
FOUNDATION_EXPORT BOOL BHTGlassDockObserveScroll(BHTGlassDockScrollState* state, CGFloat offset,
    CGFloat maximumOffset, BOOL dragging, BOOL decelerating, BOOL pinned);
FOUNDATION_EXPORT void BHTGlassDockReveal(BHTGlassDockScrollState* state, BOOL manualOverride);
FOUNDATION_EXPORT void BHTGlassDockResetScroll(BHTGlassDockScrollState* state, BOOL samePage);
FOUNDATION_EXPORT CGRect BHTGlassDockVisibleFrame(CGRect nativeFrame, BOOL overlayEnabled, BOOL activeDockedContent);
FOUNDATION_EXPORT CGFloat BHTGlassDockOpacity(NSInteger percentage, BOOL reduceTransparency);
FOUNDATION_EXPORT BOOL BHTGlassOpacityPreferenceIsValid(id value);
FOUNDATION_EXPORT CGRect BHTGlassDockAvoidedComposeFrame(CGRect nativeFrame, CGRect dockFrame);
FOUNDATION_EXPORT NSString* BHTGlassDockSymbol(NSString* page, BOOL selected);
FOUNDATION_EXPORT BOOL BHTGlassDockCanRoute(id owner, BOOL longPress);
FOUNDATION_EXPORT BOOL BHTGlassDockRoute(id owner, id originalTab, BOOL longPress);
