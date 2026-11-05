static void testLiquidGlassRestoration(void) {
    NSObject* owner = [NSObject new];
    BHTGlassChromeState* state = [BHTGlassChromeState new];
    state.savedViews = [NSMutableArray array];
    state.material = [UIView new];
    UIView* host = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 440, 83)];
    UIView* native = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 440, 49)];
    UIColor* original = [UIColor new];
    native.backgroundColor = original;
    native.opaque = YES;
    native.userInteractionEnabled = YES;
    [host addSubview:state.material];
    objc_setAssociatedObject(owner, &BHTLiquidGlassStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (NSUInteger pass = 0; pass < 1000; pass++) BHTGlassClearView(state, native, NO);
    NSCAssert(state.savedViews.count == 1 && native.backgroundColor == UIColor.clearColor && !native.opaque,
              @"Repeated refreshes reuse one native-view snapshot");
    NSCAssert(CGRectEqualToRect(native.frame, CGRectMake(0, 0, 440, 49)), @"The glass treatment leaves native tab frames unchanged");
    BHTGlassPassThrough(state, native);
    NSCAssert(!native.userInteractionEnabled, @"The invisible native bar cannot intercept timeline touches");
    UIView* divider = [UIView new];
    BHTGlassClearView(state, divider, YES);
    UIView* alreadyHidden = [UIView new];
    alreadyHidden.hidden = YES;
    BHTGlassClearView(state, alreadyHidden, YES);
    BHTGlassRestore(owner);
    NSCAssert(native.backgroundColor == original && native.opaque, @"Disabling restores the original background and opacity");
    NSCAssert(native.userInteractionEnabled, @"Disabling restores native bar interaction");
    NSCAssert(!divider.hidden && alreadyHidden.hidden, @"Disabling preserves originally hidden native decorations");
    NSCAssert(!state.material.superview && !BHTGlassState(owner, NO), @"Disabling removes the material and releases owned state");
    BHTGlassRestore(owner);
    state.savedViews = [NSMutableArray array];
    objc_setAssociatedObject(owner, &BHTLiquidGlassStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BHTGlassClearView(state, native, NO);
    UIColor* newer = [UIColor new];
    native.backgroundColor = newer;
    BHTGlassClearView(state, native, NO);
    BHTGlassRestore(owner);
    NSCAssert(native.backgroundColor == newer, @"A native theme refresh becomes the restoration baseline");
    state.savedViews = [NSMutableArray array];
    objc_setAssociatedObject(owner, &BHTLiquidGlassStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BHTGlassClearView(state, native, NO);
    native.backgroundColor = original;
    BHTGlassRestore(owner);
    NSCAssert(native.backgroundColor == original, @"A newer native background is not overwritten while restoring");
    state.savedViews = [NSMutableArray array];
    UIView* fullHost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 440, 956)];
    UIView* stockRoot = [[UIView alloc] initWithFrame:CGRectMake(0, 873, 440, 83)];
    UIView* privateFill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 440, 83)];
    privateFill.backgroundColor = original;
    privateFill.opaque = YES;
    [stockRoot addSubview:privateFill];
    [stockRoot addSubview:native];
    [fullHost addSubview:stockRoot];
    [fullHost addSubview:state.material];
    objc_setAssociatedObject(owner, &BHTLiquidGlassStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (NSUInteger pass = 0; pass < 1000; pass++) BHTGlassClearView(state, stockRoot, YES);
    NSCAssert(stockRoot.hidden && [privateFill isDescendantOfView:stockRoot],
        @"Hiding the native root suppresses private fills while retaining its hierarchy");
    NSCAssert(!state.material.hidden && state.material.superview == fullHost &&
        ![state.material isDescendantOfView:stockRoot], @"The floating controls remain outside the hidden stock tree");
    NSCAssert(native.superview == stockRoot && CGRectGetHeight(stockRoot.frame) == 83,
        @"Hiding does not replace native routing objects or manually rewrite layout frames");
    BHTGlassRestore(owner);
    NSCAssert(!stockRoot.hidden && privateFill.backgroundColor == original && native.superview == stockRoot,
        @"Disabling restores the entire stock tree without changing its contents");
    state.savedViews = [NSMutableArray array];
    objc_setAssociatedObject(owner, &BHTLiquidGlassStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    stockRoot.backgroundColor = original;
    stockRoot.opaque = YES;
    BHTGlassClearView(state, stockRoot, NO);
    BHTGlassClearView(state, stockRoot, YES);
    BHTGlassRestore(owner);
    NSCAssert(!stockRoot.hidden && stockRoot.backgroundColor == original && stockRoot.opaque,
        @"A root first seen before reparenting restores both its clear and hidden state");
    NSLog(@"PASS: Liquid Glass repeat-refresh stability, whole stock-tree suppression, sibling dock, reparent/disable restoration and native theme changes");
}
