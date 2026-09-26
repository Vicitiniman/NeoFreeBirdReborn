//
//  Theme.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import "Branding/BHTBranding.h"
#import "Compatibility/BHTCompatibilityReporter.h"
#import "Likes/BHTLikesTab.h"
#import "ThemeColor/BHTThemePresets.h"

// MARK: - Custom accent color

static NSNumber* selectedThemeColor(void) {
    return [NSUserDefaults.standardUserDefaults objectForKey:@"bh_color_theme_selectedColor"];
}

// Every apply path (launch re-apply, trait changes, both settings pickers)
// funnels through this setter, so coercing here keeps the custom color pinned.
%hook TAEColorSettings

- (void)setPrimaryColorOption:(NSInteger)colorOption {
    NSNumber* selectedColor = selectedThemeColor();
    %orig(selectedColor ? selectedColor.integerValue : colorOption);
}

- (NSInteger)primaryColorOption {
    NSNumber* selectedColor = selectedThemeColor();
    return selectedColor ? selectedColor.integerValue : %orig;
}

%end

void applySelectedThemeColor(void) {
    NSNumber* selectedColor = selectedThemeColor();
    if (selectedColor) {
        [[objc_getClass("TAEColorSettings") sharedSettings]
            setPrimaryColorOption:selectedColor.integerValue];
    }
}

// MARK: - Custom tab bar order and visibility

static NSString* scribePageForEntry(id<T1AppNavigationTabEntry> entry) {
    if (![entry respondsToSelector:@selector(tabView)]) {
        return nil;
    }
    return [entry tabView].scribePage;
}

// Operates on the tab ENTRIES, not the button views: the app derives both the
// buttons and their content view controllers from this one array.
static NSArray* orderedTabEntries(NSArray* entries) {
    entries = BHTEntriesByInstallingLikesDestination(entries);
    BHTRecordNavigationEntryClasses(entries);

    // Record the underlying tab views so the editor can show real titles and icons.
    NSMutableArray* tabViews = [NSMutableArray new];
    for (id<T1AppNavigationTabEntry> entry in entries) {
        T1TabView* tabView = [entry respondsToSelector:@selector(tabView)] ? [entry tabView] : nil;
        if (tabView) {
            [tabViews addObject:tabView];
        }
    }
    [CustomTabBarUtility recordTabViews:tabViews];

    NSArray<NSString*>* savedVisibleOrder =
        [CustomTabBarUtility visiblePageIDsInOrder];
    BOOL hasCustomOrder = savedVisibleOrder != nil;
    NSMutableArray<NSString*>* visibleOrder =
        [(savedVisibleOrder ?: [CustomTabBarUtility defaultVisiblePageIDs])
            mutableCopy];
    BOOL likesEnabled = [CustomTabBarUtility likesTabEnabled];
    NSUInteger likesIndex = [visibleOrder indexOfObject:BHTLikesPageID()];
    if (likesEnabled) {
        // Likes is its own entry. Keep Grok exactly where the user placed it
        // and add Likes to the default layout without replacing any native tab.
        if (!hasCustomOrder && likesIndex == NSNotFound) {
            [visibleOrder addObject:BHTLikesPageID()];
        }
    } else if (likesIndex != NSNotFound) {
        [visibleOrder removeObjectAtIndex:likesIndex];
    }

    NSMutableDictionary<NSString*, id>* entriesByPage = [NSMutableDictionary new];
    for (id<T1AppNavigationTabEntry> entry in entries) {
        NSString* page = scribePageForEntry(entry);
        if (page && !entriesByPage[page]) {
            entriesByPage[page] = entry;
        }
    }

    // Not customised yet: show the default set (Home, Search, Notifications, Chats)
    // in that order, hiding everything else the app builds.
    if (!hasCustomOrder) {
        NSMutableArray* defaultEntries = [NSMutableArray new];
        for (NSString* pageID in visibleOrder) {
            id entry = entriesByPage[pageID];
            if (entry) {
                [defaultEntries addObject:entry];
            }
        }
        return defaultEntries;
    }

    // Only the chosen tabs show; anything the editor hasn't been told to show
    // (including tabs unlocked after the user last saved) stays hidden.
    NSMutableArray* orderedEntries = [NSMutableArray new];
    NSMutableSet* placed = [NSMutableSet new];
    for (NSString* pageID in visibleOrder) {
        id entry = entriesByPage[pageID];
        if (entry && ![placed containsObject:pageID]) {
            [orderedEntries addObject:entry];
            [placed addObject:pageID];
        }
    }

    return orderedEntries;
}

// The single ordered spine that feeds both the tab buttons and their content, so
// filtering/reordering here keeps taps mapped to the right panel.
%hook T1TabbedAppNavigationViewController

- (void)setVisibleTabEntries:(NSArray*)entries {
    %orig(orderedTabEntries(entries));
}

%end

// MARK: - Theme tab items without defeating X's native collapse

