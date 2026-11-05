static BOOL BHTTestNativeGlassAvailable = NO;
BOOL BHTNativeLiquidGlassAvailable(void) { return BHTTestNativeGlassAvailable; }

static void testLiquidGlassPolicy(void) {
    NSCAssert(BHTLiquidGlassNavigationOverride(NO, NO, YES) == nil, @"Default preserves the account rollout decision");
    NSCAssert([BHTLiquidGlassNavigationOverride(YES, NO, YES) isEqual:@NO], @"The custom dock uses the verified entry pipeline");
    NSCAssert([BHTLiquidGlassNavigationOverride(YES, NO, NO) isEqual:@NO], @"The custom dock also supports an older-system material fallback");
    NSCAssert([BHTLiquidGlassNavigationOverride(NO, YES, YES) isEqual:@NO], @"Classic remains an explicit fallback");
    NSCAssert([BHTLiquidGlassNavigationOverride(YES, YES, YES) isEqual:@NO], @"Imported preferences retain the custom dock pipeline");
    CGRect phone = BHTGlassDockFrame(CGRectMake(0, 873, 440, 49), CGRectMake(0, 0, 440, 956), 34, 4, NO, NO);
    NSCAssert(CGRectEqualToRect(phone, CGRectMake(74, 854, 292, 58)), @"A compact dock floats above the safe area");
    CGRect compact = BHTGlassDockFrame(CGRectMake(0, 0, 440, 49), CGRectMake(0, 0, 440, 83), 34, 4, NO, NO);
    NSCAssert(CGRectEqualToRect(compact, CGRectMake(74, 0, 292, 49)), @"A small host retains hittable controls");
    CGRect landscape = BHTGlassDockFrame(CGRectMake(0, 321, 844, 49), CGRectMake(0, 0, 844, 390), 21, 4, NO, NO);
    NSCAssert(CGRectGetMaxY(landscape) <= 369 && CGRectGetWidth(landscape) == 292, @"Landscape respects its safe area");
    CGRect rail = BHTGlassDockFrame(CGRectMake(0, 80, 90, 850), CGRectMake(0, 0, 1366, 1024), 0, 4, YES, NO);
    NSCAssert(CGRectEqualToRect(rail, CGRectMake(6, 373, 78, 264)), @"The iPad uses a vertical dock");
    NSCAssert(CGRectIsEmpty(BHTGlassDockFrame(CGRectZero, CGRectZero, 0, 4, NO, NO)), @"Zero-size transitions are skipped");
    NSCAssert(CGRectIsEmpty(BHTGlassDockFrame(CGRectMake(0, 0, 80, 35), CGRectMake(0, 0, 80, 35), 0, 4, NO, NO)), @"An undersized host retains native controls");
    CGSize many = BHTGlassDockContentSize(CGSizeMake(408, 58), 12, NO);
    NSCAssert(many.width == 640, @"Large tab sets scroll instead of shrinking touch targets");
    for (NSUInteger i = 0; i < 12; i++) {
        CGRect item = BHTGlassDockItemFrame(CGSizeMake(408, 58), i, 12, NO);
        NSCAssert(item.size.width >= 44 && item.size.height >= 44, @"Every control keeps an accessible hit area");
    }
    for (NSUInteger pass = 0; pass < 1000; pass++) {
        NSCAssert(CGRectEqualToRect(BHTGlassDockFrame(CGRectMake(0, 873, 440, 49), CGRectMake(0, 0, 440, 956), 34, 4, NO, NO), phone),
                  @"Repeated native layouts never accumulate an inset");
    }
    NSCAssert([BHTGlassDockSymbol(@"home", YES) isEqualToString:@"house.fill"], @"Selected Home uses the filled symbol");
    NSCAssert([BHTGlassDockSymbol(@"guide", YES) isEqualToString:@"magnifyingglass"], @"Search uses a valid symbol");
    NSLog(@"PASS: owned dock policy, phone/rail/landscape geometry, minimum hit areas, scrolling tabs and stable layout");
}
