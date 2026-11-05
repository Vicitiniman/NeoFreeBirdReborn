// The production clear/restore routines are compiled against the existing
// UIView stand-in. These tests exercise ownership, not UIKit glass rendering.
@interface BHTGlassChromeState : NSObject
@property(nonatomic, strong) UIView* material;
@property(nonatomic, strong) NSMutableArray<BHTGlassSavedView*>* savedViews;
@end
@implementation BHTGlassChromeState @end
static char BHTLiquidGlassStateKey;
static BHTGlassChromeState* BHTGlassState(id owner, BOOL create) {
    NSCAssert(!create, @"The test fixture only resolves existing production state");
    return objc_getAssociatedObject(owner, &BHTLiquidGlassStateKey);
}
