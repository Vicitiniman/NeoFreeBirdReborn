@interface BHTTabViewFixture : UIView
@property(nonatomic, copy) NSString* title;
@property(nonatomic, getter=isSelected) BOOL selected;
@property(nonatomic, strong) UIImageView* imageView;
@property(nonatomic, strong) UIView* transformContainer;
@end
@implementation BHTTabViewFixture @end

static BHTTabViewFixture* BHTMakeTabFixture(void) {
    BHTTabViewFixture* tab = [[BHTTabViewFixture alloc] initWithFrame:CGRectMake(0, 0, 80, 50)];
    tab.title = @"Home";
    tab.imageView = [[UIImageView alloc] initWithFrame:CGRectMake(28, 14, 24, 24)];
    [tab addSubview:tab.imageView];
    return tab;
}

static NSUInteger BHTDrainTabLayouts(BHTTabViewFixture* tab) {
    NSUInteger passes = 0;
    while (tab.layoutPending && passes < 8) {
        tab.layoutPending = NO;
        BHTPrepareTabViewLayout(tab);
        // X owns icon placement between the prepare and finish hooks.
        BHTLayoutTabViewAppearance(tab);
        passes++;
    }
    NSCAssert(!tab.layoutPending, @"Tab layout must settle instead of blocking startup");
    return passes;
}

static void testTabViewAppearance(void) {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    id previous = [defaults objectForKey:@"restore_tab_labels"];
    [defaults setBool:NO forKey:@"restore_tab_labels"];
    BHTTabViewFixture* tab = BHTMakeTabFixture();
    NSCAssert(BHTDrainTabLayouts(tab) == 1, @"Labels off must finish the first layout");
    NSUInteger requests = tab.layoutRequestCount;
    for (NSUInteger i = 0; i < 100; i++) {
        BHTRefreshTabViewAppearance(tab);
        BHTLayoutTabViewAppearance(tab);
    }
    NSCAssert(tab.layoutRequestCount == requests && tab.subviews.count == 1,
              @"Labels off must not allocate a label or repeatedly invalidate layout");

    [defaults setBool:YES forKey:@"restore_tab_labels"];
    BHTRefreshTabViewAppearance(tab);
    BHTDrainTabLayouts(tab);
    UILabel* label = objc_getAssociatedObject(tab, &BHTTabLabelKey);
    NSCAssert(label && !label.hidden && [label.text isEqualToString:@"Home"],
              @"Enabling labels must create and show one title");
    NSCAssert(tab.subviews.count == 2 && tab.reorderCount == 0,
              @"A label already at the front must not be reordered on every pass");
    CGPoint adjustedCenter = tab.imageView.center;
    requests = tab.layoutRequestCount;
    for (NSUInteger i = 0; i < 100; i++) {
        BHTPrepareTabViewLayout(tab);
        BHTLayoutTabViewAppearance(tab);
        NSCAssert(CGPointEqualToPoint(tab.imageView.center, adjustedCenter),
                  @"Repeated layouts must not accumulate icon shifts");
    }
    NSCAssert(tab.layoutRequestCount == requests, @"Stable visible labels must not request more layouts");

    tab.selected = YES;
    BHTRefreshTabViewAppearance(tab);
    NSCAssert(label.textColor == CurrentAccentColor(), @"Selection still refreshes the label color");
    BHTSetTabViewTitleOverride(tab, @"Likes");
    BHTDrainTabLayouts(tab);
    NSCAssert([label.text isEqualToString:@"Likes"], @"The custom Likes title remains supported");
    requests = tab.layoutRequestCount;
    BHTSetTabViewTitleOverride(tab, @"Likes");
    NSCAssert(tab.layoutRequestCount == requests, @"An unchanged title does not invalidate layout");

    [tab addSubview:[UIView new]];
    BHTDrainTabLayouts(tab);
    NSCAssert(tab.subviews.lastObject == label && tab.reorderCount == 1,
              @"New host subviews require only one label reorder");

    [defaults setBool:NO forKey:@"restore_tab_labels"];
    BHTRefreshTabViewAppearance(tab);
    BHTDrainTabLayouts(tab);
    NSCAssert(label.hidden && CGPointEqualToPoint(tab.imageView.center, CGPointMake(40, 26)),
              @"Disabling labels restores native icon placement");
    requests = tab.layoutRequestCount;
    for (NSUInteger i = 0; i < 100; i++) BHTRefreshTabViewAppearance(tab);
    NSCAssert(tab.layoutRequestCount == requests, @"Hidden retained labels also stay idle");

    [defaults setBool:YES forKey:@"restore_tab_labels"];
    BHTSetTabViewTitleOverride(tab, @"");
    BHTDrainTabLayouts(tab);
    NSCAssert(label.hidden, @"An empty title hides the label without a layout loop");
    BHTSetTabViewTitleOverride(tab, nil);
    BHTDrainTabLayouts(tab);
    NSCAssert(!label.hidden && [label.text isEqualToString:@"Home"], @"Removing an override restores the native title");

    tab.frame = CGRectMake(0, 0, 180, 50);
    tab.imageView.frame = CGRectMake(12, 13, 24, 24);
    [tab setNeedsLayout];
    BHTDrainTabLayouts(tab);
    NSCAssert(label.textAlignment == NSTextAlignmentLeft && CGRectGetMinX(label.frame) == 44,
              @"Wide tab layouts put the label beside the icon");
    BHTRefreshTabViewAppearance(nil);
    BHTLayoutTabViewAppearance(nil);
    if (previous) [defaults setObject:previous forKey:@"restore_tab_labels"];
    else [defaults removeObjectForKey:@"restore_tab_labels"];
    NSLog(@"PASS: production tab layout settles with labels off, on and toggled");
}