static char kBHTOriginalNativeTabBarAppearanceKey;
static char kBHTNativeTabBarRestoreInProgressKey;
static char kBHTLastNativeTabBarAccentKey;
static char kBHTLastNativeTabBarSecondaryTextKey;
static char kBHTTabChromeAppliedGenerationKey;
static char kBHTTabChromeNativeBarIdentityKey;
static NSUInteger BHTTabChromeThemeGeneration = 1;

static id BHTThemeSafeValue(id object, NSString* key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

static UITabBarAppearance* BHTThemedTabBarAppearance(
    UITabBarAppearance* source, UIColor* accent,
    UIColor* secondaryText) {
    UITabBarAppearance* appearance =
        [source isKindOfClass:UITabBarAppearance.class]
            ? [source copy]
            : [UITabBarAppearance new];
    // Preserve X's backgroundEffect, background color, and transparency. X
    // collapses the item/content layer while keeping its structural tab host
    // mounted; forcing an opaque background here leaves an empty strip behind.
    for (UITabBarItemAppearance* itemAppearance in @[
             appearance.stackedLayoutAppearance,
             appearance.inlineLayoutAppearance,
             appearance.compactInlineLayoutAppearance
         ]) {
        itemAppearance.normal.iconColor = secondaryText;
        NSMutableDictionary* normalAttributes =
            [itemAppearance.normal.titleTextAttributes
                mutableCopy] ?: [NSMutableDictionary dictionary];
        normalAttributes[NSForegroundColorAttributeName] =
            secondaryText;
        itemAppearance.normal.titleTextAttributes =
            normalAttributes;
        itemAppearance.selected.iconColor = accent;
        NSMutableDictionary* selectedAttributes =
            [itemAppearance.selected.titleTextAttributes
                mutableCopy] ?: [NSMutableDictionary dictionary];
        selectedAttributes[NSForegroundColorAttributeName] =
            accent;
        itemAppearance.selected.titleTextAttributes =
            selectedAttributes;
    }
    return appearance;
}

static BOOL BHTNativeTabBarStillMatches(UITabBar* tabBar);

static void BHTApplyThemeToNativeTabBar(
    UITabBar* tabBar, BOOL themed, UIColor* accent,
    UIColor* secondaryText) {
    if (!tabBar) return;
    NSDictionary* original =
        objc_getAssociatedObject(
            tabBar, &kBHTOriginalNativeTabBarAppearanceKey);
    if (!themed) {
        if (!original) return;
        // Preserve a fresher native light/dark restoration if X already
        // replaced our item appearance.
        if (BHTNativeTabBarStillMatches(tabBar)) {
            id standard = original[@"standard"];
            id scrollEdge = original[@"scrollEdge"];
            id tintColor = original[@"tintColor"];
            id unselectedColor = original[@"unselectedColor"];
            tabBar.standardAppearance =
                standard == NSNull.null ? nil : standard;
            tabBar.scrollEdgeAppearance =
                scrollEdge == NSNull.null ? nil : scrollEdge;
            tabBar.tintColor =
                tintColor == NSNull.null ? nil : tintColor;
            tabBar.unselectedItemTintColor =
                unselectedColor == NSNull.null
                    ? nil
                    : unselectedColor;
        }
        objc_setAssociatedObject(
            tabBar, &kBHTOriginalNativeTabBarAppearanceKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            tabBar, &kBHTLastNativeTabBarAccentKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            tabBar, &kBHTLastNativeTabBarSecondaryTextKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (!original) {
        original = @{
            @"standard":
                tabBar.standardAppearance ?: NSNull.null,
            @"scrollEdge":
                tabBar.scrollEdgeAppearance ?: NSNull.null,
            @"tintColor":
                tabBar.tintColor ?: NSNull.null,
            @"unselectedColor":
                tabBar.unselectedItemTintColor ?: NSNull.null
        };
        objc_setAssociatedObject(
            tabBar, &kBHTOriginalNativeTabBarAppearanceKey,
            original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UITabBarAppearance* standardSource =
        [tabBar.standardAppearance
            isKindOfClass:UITabBarAppearance.class]
            ? tabBar.standardAppearance
            : nil;
    UITabBarAppearance* scrollEdgeSource =
        [tabBar.scrollEdgeAppearance
            isKindOfClass:UITabBarAppearance.class]
            ? tabBar.scrollEdgeAppearance
            : standardSource;
    tabBar.standardAppearance =
        BHTThemedTabBarAppearance(
            standardSource, accent, secondaryText);
    tabBar.scrollEdgeAppearance =
        BHTThemedTabBarAppearance(
            scrollEdgeSource, accent, secondaryText);
    tabBar.tintColor = accent;
    tabBar.unselectedItemTintColor = secondaryText;
    objc_setAssociatedObject(
        tabBar, &kBHTLastNativeTabBarAccentKey,
        accent, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(
        tabBar, &kBHTLastNativeTabBarSecondaryTextKey,
        secondaryText, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL BHTTabBarItemAppearanceMatches(
    UITabBarItemAppearance* itemAppearance, UIColor* accent,
    UIColor* secondaryText) {
    UIColor* normalTitle =
        itemAppearance.normal
            .titleTextAttributes[
                NSForegroundColorAttributeName];
    UIColor* selectedTitle =
        itemAppearance.selected
            .titleTextAttributes[
                NSForegroundColorAttributeName];
    return (!secondaryText ||
            ([itemAppearance.normal.iconColor
                 isEqual:secondaryText] &&
             [normalTitle isEqual:secondaryText])) &&
           (!accent ||
            ([itemAppearance.selected.iconColor
                 isEqual:accent] &&
             [selectedTitle isEqual:accent]));
}

static BOOL BHTTabBarAppearanceMatches(
    UITabBarAppearance* appearance, UIColor* accent,
    UIColor* secondaryText) {
    return BHTTabBarItemAppearanceMatches(
               appearance.stackedLayoutAppearance,
               accent, secondaryText) &&
           BHTTabBarItemAppearanceMatches(
               appearance.inlineLayoutAppearance,
               accent, secondaryText) &&
           BHTTabBarItemAppearanceMatches(
               appearance.compactInlineLayoutAppearance,
               accent, secondaryText);
}

static BOOL BHTNativeTabBarStillMatches(UITabBar* tabBar) {
    if (!tabBar) return YES;
    UIColor* accent = objc_getAssociatedObject(
        tabBar, &kBHTLastNativeTabBarAccentKey);
    UIColor* secondaryText = objc_getAssociatedObject(
        tabBar, &kBHTLastNativeTabBarSecondaryTextKey);
    if (!accent && !secondaryText) return YES;
    return BHTTabBarAppearanceMatches(
               tabBar.standardAppearance, accent,
               secondaryText) &&
           BHTTabBarAppearanceMatches(
               tabBar.scrollEdgeAppearance, accent,
               secondaryText) &&
           (!accent || [tabBar.tintColor isEqual:accent]) &&
           (!secondaryText ||
            [tabBar.unselectedItemTintColor
                isEqual:secondaryText]);
}

static void BHTApplyCurrentThemeToTabBarController(
    T1TabBarViewController* controller, BOOL force) {
    if (!controller || !controller.isViewLoaded) return;

    id tabView = BHTThemeSafeValue(controller, @"tabBar");
    id nativeBarValue =
        BHTThemeSafeValue(controller, @"nativeTabBar");
    UITabBar* nativeTabBar =
        [nativeBarValue isKindOfClass:UITabBar.class]
            ? nativeBarValue
            : ([tabView isKindOfClass:UITabBar.class]
                   ? tabView
                   : nil);
    NSNumber* appliedGeneration =
        objc_getAssociatedObject(
            controller, &kBHTTabChromeAppliedGenerationKey);
    BOOL identitiesUnchanged =
        objc_getAssociatedObject(
            controller, &kBHTTabChromeNativeBarIdentityKey) ==
            nativeTabBar;
    BOOL colorsUnchanged =
        BHTNativeTabBarStillMatches(nativeTabBar);
    if (!force && identitiesUnchanged &&
        colorsUnchanged &&
        appliedGeneration.unsignedIntegerValue ==
            BHTTabChromeThemeGeneration) {
        return;
    }

    BOOL themed = [Palette
        customThemeColorForRole:BHTThemeColorBackgroundKey] != nil;
    UIColor* secondaryText = [Palette currentSecondaryTextColor];
    UIColor* accent = [Palette
        customThemeColorForRole:BHTThemeColorAccentKey] ?:
        CurrentAccentColor() ?: UIColor.systemBlueColor;

    BOOL hadNativeOverride =
        nativeTabBar &&
        objc_getAssociatedObject(
            nativeTabBar,
            &kBHTOriginalNativeTabBarAppearanceKey) != nil;
    BHTApplyThemeToNativeTabBar(
        nativeTabBar, themed, accent, secondaryText);
    if (!themed && hadNativeOverride &&
        ![objc_getAssociatedObject(
            controller,
            &kBHTNativeTabBarRestoreInProgressKey) boolValue]) {
        SEL selector =
            NSSelectorFromString(@"_t1_configureNativeTabBar");
        Method method =
            class_getInstanceMethod(
                object_getClass(controller), selector);
        char returnType[16] = {0};
        if ([controller respondsToSelector:selector] && method &&
            method_getNumberOfArguments(method) == 2) {
            method_getReturnType(
                method, returnType, sizeof(returnType));
            if (returnType[0] == 'v') {
                objc_setAssociatedObject(
                    controller,
                    &kBHTNativeTabBarRestoreInProgressKey, @YES,
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                @try {
                    ((void (*)(id, SEL))objc_msgSend)(
                        controller, selector);
                } @catch (__unused NSException* exception) {
                }
                objc_setAssociatedObject(
                    controller,
                    &kBHTNativeTabBarRestoreInProgressKey, nil,
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }

    objc_setAssociatedObject(
        controller, &kBHTTabChromeNativeBarIdentityKey,
        nativeTabBar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(
        controller, &kBHTTabChromeAppliedGenerationKey,
        @(BHTTabChromeThemeGeneration),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void BHTRefreshCurrentThemeTabItems(
    T1TabBarViewController* controller) {
    id value = BHTThemeSafeValue(controller, @"tabViews");
    if (![value isKindOfClass:NSArray.class]) return;
    SEL imageSelector =
        NSSelectorFromString(@"_t1_updateImageViewAnimated:");
    SEL titleSelector =
        NSSelectorFromString(@"_t1_updateTitleLabel");
    for (id tabView in (NSArray*)value) {
        Method imageMethod =
            class_getInstanceMethod([tabView class], imageSelector);
        char imageReturnType[16] = {0};
        char animatedType[16] = {0};
        if ([tabView respondsToSelector:imageSelector] &&
            imageMethod &&
            method_getNumberOfArguments(imageMethod) == 3) {
            method_getReturnType(
                imageMethod, imageReturnType,
                sizeof(imageReturnType));
            method_getArgumentType(
                imageMethod, 2, animatedType,
                sizeof(animatedType));
            if (imageReturnType[0] == 'v' &&
                (animatedType[0] == 'c' ||
                 animatedType[0] == 'B')) {
                @try {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(
                        tabView, imageSelector, NO);
                } @catch (__unused NSException* exception) {
                }
            }
        }

        Method titleMethod =
            class_getInstanceMethod([tabView class], titleSelector);
        char titleReturnType[16] = {0};
        if ([tabView respondsToSelector:titleSelector] &&
            titleMethod &&
            method_getNumberOfArguments(titleMethod) == 2) {
            method_getReturnType(
                titleMethod, titleReturnType,
                sizeof(titleReturnType));
            if (titleReturnType[0] == 'v') {
                @try {
                    ((void (*)(id, SEL))objc_msgSend)(
                        tabView, titleSelector);
                } @catch (__unused NSException* exception) {
                }
            }
        }
    }
}

static NSHashTable* BHTThemedTabBarControllers(void) {
    static NSHashTable* controllers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controllers = [NSHashTable weakObjectsHashTable];
    });
    return controllers;
}

static void BHTTrackThemedTabBarController(
    T1TabBarViewController* controller) {
    if (!controller) return;
    NSHashTable* controllers = BHTThemedTabBarControllers();
    @synchronized(controllers) {
        [controllers addObject:controller];
    }
    static dispatch_once_t observerToken;
    dispatch_once(&observerToken, ^{
        NSNotificationCenter* center =
            NSNotificationCenter.defaultCenter;
        for (NSString* name in @[
                 BHTThemeDidChangeNotification,
                 BHTSettingsProfileDidApplyNotification
             ]) {
            [center
                addObserverForName:name
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(
                            __unused NSNotification* notification) {
                BHTTabChromeThemeGeneration++;
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSArray* snapshot = nil;
                    @synchronized(controllers) {
                        snapshot = controllers.allObjects;
                    }
                    for (T1TabBarViewController* tracked
                         in snapshot) {
                        BHTApplyCurrentThemeToTabBarController(
                            tracked, NO);
                        BHTRefreshCurrentThemeTabItems(
                            tracked);
                    }
                });
            }];
        }
    });
}

static BOOL shouldPinCollapsibleTabBar(
    T1TabBarViewController* controller) {
    if (![BHTSettings boolForKey:@"no_tab_bar_hiding"]) {
        return NO;
    }

    UIUserInterfaceIdiom idiom =
        controller.traitCollection.userInterfaceIdiom;
    if (idiom == UIUserInterfaceIdiomUnspecified) {
        idiom = UIDevice.currentDevice.userInterfaceIdiom;
    }

    // On iPad the same "collapse ratio" drives the vertical rail between its
    // compact and expanded widths; it is not the phone's scroll-to-hide
    // animation. Pinning that value locks the rail in its narrow icon-only
    // state and can fight X's split-view relayouts. The iPad rail already stays
    // on-screen, so preserve its native expansion state.
    return idiom != UIUserInterfaceIdiomPad;
}

%hook T1TabBarViewController

- (void)viewDidLoad {
    %orig;
    BHTTrackThemedTabBarController(self);
    BHTApplyCurrentThemeToTabBarController(self, YES);
    BHTRefreshCurrentThemeTabItems(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    BHTApplyCurrentThemeToTabBarController(self, NO);
}

- (void)traitCollectionDidChange:
    (UITraitCollection*)previousTraits {
    %orig(previousTraits);
    BHTApplyCurrentThemeToTabBarController(self, YES);
    BHTRefreshCurrentThemeTabItems(self);
}

// X 12.9 consults these capabilities before sending collapse-ratio updates.
- (BOOL)tfn_supportsTabBarCollapsing {
    return shouldPinCollapsibleTabBar(self) ? NO : %orig;
}

- (BOOL)tfn_prefersTabBarPinned {
    return shouldPinCollapsibleTabBar(self) ? YES : %orig;
}

// The scroll-driven hide only reaches the tab bar as a collapse ratio, so
// clamping it spares the deliberate hides (fullscreen media, immersive player).
- (void)setTabBarCollapseRatio:(double)ratio {
    if (shouldPinCollapsibleTabBar(self)) {
        %orig(0.0);
    } else {
        %orig(ratio);
    }
}

%end

// MARK: - Tab bar icon and label theming

static BOOL updatingTabIconColor = NO;

static UIColor* tabItemColor(BOOL selected) {
    return selected ? CurrentAccentColor()
                    : [Palette currentSecondaryTextColor];
}

static BOOL BHTShouldThemeTabItems(void) {
    return [BHTSettings boolForKey:@"tab_bar_theming"] ||
           [Palette
               customThemeColorForRole:
                   BHTThemeColorBackgroundKey] != nil;
}

%hook T1TabView

- (void)_t1_updateImageViewAnimated:(BOOL)animated {
    // setIconColor: re-enters this method, so swallow the inner call and let
    // %orig below render once with the new color
    if (updatingTabIconColor) {
        return;
    }

    updatingTabIconColor = YES;
    if (BHTShouldThemeTabItems()) {
        self.iconColor = tabItemColor(self.selected);
    } else if (self.iconColor) {
        self.iconColor = nil;
    }
    updatingTabIconColor = NO;

    %orig(animated);
}

- (void)_t1_updateTitleLabel {
    %orig;

    if (BHTShouldThemeTabItems()) {
        self.titleLabel.textColor = tabItemColor(self.selected);
    }
}

- (BOOL)showsTitleInDisplayMode:(long long)displayMode {
    if ([BHTSettings boolForKey:@"restore_tab_labels"]) {
        return YES;
    }
    return %orig;
}

%new
- (void)applyCurrentThemeToIcon {
    [self _t1_updateImageViewAnimated:NO];
    [self _t1_updateTitleLabel];
}

%end

// MARK: - Home and iPad rail branding

static char kBHTOriginalRailLogoImageKey;
static char kBHTOriginalRailLogoTintKey;
static char kBHTOriginalRailLogoContentModeKey;
static char kBHTOriginalRailLogoAccessibilityLabelKey;
static char kBHTOriginalRailLogoStateCapturedKey;
static char kBHTRailDeferredUpdatePendingKey;
static char kBHTRailResolvedLogoViewKey;

static BOOL BHTUsesPadNavigation(UITraitCollection* traits) {
    UIUserInterfaceIdiom idiom = traits.userInterfaceIdiom;
    if (idiom == UIUserInterfaceIdiomUnspecified) {
        idiom = UIDevice.currentDevice.userInterfaceIdiom;
    }
    return idiom == UIUserInterfaceIdiomPad;
}

static NSHashTable<UIImageView*>* BHTBrandedLogoViews(void) {
    static NSHashTable* views = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        views = [NSHashTable weakObjectsHashTable];
    });
    return views;
}

static void BHTApplyCurrentBirdToImageView(UIImageView* imageView) {
    if (!imageView) return;
    BHTApplyTwitterBirdToImageView(imageView, CurrentAccentColor());
    [BHTBrandedLogoViews() addObject:imageView];
}

static void BHTInstallBrandingThemeObserver(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (NSString* name in @[
                 BHTThemeDidChangeNotification,
                 BHTSettingsProfileDidApplyNotification
             ]) {
            [NSNotificationCenter.defaultCenter
                addObserverForName:name
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(
                            __unused NSNotification* notification) {
                if (![BHTSettings
                        boolForKey:
                            @"color_twitter_icon_in_top_bar"]) {
                    return;
                }
                UIColor* accent = CurrentAccentColor();
                for (UIImageView* imageView
                     in BHTBrandedLogoViews().allObjects) {
                    BHTApplyTwitterBirdToImageView(imageView, accent);
                }
            }];
        }
    });
}

static BOOL BHTRailHeaderCandidateIsVisible(UIView* candidate,
                                            UIView* hostView) {
    for (UIView* current = candidate; current;
         current = current.superview) {
        if (current.hidden || current.alpha <= 0.01) return NO;
        if (current == hostView) break;
    }
    return YES;
}

static BOOL BHTRailHeaderCandidateBelongsToTab(UIView* candidate,
                                               UIView* hostView) {
    Class tabViewClass = NSClassFromString(@"T1TabView");
    if (!tabViewClass) return NO;
    for (UIView* current = candidate.superview;
         current && current != hostView;
         current = current.superview) {
        if ([current isKindOfClass:tabViewClass]) {
            // The Home house and every other navigation item live inside a
            // T1TabView. The rail header mark does not, so this is a stronger
            // guard than comparing icon pixels or relying on view order.
            return YES;
        }
    }
    return NO;
}

static BOOL BHTIsSafeRailHeaderCandidate(UIImageView* candidate,
                                         UIView* hostView,
                                         CGRect* resolvedFrame) {
    if (!candidate || !hostView ||
        ![candidate isDescendantOfView:hostView] ||
        BHTRailHeaderCandidateBelongsToTab(candidate, hostView) ||
        !BHTRailHeaderCandidateIsVisible(candidate, hostView)) {
        return NO;
    }

    CGRect frame = [candidate convertRect:candidate.bounds toView:hostView];
    if (CGRectIsNull(frame) || CGRectIsInfinite(frame) ||
        CGRectIsEmpty(frame)) {
        return NO;
    }
    CGFloat width = CGRectGetWidth(frame);
    CGFloat height = CGRectGetHeight(frame);
    if (!isfinite(width) || !isfinite(height) ||
        width < 16.0 || height < 16.0 ||
        width > 56.0 || height > 56.0) {
        return NO;
    }
    CGFloat aspectRatio = width / MAX(height, 1.0);
    if (aspectRatio < 0.65 || aspectRatio > 1.35) return NO;

    // X 12.9 placed the mark at {34,35}; X 12.24 moved ownership to the
    // split-sidebar controller and can place it slightly lower. The first
    // T1TabView is explicitly excluded above, so this wider header band still
    // cannot replace the Home house.
    UIEdgeInsets safeAreaInsets = hostView.safeAreaInsets;
    CGFloat headerBottom = MAX(104.0, safeAreaInsets.top + 64.0);
    if (CGRectGetMinY(frame) < -1.0 ||
        CGRectGetMaxY(frame) > headerBottom) {
        return NO;
    }

    CGFloat hostWidth = CGRectGetWidth(hostView.bounds);
    if (hostWidth <= 0.0) return NO;
    CGFloat edgeBand =
        MIN(144.0, MAX(80.0, hostWidth * 0.18));
    UIUserInterfaceLayoutDirection direction =
        [UIView userInterfaceLayoutDirectionForSemanticContentAttribute:
                    hostView.semanticContentAttribute];
    BOOL inRailColumn =
        direction == UIUserInterfaceLayoutDirectionRightToLeft
            ? CGRectGetMinX(frame) >= hostWidth - edgeBand
            : CGRectGetMaxX(frame) <= edgeBand;
    if (!inRailColumn) return NO;

    if (resolvedFrame) *resolvedFrame = frame;
    return YES;
}

static UIImageView* BHTGuardedRailHeaderImageScan(UIView* hostView,
                                                   NSUInteger* matchCount) {
    __block UIImageView* best = nil;
    __block CGFloat bestScore = CGFLOAT_MAX;
    __block NSUInteger matches = 0;
    EnumerateSubviewsRecursively(hostView, ^(UIView* view) {
        if (![view isKindOfClass:UIImageView.class]) return;
        CGRect frame = CGRectZero;
        UIImageView* imageView = (UIImageView*)view;
        if (!BHTIsSafeRailHeaderCandidate(imageView, hostView, &frame)) {
            return;
        }
        matches++;
        CGFloat iconSize =
            (CGRectGetWidth(frame) + CGRectGetHeight(frame)) / 2.0;
        CGFloat edgeDistance =
            MIN(CGRectGetMinX(frame),
                MAX(0.0, CGRectGetWidth(hostView.bounds) -
                             CGRectGetMaxX(frame)));
        CGFloat score = CGRectGetMidY(frame) * 10.0 +
                        fabs(iconSize - 28.0) * 2.0 +
                        edgeDistance;
        if (score < bestScore) {
            bestScore = score;
            best = imageView;
        }
    });
    if (matchCount) *matchCount = matches;
    return best;
}

static UIImageView* BHTRailHeaderLogoImageView(UIView* hostView,
                                               NSString** resolution,
                                               NSUInteger* matchCount) {
    UIImageView* cached =
        objc_getAssociatedObject(hostView,
                                 &kBHTRailResolvedLogoViewKey);
    if (BHTIsSafeRailHeaderCandidate(cached, hostView, NULL)) {
        if (resolution) *resolution = @"cachedGuardedHeader";
        if (matchCount) *matchCount = 1;
        return cached;
    }
    if (cached) {
        objc_setAssociatedObject(
            hostView, &kBHTRailResolvedLogoViewKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // X 12.9 owns the actual iPad header mark in T1TabBarHostView. Resolve its
    // semantic logo property/ivar first.
    SEL selector = NSSelectorFromString(@"logoImageView");
    if ([hostView respondsToSelector:selector]) {
        id candidate = nil;
        @try {
            candidate =
                ((id (*)(id, SEL))objc_msgSend)(hostView, selector);
        } @catch (__unused NSException* exception) {
        }
        if ([candidate isKindOfClass:UIImageView.class] &&
            BHTIsSafeRailHeaderCandidate(candidate, hostView, NULL)) {
            if (resolution) *resolution = @"semanticSelector";
            if (matchCount) *matchCount = 1;
            objc_setAssociatedObject(
                hostView, &kBHTRailResolvedLogoViewKey, candidate,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return candidate;
        }
    }

    for (Class currentClass = hostView.class;
         currentClass && currentClass != UIView.class;
         currentClass = class_getSuperclass(currentClass)) {
        unsigned int ivarCount = 0;
        Ivar* ivars = class_copyIvarList(currentClass, &ivarCount);
        for (unsigned int index = 0; index < ivarCount; index++) {
            Ivar ivar = ivars[index];
            const char* rawName = ivar_getName(ivar);
            const char* encoding = ivar_getTypeEncoding(ivar);
            NSString* name =
                rawName ? [NSString stringWithUTF8String:rawName] : @"";
            if (!encoding || encoding[0] != '@' ||
                [name.lowercaseString rangeOfString:@"logo"].location ==
                    NSNotFound) {
                continue;
            }
            id candidate = nil;
            @try {
                candidate = object_getIvar(hostView, ivar);
            } @catch (__unused NSException* exception) {
            }
            if ([candidate isKindOfClass:UIImageView.class] &&
                BHTIsSafeRailHeaderCandidate(candidate, hostView, NULL)) {
                free(ivars);
                if (resolution) {
                    *resolution =
                        [@"semanticIvar:" stringByAppendingString:name];
                }
                if (matchCount) *matchCount = 1;
                objc_setAssociatedObject(
                    hostView, &kBHTRailResolvedLogoViewKey, candidate,
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                return candidate;
            }
        }
        free(ivars);
    }

    UIImageView* fallback =
        BHTGuardedRailHeaderImageScan(hostView, matchCount);
    if (resolution) {
        *resolution =
            fallback ? @"guardedHeaderScan" : @"unresolved";
    }
    if (fallback) {
        objc_setAssociatedObject(
            hostView, &kBHTRailResolvedLogoViewKey, fallback,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return fallback;
}

static BOOL BHTShouldRecordUnresolvedRailHost(UIView* hostView) {
    Class splitSidebarClass =
        NSClassFromString(@"T1AppSplitSideBarViewController");
    Class tabBarHostClass = NSClassFromString(@"T1TabBarHostView");
    // On X 12.24 the child tab host contains only the navigation buttons.
    // Let the full split-sidebar owner report resolution so the child's
    // expected zero-candidate scan cannot overwrite a successful diagnostic.
    return !splitSidebarClass || !tabBarHostClass ||
           ![hostView isKindOfClass:tabBarHostClass];
}

static void BHTUpdateRailHostBranding(UIView* hostView) {
    if (!BHTUsesPadNavigation(hostView.traitCollection)) return;
    NSString* resolution = nil;
    NSUInteger matchCount = 0;
    UIImageView* logoView =
        BHTRailHeaderLogoImageView(hostView, &resolution, &matchCount);
    if (!logoView) {
        if (BHTShouldRecordUnresolvedRailHost(hostView)) {
            BHTRecordRailBrandingObservation(
                resolution ?: @"unresolved", hostView, nil, matchCount);
        }
        return;
    }

    BOOL enabled =
        [BHTSettings boolForKey:@"color_twitter_icon_in_top_bar"];
    BOOL capturedOriginalState =
        [objc_getAssociatedObject(
            logoView, &kBHTOriginalRailLogoStateCapturedKey)
            boolValue];
    if (enabled) {
        // Wait until X has supplied its stock image so disabling the setting
        // can restore every property exactly instead of leaving a bird behind
        // on an initially-empty image view.
        if (!capturedOriginalState && !logoView.image) {
            BHTRecordRailBrandingObservation(
                resolution ?: @"unresolved", hostView, logoView,
                matchCount);
            return;
        }
        if (!capturedOriginalState) {
            objc_setAssociatedObject(
                logoView, &kBHTOriginalRailLogoImageKey,
                logoView.image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(
                logoView, &kBHTOriginalRailLogoTintKey,
                logoView.tintColor ?: NSNull.null,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(
                logoView, &kBHTOriginalRailLogoContentModeKey,
                @(logoView.contentMode),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(
                logoView,
                &kBHTOriginalRailLogoAccessibilityLabelKey,
                logoView.accessibilityLabel ?: NSNull.null,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(
                logoView, &kBHTOriginalRailLogoStateCapturedKey, @YES,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        BHTInstallBrandingThemeObserver();
        BHTApplyCurrentBirdToImageView(logoView);
    } else if (capturedOriginalState) {
        [BHTBrandedLogoViews() removeObject:logoView];
        logoView.image =
            objc_getAssociatedObject(logoView,
                                     &kBHTOriginalRailLogoImageKey);
        id originalTint =
            objc_getAssociatedObject(logoView,
                                     &kBHTOriginalRailLogoTintKey);
        logoView.tintColor =
            originalTint == NSNull.null ? nil : originalTint;
        NSNumber* originalContentMode =
            objc_getAssociatedObject(
                logoView, &kBHTOriginalRailLogoContentModeKey);
        if (originalContentMode) {
            logoView.contentMode =
                (UIViewContentMode)originalContentMode.integerValue;
        }
        id originalAccessibilityLabel =
            objc_getAssociatedObject(
                logoView,
                &kBHTOriginalRailLogoAccessibilityLabelKey);
        logoView.accessibilityLabel =
            originalAccessibilityLabel == NSNull.null
                ? nil
                : originalAccessibilityLabel;
        objc_setAssociatedObject(
            logoView, &kBHTOriginalRailLogoImageKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            logoView, &kBHTOriginalRailLogoTintKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            logoView, &kBHTOriginalRailLogoContentModeKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            logoView,
            &kBHTOriginalRailLogoAccessibilityLabelKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            logoView, &kBHTOriginalRailLogoStateCapturedKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BHTRecordRailBrandingObservation(
        resolution ?: @"unresolved", hostView, logoView, matchCount);
}

static void BHTScheduleDeferredRailHostBranding(UIView* hostView) {
    if (!hostView ||
        objc_getAssociatedObject(
            hostView, &kBHTRailDeferredUpdatePendingKey)) {
        return;
    }
    objc_setAssociatedObject(
        hostView, &kBHTRailDeferredUpdatePendingKey, @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView* weakHostView = hostView;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView* strongHostView = weakHostView;
        if (!strongHostView) return;
        objc_setAssociatedObject(
            strongHostView, &kBHTRailDeferredUpdatePendingKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BHTUpdateRailHostBranding(strongHostView);
    });
}

// X 12.24 owns the permanent iPad rail header in this controller. Its
// T1TabBarHostView child starts below the mark and therefore cannot see it.
%hook T1AppSplitSideBarViewController

- (void)viewDidLoad {
    %orig;
    UIView* railView = ((UIViewController*)self).view;
    BHTUpdateRailHostBranding(railView);
    BHTScheduleDeferredRailHostBranding(railView);
}

- (void)viewWillLayoutSubviews {
    %orig;
    UIView* railView = ((UIViewController*)self).view;
    BHTUpdateRailHostBranding(railView);
    BHTScheduleDeferredRailHostBranding(railView);
}

- (void)viewSafeAreaInsetsDidChange {
    %orig;
    UIView* railView = ((UIViewController*)self).view;
    BHTUpdateRailHostBranding(railView);
    BHTScheduleDeferredRailHostBranding(railView);
}

%end

%hook T1TabBarHostView

- (void)didMoveToWindow {
    %orig;
    BHTUpdateRailHostBranding((UIView*)self);
    BHTScheduleDeferredRailHostBranding((UIView*)self);
}

- (void)layoutSubviews {
    %orig;
    BHTUpdateRailHostBranding((UIView*)self);
    // The stock rail may assign its X image from a child layout later in the
    // same pass. Re-apply once at the end of the main run loop without a
    // timer, polling, or a process-wide UIImageView hook.
    BHTScheduleDeferredRailHostBranding((UIView*)self);
}

- (void)traitCollectionDidChange:(UITraitCollection*)previousTraits {
    %orig(previousTraits);
    BHTUpdateRailHostBranding((UIView*)self);
    BHTScheduleDeferredRailHostBranding((UIView*)self);
}

- (void)didAddSubview:(UIView*)subview {
    %orig(subview);
    BHTScheduleDeferredRailHostBranding((UIView*)self);
}

- (void)setTabBarViewController:(id)controller {
    %orig(controller);
    BHTScheduleDeferredRailHostBranding((UIView*)self);
}

%end

%hook _TtC11TwitterHome39HomeDefaultNavigationBarTitleViewPlugin

- (UIView*)titleView {
    UIView* titleView = %orig;

    if ([titleView isKindOfClass:[UIImageView class]]) {
        UIImageView* logoView = (UIImageView*)titleView;
        BOOL enabled =
            [BHTSettings boolForKey:@"color_twitter_icon_in_top_bar"];
        BOOL usesPadRail =
            BHTUsesPadNavigation(titleView.traitCollection);
        // iPad already has the branded rail header. Suppress this second Home
        // title mark there; on iPhone it remains the single themed bird.
        logoView.hidden = enabled && usesPadRail;
        logoView.accessibilityElementsHidden = logoView.hidden;
        if (enabled && !usesPadRail) {
            BHTInstallBrandingThemeObserver();
            BHTApplyCurrentBirdToImageView(logoView);
        }
    }

    return titleView;
}

%end
