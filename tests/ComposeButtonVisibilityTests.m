static void testComposeButtonVisibility(void) {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    id previous = [defaults objectForKey:@"hide_compose_button"];
    [defaults setBool:YES forKey:@"hide_compose_button"];
    TFNFloatingActionButton* unrelated = [TFNFloatingActionButton new];
    unrelated.hidden = NO;
    NSCAssert(!unrelated.hidden, @"An unregistered floating button remains native");
    BHTComposeOwnerFixture* owner = [BHTComposeOwnerFixture new];
    TFNFloatingActionButton* button = [TFNFloatingActionButton new];
    button.userInteractionEnabled = YES;
    owner.floatingActionButton = button;
    BHTTrackComposeButtonOwner(owner);
    NSCAssert(button.hidden && !button.userInteractionEnabled && button.accessibilityElementsHidden,
        @"The compose preference hides visuals, touch targets and accessibility descendants");
    button.hidden = NO;
    NSCAssert(button.hidden, @"A native show request cannot undo the preference");
    for (NSUInteger pass = 0; pass < 1000; pass++) BHTTrackComposeButtonOwner(owner);
    [defaults setBool:NO forKey:@"hide_compose_button"];
    BHTRefreshComposeButtonVisibility();
    NSCAssert(!button.hidden && button.userInteractionEnabled && !button.accessibilityElementsHidden,
        @"Turning it off restores the latest native visibility and interaction");
    [defaults setBool:YES forKey:@"hide_compose_button"];
    BHTTrackComposeButtonOwner(owner);
    button.hidden = YES;
    [defaults setBool:NO forKey:@"hide_compose_button"];
    BHTRefreshComposeButtonVisibility();
    NSCAssert(button.hidden, @"A deliberate native hide remains hidden when the preference is disabled");
    button.hidden = NO;
    NSCAssert(!button.hidden, @"Native show requests work normally when the preference is disabled");
    [defaults setBool:YES forKey:@"hide_compose_button"];
    owner.floatingActionButton = [TFNFloatingActionButton new];
    BHTTrackComposeButtonOwner(owner);
    button.hidden = NO;
    NSCAssert(!button.hidden && owner.floatingActionButton.hidden, @"Replacement buttons are tracked; stale objects cannot inherit ownership");
    if (previous) [defaults setObject:previous forKey:@"hide_compose_button"];
    else [defaults removeObjectForKey:@"hide_compose_button"];
    NSLog(@"PASS: production compose visibility scoping, native show suppression, repeat refresh, restoration, deliberate hides and replacement isolation");
}
