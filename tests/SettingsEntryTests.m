static void testSettingsEntryRoot(void) {
    T1GenericSettingsViewController* root = [T1GenericSettingsViewController new];
    NSCAssert(settingsVCIsRoot(root), @"A settings root outside a UIKit navigation stack must remain reachable");
    UINavigationController* navigation = [UINavigationController new];
    UIViewController* wrapper = [UIViewController new];
    root.navigationController = navigation;
    navigation.viewControllers = @[wrapper, root];
    NSCAssert(settingsVCIsRoot(root), @"A non-settings wrapper can precede the native settings root");
    T1GenericSettingsViewController* child = [T1GenericSettingsViewController new];
    child.navigationController = navigation;
    navigation.viewControllers = @[root, child];
    NSCAssert(!settingsVCIsRoot(child), @"A settings subpage is not another root");
    child.navigationController = nil;
    child.parentViewController = wrapper;
    wrapper.parentViewController = root;
    NSCAssert(!settingsVCIsRoot(child), @"A custom stack's descendant settings page is not a root");
    Class listClass = objc_allocateClassPair(UIViewController.class, "XSettings.SettingsListViewController", 0);
    objc_registerClassPair(listClass);
    UIViewController* list = [listClass new];
    NSCAssert(BHTSettingsEntryIsContainer(list) && BHTSettingsEntryIsRootController(list),
              @"The current XSettings root is recognized without the old settings class");
    UIViewController* nestedList = [listClass new];
    navigation.viewControllers = @[list, nestedList];
    nestedList.navigationController = navigation;
    NSCAssert(!BHTSettingsEntryIsRootController(nestedList), @"A modern settings subpage does not get another entry");
    Class chromeClass = objc_allocateClassPair(UIViewController.class, "T1TwitterSwift.SettingsChromeViewController", 0);
    objc_registerClassPair(chromeClass);
    UIViewController* chrome = [chromeClass new];
    list.parentViewController = chrome;
    NSCAssert(BHTSettingsEntryIsRootController(chrome) && !BHTSettingsEntryIsRootController(list),
              @"An outer settings chrome owner provides one entry for its nested list");
    NSCAssert(!BHTSettingsEntryIsRootController([UIViewController new]), @"Unrelated screens are not settings roots");
    CGFloat nativeTop = 12, top = nativeTop, owned = 0;
    for (NSUInteger pass = 0; pass < 100; pass++) {
        top = BHTSettingsEntryAdditionalTop(top, owned, 80);
        owned = 80;
        NSCAssert(top == 92, @"Repeated layouts must not accumulate safe-area padding");
    }
    top = BHTSettingsEntryAdditionalTop(top, owned, 112);
    NSCAssert(top == nativeTop + 112, @"Larger text changes only the entry's own padding");
    NSCAssert(BHTSettingsEntryRestoredTop(92, 92, 80) == 12, @"Removing an entry restores the native top inset");
    NSCAssert(BHTSettingsEntryRestoredTop(0, 92, 80) == 0, @"A newer native inset is not subtracted a second time");
    NSCAssert(BHTSettingsEntryRestoredTop(70, 70, 80) == -10, @"A preexisting negative native inset is preserved");
    CGRect portrait = BHTSettingsEntryButtonFrame(CGRectMake(0, 0, 390, 844), 168, 0, 0, 80);
    NSCAssert(CGRectEqualToRect(portrait, CGRectMake(16, 92, 358, 72)), @"The entry sits above the adjusted content area");
    CGRect landscape = BHTSettingsEntryButtonFrame(CGRectMake(0, 0, 844, 390), 80, 44, 44, 80);
    NSCAssert(CGRectGetMinX(landscape) == 60 && CGRectGetMaxX(landscape) == 784,
              @"Landscape entry respects both horizontal safe areas");
    CGRect small = BHTSettingsEntryButtonFrame(CGRectMake(0, 0, 20, 40), 0, 0, 0, 0);
    NSCAssert(small.size.width == 0 && small.size.height == 0, @"Zero-size transitions do not produce negative frames");
    CGRect shifted = BHTSettingsEntryButtonFrame(CGRectMake(0, 50, 390, 844), 80, 0, 0, 80);
    NSCAssert(CGRectGetMinY(shifted) == 54, @"Entry geometry respects the root view's bounds origin");
    NSLog(@"PASS: settings roots in UIKit and custom navigation containers");
    NSLog(@"PASS: current settings roots, nested-page exclusion, stable entry insets and rotation geometry");
}
