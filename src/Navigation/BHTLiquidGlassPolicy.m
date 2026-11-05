#import "BHTLiquidGlassPolicy.h"
#include <math.h>

NSNumber* BHTLiquidGlassNavigationOverride(BOOL enabled, BOOL classic, BOOL available) {
    if (enabled && available) return @YES;
    return classic ? @NO : nil;
}

CGRect BHTLiquidGlassFrame(CGRect bounds, BOOL vertical) {
    if (CGRectIsEmpty(bounds) || !isfinite(bounds.size.width) || !isfinite(bounds.size.height)) return CGRectZero;
    // Keep every native tab's frame and hit area. Only the material is inset.
    CGFloat horizontal = MIN(vertical ? 8 : 12, MAX(0, (bounds.size.width - 44) / 2));
    CGFloat top = MIN(vertical ? 10 : 2, MAX(0, (bounds.size.height - 44) / 2));
    return CGRectInset(bounds, horizontal, top);
}

CGRect BHTLiquidGlassSelectionFrame(CGRect item, CGRect glass) {
    if (CGRectIsEmpty(item) || CGRectIsEmpty(glass)) return CGRectZero;
    CGRect clipped = CGRectIntersection(item, glass);
    if (CGRectIsNull(clipped) || CGRectIsEmpty(clipped)) return CGRectZero;
    CGFloat insetX = MIN(5, MAX(0, (clipped.size.width - 24) / 2));
    CGFloat insetY = MIN(4, MAX(0, (clipped.size.height - 24) / 2));
    return CGRectInset(clipped, insetX, insetY);
}
