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
    NSLog(@"PASS: settings roots in UIKit and custom navigation containers");
}
