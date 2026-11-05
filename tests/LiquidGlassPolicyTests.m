static BOOL BHTTestNativeGlassAvailable = NO;
BOOL BHTNativeLiquidGlassAvailable(void) { return BHTTestNativeGlassAvailable; }

static void testLiquidGlassPolicy(void) {
    NSCAssert(BHTLiquidGlassNavigationOverride(NO, NO, YES) == nil, @"Default preserves the account rollout decision");
    NSCAssert([BHTLiquidGlassNavigationOverride(YES, NO, YES) isEqual:@NO], @"The custom dock uses the verified entry pipeline");
    NSCAssert([BHTLiquidGlassNavigationOverride(YES, NO, NO) isEqual:@NO], @"The custom dock also supports an older-system material fallback");
    NSCAssert([BHTLiquidGlassNavigationOverride(NO, YES, YES) isEqual:@NO], @"Classic remains an explicit fallback");
    NSCAssert([BHTLiquidGlassNavigationOverride(YES, YES, YES) isEqual:@NO], @"Imported preferences retain the custom dock pipeline");
    CGRect phone = BHTGlassDockFrame(CGRectMake(0, 873, 440, 49), CGRectMake(0, 0, 440, 956), 34, 4, NO, NO);
    NSCAssert(CGRectEqualToRect(phone, CGRectMake(20, 854, 400, 58)), @"The wide tray spreads its buttons across the phone");
    CGRect compact = BHTGlassDockFrame(CGRectMake(0, 0, 440, 49), CGRectMake(0, 0, 440, 83), 34, 4, NO, NO);
    NSCAssert(CGRectEqualToRect(compact, CGRectMake(20, 0, 400, 49)), @"A small host retains hittable controls");
    CGRect landscape = BHTGlassDockFrame(CGRectMake(0, 321, 844, 49), CGRectMake(0, 0, 844, 390), 21, 4, NO, NO);
    NSCAssert(CGRectGetMaxY(landscape) <= 369 && CGRectGetWidth(landscape) == 600, @"Landscape respects its safe area");
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
    NSCAssert(CGRectEqualToRect(BHTGlassDockCompactFrame(phone, NO), CGRectMake(20, 854, 58, 58)), @"The compact button moves to the leading edge");
    NSCAssert(CGRectEqualToRect(BHTGlassDockCompactFrame(phone, YES), CGRectMake(362, 854, 58, 58)), @"RTL uses the opposite leading edge");
    BHTGlassDockScrollState scroll = {0};
    BHTGlassDockObserveScroll(&scroll, 100, 3000, YES, NO, NO);
    NSCAssert(!BHTGlassDockObserveScroll(&scroll, 150, 3000, YES, NO, NO), @"A short movement keeps the tray available");
    NSCAssert(BHTGlassDockObserveScroll(&scroll, 180, 3000, YES, NO, NO) && scroll.collapsed, @"Scrolling down minimizes navigation");
    NSCAssert(!BHTGlassDockObserveScroll(&scroll, 176, 3000, YES, NO, NO), @"Finger jitter does not expand the button");
    NSCAssert(BHTGlassDockObserveScroll(&scroll, 165, 3000, YES, NO, NO) && !scroll.collapsed, @"Scrolling back reveals the tray");
    BHTGlassDockObserveScroll(&scroll, 245, 3000, YES, NO, NO);
    NSCAssert(scroll.collapsed, @"A subsequent downward gesture can minimize again");
    BHTGlassDockReveal(&scroll, YES);
    BHTGlassDockObserveScroll(&scroll, 330, 3000, NO, YES, NO);
    NSCAssert(!scroll.collapsed, @"Tapping the compact button stays expanded during the remaining inertia");
    BHTGlassDockObserveScroll(&scroll, 410, 3000, YES, NO, NO);
    NSCAssert(!scroll.collapsed && scroll.manuallyExpanded, @"Manual expansion overrides subsequent downward drags");
    BHTGlassDockResetScroll(&scroll, YES);
    BHTGlassDockObserveScroll(&scroll, 100, 3000, YES, NO, NO);
    BHTGlassDockObserveScroll(&scroll, 190, 3000, YES, NO, NO);
    NSCAssert(!scroll.collapsed && scroll.manuallyExpanded, @"A same-page scroll-source replacement preserves manual expansion");
    BHTGlassDockResetScroll(&scroll, NO);
    BHTGlassDockObserveScroll(&scroll, 100, 3000, YES, NO, NO);
    BHTGlassDockObserveScroll(&scroll, 180, 3000, YES, NO, NO);
    NSCAssert(scroll.collapsed && !scroll.manuallyExpanded, @"A new page restores automatic minimization");
    NSCAssert(BHTGlassDockObserveScroll(&scroll, 410, 3000, YES, NO, YES) && !scroll.collapsed, @"Keep-visible overrides minimization");
    BHTGlassDockObserveScroll(&scroll, 490, 3000, NO, NO, NO);
    NSCAssert(!scroll.collapsed, @"Programmatic scrolling cannot minimize the dock");
    BHTGlassDockObserveScroll(&scroll, 600, 3000, YES, NO, NO);
    NSCAssert(scroll.collapsed, @"A real drag may minimize after a programmatic update");
    BHTGlassDockObserveScroll(&scroll, -15, 3000, YES, NO, NO);
    NSCAssert(!scroll.collapsed, @"Returning to the top reveals navigation, including rubber banding");
    scroll.collapsed = YES;
    BHTGlassDockObserveScroll(&scroll, 30, 0, YES, NO, NO);
    NSCAssert(!scroll.collapsed, @"Short pages always show navigation");
    scroll = (BHTGlassDockScrollState){0};
    BHTGlassDockObserveScroll(&scroll, 100, 3000, YES, NO, NO);
    for (NSUInteger pass = 0; pass < 1000; pass++)
        BHTGlassDockObserveScroll(&scroll, 100 + (pass % 2) * 0.2, 3000, YES, NO, NO);
    NSCAssert(!scroll.collapsed, @"Subpixel jitter never accumulates into a collapse");
    CGRect visible = CGRectMake(0, 0, 440, 49);
    CGRect overlay = BHTGlassDockVisibleFrame(visible, YES, NO);
    CGFloat rootHeight = 956, nativeBarOrigin = 873, safeBottom = 34;
    CGFloat reserved = MAX(0, rootHeight - (nativeBarOrigin + CGRectGetMinY(overlay) + safeBottom));
    NSCAssert(overlay.size.height == 0 && reserved == 0, @"Native inset math removes the old bar's reservation");
    NSCAssert(CGRectEqualToRect(BHTGlassDockVisibleFrame(visible, NO, NO), visible), @"Disabling restores the stock reservation");
    NSCAssert(CGRectEqualToRect(BHTGlassDockVisibleFrame(visible, YES, YES), visible), @"An active docked composer retains its native space");
    NSCAssert(CGRectEqualToRect(BHTGlassDockVisibleFrame(CGRectZero, YES, NO), CGRectZero), @"An intentionally hidden native bar stays hidden");
    NSCAssert(BHTGlassDockOpacity(-10, NO) == 0 && BHTGlassDockOpacity(50, NO) == 0.5 && BHTGlassDockOpacity(200, NO) == 1,
        @"Opacity clamps safely while exposing the full clear-to-opaque range");
    NSCAssert(BHTGlassDockOpacity(0, YES) == 1, @"Reduce Transparency overrides the slider");
    CGRect compose = CGRectMake(376, 850, 56, 56);
    CGRect avoided = BHTGlassDockAvoidedComposeFrame(compose, phone);
    NSCAssert(CGRectGetMaxY(avoided) == CGRectGetMinY(phone) - 12 && avoided.size.width == compose.size.width,
        @"An enabled compose button sits above the expanded tray without resizing");
    NSCAssert(CGRectEqualToRect(BHTGlassDockAvoidedComposeFrame(compose, BHTGlassDockCompactFrame(phone, NO)), compose),
        @"A compact button on the other side does not displace compose");
    for (id value in @[@0, @35, @100]) NSCAssert(BHTGlassOpacityPreferenceIsValid(value), @"Valid opacity profiles import");
    for (id value in @[@-1, @101, @0.5, @(NAN), @"35", NSNull.null])
        NSCAssert(!BHTGlassOpacityPreferenceIsValid(value), @"Malformed opacity profiles are rejected");
    NSLog(@"PASS: wide dock geometry, manual expansion across inertia/drags/source replacement, page reset, native inset removal/restoration, docked-content guard and opacity/profile validation");
}
