static BOOL BHTTestNativeGlassAvailable = NO;
BOOL BHTNativeLiquidGlassAvailable(void) { return BHTTestNativeGlassAvailable; }

static void testLiquidGlassPolicy(void) {
    NSCAssert(BHTLiquidGlassNavigationOverride(NO, NO, YES) == nil, @"Default preserves the account rollout decision");
    NSCAssert([BHTLiquidGlassNavigationOverride(YES, NO, YES) isEqual:@YES], @"Explicit opt-in requests native glass");
    NSCAssert(BHTLiquidGlassNavigationOverride(YES, NO, NO) == nil, @"Older UIKit is not forced into an unsupported native pipeline");
    NSCAssert([BHTLiquidGlassNavigationOverride(NO, YES, YES) isEqual:@NO], @"Classic remains an explicit fallback");
    NSCAssert([BHTLiquidGlassNavigationOverride(YES, YES, YES) isEqual:@YES], @"Imported conflicting preferences have deterministic priority");
    CGRect phone = BHTLiquidGlassFrame(CGRectMake(0, 0, 440, 49), NO);
    NSCAssert(CGRectEqualToRect(phone, CGRectMake(12, 2, 416, 45)), @"The floating material fits within the existing phone row");
    CGRect rail = BHTLiquidGlassFrame(CGRectMake(0, 0, 90, 1000), YES);
    NSCAssert(CGRectEqualToRect(rail, CGRectMake(8, 10, 74, 980)), @"The iPad rail uses its native vertical layout");
    CGRect narrow = BHTLiquidGlassFrame(CGRectMake(30, 20, 42, 44), NO);
    NSCAssert(CGRectEqualToRect(narrow, CGRectMake(30, 20, 42, 44)), @"Small windows do not create a negative material frame");
    NSCAssert(CGRectIsEmpty(BHTLiquidGlassFrame(CGRectZero, NO)), @"Zero-size transitions are skipped");
    CGRect highlight = BHTLiquidGlassSelectionFrame(CGRectMake(0, 0, 110, 49), phone);
    NSCAssert(CGRectContainsRect(phone, highlight), @"The selection stays inside the floating material");
    NSCAssert(CGRectIsEmpty(BHTLiquidGlassSelectionFrame(CGRectMake(800, 0, 50, 49), phone)), @"Offscreen items do not produce a selection");
    for (NSUInteger pass = 0; pass < 1000; pass++) {
        NSCAssert(CGRectEqualToRect(BHTLiquidGlassFrame(CGRectMake(0, 0, 440, 49), NO), phone),
                  @"Repeated native layouts never accumulate an inset");
    }
    NSLog(@"PASS: Liquid Glass opt-in, older-system fallback, classic priority, phone/rail geometry and stable repeated layout");
}
