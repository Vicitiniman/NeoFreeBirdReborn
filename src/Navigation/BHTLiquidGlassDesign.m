#import "BHTLiquidGlassDesign.h"
#import "BHTGlassDockView.h"
#import "BHTComposeButtonVisibility.h"
#import "Core/BHTSettings.h"
#import "Compatibility/BHTHostCompatibility.h"
#import "ThemeColor/Palette.h"
#import "ThemeColor/BHTThemePresets.h"
#import "Headers/Helpers.h"
#import <objc/message.h>
#import <objc/runtime.h>

@interface BHTGlassSavedView : NSObject
@property(nonatomic, weak) UIView* view;
@property(nonatomic, strong) UIColor* background;
@property(nonatomic) BOOL opaque;
@property(nonatomic) BOOL hidden;
@property(nonatomic) BOOL hidesView;
@property(nonatomic) BOOL clearsBackground;
@property(nonatomic) BOOL disablesInteraction;
@property(nonatomic) BOOL interactionEnabled;
@end
@implementation BHTGlassSavedView @end

@interface BHTGlassChromeState : NSObject
@property(nonatomic, strong) BHTGlassDockView* material;
@property(nonatomic, strong) NSMutableArray<BHTGlassSavedView*>* savedViews;
@property(nonatomic, strong) UITraitCollection* traits;
@property(nonatomic, copy) NSString* materialKind;
@property(nonatomic, copy) NSString* requestedMaterialKind;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL updating;
@property(nonatomic) BOOL vertical;
@property(nonatomic) CGRect selectedFrame;
@property(nonatomic) NSUInteger materialUpdates;
@property(nonatomic) NSUInteger selectionUpdates;
@property(nonatomic) NSUInteger materialRebuilds;
@property(nonatomic) NSUInteger collapseTransitions;
@property(nonatomic) BHTGlassDockScrollState scrollState;
@property(nonatomic, weak) UIScrollView* scrollSource;
@property(nonatomic, weak) UIViewController* scrollPage;
@property(nonatomic, weak) UIView* selectedTab;
@end
@implementation BHTGlassChromeState @end

static char BHTLiquidGlassStateKey;
static NSUInteger BHTLiquidGlassGeneration = 1;
static NSHashTable<UIViewController*>* BHTLiquidGlassTabOwners;
static char BHTGlassDockOwnerKey;
static BOOL BHTComposeLayoutRefreshScheduled;
static BHTGlassChromeState* BHTGlassState(id owner, BOOL create);
@interface BHTGlassDockOwner : NSObject
@property(nonatomic, weak) UIViewController* controller;
@property(nonatomic) BOOL refreshScheduled;
@end
@implementation BHTGlassDockOwner @end

BOOL BHTNativeLiquidGlassAvailable(void) {
    Class glass = NSClassFromString(@"UIGlassEffect");
    return BHTIsSupportedHost() && glass && [glass isSubclassOfClass:UIVisualEffect.class] &&
        [glass respondsToSelector:NSSelectorFromString(@"effectWithStyle:")];
}

static id BHTGlassObject(id object, NSString* name) {
    Method method = class_getInstanceMethod([object class], NSSelectorFromString(name));
    char type[16] = {0};
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    method_getReturnType(method, type, sizeof(type));
    return type[0] == '@' ? ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name)) : nil;
}

static void BHTRegisterLiquidGlassObservers(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        BHTLiquidGlassTabOwners = [NSHashTable weakObjectsHashTable];
        for (NSString* name in @[BHTThemeDidChangeNotification, BHTSettingsProfileDidApplyNotification,
             UIAccessibilityReduceTransparencyStatusDidChangeNotification,
             UIAccessibilityReduceMotionStatusDidChangeNotification,
             UIAccessibilityVoiceOverStatusDidChangeNotification,
             UIAccessibilityDarkerSystemColorsStatusDidChangeNotification,
             UIApplicationDidBecomeActiveNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification* note) { BHTRefreshLiquidGlassDesign(); }];
        }
    });
}

static BHTGlassChromeState* BHTGlassState(id owner, BOOL create) {
    BHTGlassChromeState* state = objc_getAssociatedObject(owner, &BHTLiquidGlassStateKey);
    if (!state && create) {
        state = [BHTGlassChromeState new];
        state.savedViews = [NSMutableArray array];
        state.material = [[BHTGlassDockView alloc] initWithEffect:nil];
        state.material.userInteractionEnabled = YES;
        state.material.isAccessibilityElement = NO;
        state.material.layer.cornerCurve = kCACornerCurveContinuous;
        state.material.clipsToBounds = YES;
        __weak UIViewController* weakOwner = owner;
        state.material.expansionHandler = ^{
            BHTGlassChromeState* current = objc_getAssociatedObject(weakOwner, &BHTLiquidGlassStateKey);
            if (!current) return;
            BHTGlassDockScrollState scroll = current.scrollState;
            BHTGlassDockReveal(&scroll, YES);
            current.scrollState = scroll;
            BHTUpdateLiquidGlassTabBar(weakOwner);
        };
        objc_setAssociatedObject(owner, &BHTLiquidGlassStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}

static void BHTGlassClearView(BHTGlassChromeState* state, UIView* view, BOOL hide) {
    if (![view isKindOfClass:UIView.class] || view == state.material) return;
    BHTGlassSavedView* saved = nil;
    for (BHTGlassSavedView* item in state.savedViews) if (item.view == view) { saved = item; break; }
    if (!saved) {
        saved = [BHTGlassSavedView new];
        saved.view = view;
        saved.background = view.backgroundColor;
        saved.opaque = view.opaque;
        saved.hidden = view.hidden;
        [state.savedViews addObject:saved];
    }
    if (hide) {
        saved.hidesView = YES;
        if (!view.hidden) view.hidden = YES;
    } else {
        saved.clearsBackground = YES;
        if (view.backgroundColor && ![view.backgroundColor isEqual:UIColor.clearColor]) {
            saved.background = view.backgroundColor;
            view.backgroundColor = UIColor.clearColor;
        }
        if (view.opaque) view.opaque = NO;
    }
}

static void BHTGlassRestore(id owner) {
    BHTGlassChromeState* state = BHTGlassState(owner, NO);
    if (!state) return;
    [state.material removeFromSuperview];
    for (BHTGlassSavedView* saved in state.savedViews) {
        UIView* view = saved.view;
        if (!view) continue;
        if (saved.disablesInteraction && !view.userInteractionEnabled) view.userInteractionEnabled = saved.interactionEnabled;
        if (saved.hidesView) {
            if (view.hidden) view.hidden = saved.hidden;
        }
        if (saved.clearsBackground) {
            if ([view.backgroundColor isEqual:UIColor.clearColor]) view.backgroundColor = saved.background;
            if (!view.opaque) view.opaque = saved.opaque;
        }
    }
    objc_setAssociatedObject(owner, &BHTLiquidGlassStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void BHTGlassPassThrough(BHTGlassChromeState* state, UIView* view) {
    BHTGlassClearView(state, view, NO);
    for (BHTGlassSavedView* saved in state.savedViews) if (saved.view == view) {
        if (!saved.disablesInteraction) {
            saved.interactionEnabled = view.userInteractionEnabled;
            saved.disablesInteraction = YES;
        }
        if (view.userInteractionEnabled) view.userInteractionEnabled = NO;
        break;
    }
}

BOOL BHTGlassDockUsesOverlayLayout(UIViewController* owner) {
    return BHTIsSupportedHost() && [BHTSettings boolForKey:@"liquid_glass_design"] &&
        UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad && BHTGlassDockCanRoute(owner, NO);
}

BOOL BHTGlassDockHasActiveDockedContent(UIViewController* owner) {
    for (UIViewController* parent = owner.parentViewController; parent; parent = parent.parentViewController) {
        id segment = BHTGlassObject(parent, @"tabBottomSegmentViewController");
        if (segment) return BHTGlassObject(segment, @"activeController") != nil;
    }
    return NO;
}

CGFloat BHTGlassDockNativeStockHeight(UIViewController* container, CGFloat nativeHeight) {
    id owner = BHTGlassObject(container, @"tabBarViewController");
    return BHTGlassDockStockHeight(nativeHeight,
        [owner isKindOfClass:UIViewController.class] && BHTGlassDockUsesOverlayLayout(owner));
}

void BHTUpdateGlassAppContainer(UIViewController* container) {
    id owner = BHTGlassObject(container, @"tabBarViewController");
    if ([owner isKindOfClass:UIViewController.class]) BHTUpdateLiquidGlassTabBar(owner);
}

static void BHTGlassUpdateMaterial(BHTGlassChromeState* state, UIView* host) {
    NSString* kind = UIAccessibilityIsReduceTransparencyEnabled() ? @"opaque_accessibility" :
        (BHTNativeLiquidGlassAvailable() ? @"native_liquid_glass" : @"system_material");
    BOOL colorChanged = !state.traits || [host.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:state.traits];
    if (state.generation == BHTLiquidGlassGeneration && !colorChanged && [state.requestedMaterialKind isEqual:kind]) return;
    BOOL rebuild = ![state.requestedMaterialKind isEqual:kind];
    state.requestedMaterialKind = kind;
    UIVisualEffect* effect = state.material.materialEffect;
    if (rebuild) effect = nil;
    if (rebuild && [kind isEqualToString:@"native_liquid_glass"]) {
        // Public UIKit clear glass (style 1), with our own controls inside its
        // content view. X's bar and navigation rollout are not used to draw it.
        id candidate = ((id (*)(id, SEL, NSInteger))objc_msgSend)(NSClassFromString(@"UIGlassEffect"),
            NSSelectorFromString(@"effectWithStyle:"), 1);
        if ([candidate respondsToSelector:NSSelectorFromString(@"setInteractive:")])
            ((void (*)(id, SEL, BOOL))objc_msgSend)(candidate, NSSelectorFromString(@"setInteractive:"), YES);
        if ([candidate isKindOfClass:UIVisualEffect.class]) effect = candidate;
    }
    if (rebuild && !effect && !UIAccessibilityIsReduceTransparencyEnabled()) {
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
        kind = @"system_material";
    }
    if (rebuild) { state.material.materialEffect = effect; state.materialRebuilds++; }
    [state.material setGlassOpacity:BHTGlassDockOpacity([BHTSettings integerForKey:@"glass_opacity"],
        UIAccessibilityIsReduceTransparencyEnabled()) surfaceColor:[Palette currentBackgroundColor]];
    state.material.backgroundColor = effect ? UIColor.clearColor : [Palette currentSurfaceColor];
    state.material.overrideUserInterfaceStyle = [Palette currentPaletteUsesDarkAppearance]
        ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    UIColor* edge = [Palette currentPaletteUsesDarkAppearance] ? UIColor.whiteColor : UIColor.blackColor;
    state.material.layer.borderColor = [edge colorWithAlphaComponent:0.22].CGColor;
    state.material.layer.borderWidth = UIAccessibilityDarkerSystemColorsEnabled() ? 1 : 0.5;
    if (rebuild) state.materialKind = kind;
    state.traits = host.traitCollection;
    state.generation = BHTLiquidGlassGeneration;
    state.materialUpdates++;
}

static double BHTGlassNumber(id object, NSString* name, double fallback) {
    Method method = class_getInstanceMethod([object class], NSSelectorFromString(name));
    char type[16] = {0};
    if (!method || method_getNumberOfArguments(method) != 2) return fallback;
    method_getReturnType(method, type, sizeof(type));
    if (type[0] == 'B' || type[0] == 'c') return ((BOOL (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name));
    if (type[0] == 'd') return ((double (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name));
    return fallback;
}

void BHTRefreshGlassDockForTabView(UIView* view) {
    BHTGlassDockOwner* owner = objc_getAssociatedObject(view, &BHTGlassDockOwnerKey);
    if (!owner.controller || owner.refreshScheduled || ![BHTSettings boolForKey:@"liquid_glass_design"]) return;
    owner.refreshScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        owner.refreshScheduled = NO;
        if (owner.controller) BHTUpdateLiquidGlassTabBar(owner.controller);
    });
}

void BHTUpdateLiquidGlassTabBar(UIViewController* controller) {
    if (!NSThread.isMainThread || !controller.isViewLoaded) return;
    BHTRegisterLiquidGlassObservers();
    [BHTLiquidGlassTabOwners addObject:controller];
    if (![BHTSettings boolForKey:@"liquid_glass_design"] || !BHTIsSupportedHost()) { BHTGlassRestore(controller); return; }
    UIView* tabBar = BHTGlassObject(controller, @"tabBar");
    NSArray* tabs = BHTGlassObject(controller, @"tabViews");
    if (!BHTGlassDockCanRoute(controller, NO)) {
        BHTGlassRestore(controller);
        return;
    }
    BOOL overlay = BHTGlassDockUsesOverlayLayout(controller);
    if (![tabBar isKindOfClass:UIView.class] || ![tabs isKindOfClass:NSArray.class] || !tabs.count ||
        ![tabBar isDescendantOfView:controller.view] || (!overlay && CGRectIsEmpty(tabBar.bounds))) {
        // Native navigation can pass through zero-size/reparenting states.
        // Retain the effect rather than rebuilding it and flashing on return.
        BHTGlassChromeState* suspended = BHTGlassState(controller, NO);
        suspended.material.hidden = YES;
        suspended.material.userInteractionEnabled = NO;
        return;
    }
    for (id tab in tabs) if (![tab isKindOfClass:UIView.class]) { BHTGlassRestore(controller); return; }
    UIView* host = controller.view.superview ?: controller.view;
    BHTGlassChromeState* state = BHTGlassState(controller, YES);
    if (state.updating) return;
    state.updating = YES;
    @try {
        CGRect nativeFrame = overlay && host != controller.view
            ? BHTGlassDockOverlayReferenceFrame(host.bounds, CGRectGetMinY(controller.view.frame))
            : [tabBar convertRect:tabBar.bounds toView:host];
        state.vertical = !overlay && nativeFrame.size.height > nativeFrame.size.width;
        BOOL labels = [BHTSettings boolForKey:@"restore_tab_labels"];
        CGFloat safeBottom = host.safeAreaInsets.bottom;
        CGRect frame = BHTGlassDockFrame(nativeFrame, host.bounds, safeBottom, tabs.count, state.vertical, labels);
        if (CGRectIsEmpty(frame)) { state.material.hidden = YES; state.material.userInteractionEnabled = NO; return; }
        if (overlay && host != controller.view) {
            // Hide the entire stock rendering tree, not only its buttons/fill.
            // The owned controls are a sibling, outside this hidden subtree.
            BHTGlassClearView(state, controller.view, YES);
        } else {
            BHTGlassClearView(state, controller.view, NO);
            if (host != controller.view) BHTGlassPassThrough(state, controller.view);
        }
        if (tabBar != controller.view) BHTGlassClearView(state, tabBar, YES);
        else for (UIView* tab in tabs) BHTGlassClearView(state, tab, YES);
        for (NSString* name in @[@"tabBarBackgroundView", @"tabBarDivider"]) {
            UIView* background = BHTGlassObject(controller, name);
            if ([background isKindOfClass:UIView.class] && background != tabBar && background != controller.view &&
                ![tabBar isDescendantOfView:background]) BHTGlassClearView(state, background, YES);
        }
        if (state.material.superview != host) {
            if (controller.view.superview == host) [host insertSubview:state.material aboveSubview:controller.view];
            else [host addSubview:state.material];
        }
        BOOL hidden = BHTGlassNumber(controller, @"isTabBarHidden", NO) != 0;
        CGFloat alpha = hidden ? 0 : tabBar.alpha;
        if (state.material.hidden != hidden) state.material.hidden = hidden;
        if (state.material.alpha != alpha) state.material.alpha = alpha;
        state.material.userInteractionEnabled = !hidden && alpha > 0.05;
        UIView* selected = nil;
        for (UIView* tab in tabs) if (BHTGlassNumber(tab, @"isSelected", NO) != 0) { selected = tab; break; }
        if (selected != state.selectedTab) {
            state.selectedTab = selected;
            state.scrollState = (BHTGlassDockScrollState){0};
            state.scrollSource = nil;
            state.scrollPage = nil;
        }
        if (state.vertical || [BHTSettings boolForKey:@"no_tab_bar_hiding"] || UIAccessibilityIsVoiceOverRunning()) {
            BHTGlassDockScrollState scroll = state.scrollState;
            BHTGlassDockReveal(&scroll, NO);
            state.scrollState = scroll;
        }
        BHTGlassUpdateMaterial(state, host);
        [state.material updateTabs:tabs owner:controller vertical:state.vertical showLabels:labels
            textColor:[Palette currentTextColor] accent:(CurrentAccentColor() ?: UIColor.systemBlueColor)];
        CGRect previousDockFrame = state.material.frame;
        [state.material presentExpandedFrame:frame collapsed:state.scrollState.collapsed
            rightToLeft:host.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft animated:YES];
        if (!CGRectEqualToRect(previousDockFrame, state.material.frame) && !BHTComposeLayoutRefreshScheduled) {
            BHTComposeLayoutRefreshScheduled = YES;
            dispatch_async(dispatch_get_main_queue(), ^{
                BHTComposeLayoutRefreshScheduled = NO;
                BHTRefreshComposeButtonLayout();
            });
        }
        BHTGlassDockOwner* box = objc_getAssociatedObject(controller, &BHTGlassDockOwnerKey);
        if (!box) {
            box = [BHTGlassDockOwner new];
            box.controller = controller;
            objc_setAssociatedObject(controller, &BHTGlassDockOwnerKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        for (UIView* tab in tabs) {
            if (objc_getAssociatedObject(tab, &BHTGlassDockOwnerKey) != box)
                objc_setAssociatedObject(tab, &BHTGlassDockOwnerKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @finally { state.updating = NO; }
}

CGRect BHTGlassDockAvoidanceFrame(UIView* view) {
    if (!NSThread.isMainThread || !view.window || ![BHTSettings boolForKey:@"liquid_glass_design"]) return CGRectZero;
    for (UIViewController* owner in BHTLiquidGlassTabOwners.allObjects) {
        BHTGlassChromeState* state = BHTGlassState(owner, NO);
        if (state.material.window == view.window && !state.material.hidden && state.material.alpha > 0.05)
            return [state.material convertRect:state.material.bounds toView:view];
    }
    return CGRectZero;
}

void BHTObserveGlassDockScroll(UIViewController* source, UIScrollView* scrollView) {
    if (!NSThread.isMainThread || ![BHTSettings boolForKey:@"liquid_glass_design"] ||
        !source.isViewLoaded || !scrollView.window || scrollView.window != source.view.window ||
        ![scrollView isDescendantOfView:source.view] || scrollView.bounds.size.height < 1) return;
    for (UIViewController* parent = source; parent; parent = parent.parentViewController)
        if (parent.presentingViewController) return;
    for (UIViewController* owner in BHTLiquidGlassTabOwners.allObjects) {
        BHTGlassChromeState* state = BHTGlassState(owner, NO);
        UIView* host = state.material.superview;
        if (!state || state.vertical || !host || state.material.hidden || host.window != scrollView.window) continue;
        // The report shows the tab controller and content as sibling children
        // of T1AppSplitViewController. The bar host alone need not contain a feed.
        BOOL sameContainer = [source.view isDescendantOfView:host];
        UIViewController* container = owner.parentViewController;
        for (NSUInteger depth = 0; !sameContainer && container && depth < 12; depth++, container = container.parentViewController)
            if (container.isViewLoaded) sameContainer = [source.view isDescendantOfView:container.view];
        if (!sameContainer) continue;
        if (state.scrollSource != scrollView || state.scrollPage != source) {
            BOOL samePage = state.scrollPage == source;
            state.scrollPage = source;
            state.scrollSource = scrollView;
            BHTGlassDockScrollState scroll = state.scrollState;
            BHTGlassDockResetScroll(&scroll, samePage);
            state.scrollState = scroll;
            BHTUpdateLiquidGlassTabBar(owner);
        }
        BHTGlassDockScrollState scroll = state.scrollState;
        CGFloat offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top;
        CGFloat maximum = scrollView.contentSize.height - scrollView.bounds.size.height +
            scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom;
        BOOL changed = BHTGlassDockObserveScroll(&scroll, offset, maximum, scrollView.dragging,
            scrollView.decelerating, [BHTSettings boolForKey:@"no_tab_bar_hiding"] || UIAccessibilityIsVoiceOverRunning());
        state.scrollState = scroll;
        if (changed) { state.collapseTransitions++; BHTUpdateLiquidGlassTabBar(owner); }
    }
}

void BHTUpdateLiquidGlassNavigationBar(UINavigationBar* bar) {
    if (!NSThread.isMainThread) return;
    // A full-size effect added above TFNNavigationBar's private content can
    // cover the avatar, title/bird and actions. Leave the header native.
    BHTGlassRestore(bar);
}

void BHTRefreshLiquidGlassDesign(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ BHTRefreshLiquidGlassDesign(); }); return; }
    BHTRegisterLiquidGlassObservers();
    BHTLiquidGlassGeneration++;
    for (UIViewController* owner in BHTLiquidGlassTabOwners.allObjects) {
        BHTUpdateLiquidGlassTabBar(owner);
        if (owner.parentViewController.isViewLoaded) [owner.parentViewController.view setNeedsLayout];
    }
}

static NSDictionary* BHTGlassDiagnosticFrame(CGRect frame) {
    return @{@"x": @(frame.origin.x), @"y": @(frame.origin.y),
        @"width": @(frame.size.width), @"height": @(frame.size.height)};
}

NSDictionary* BHTLiquidGlassDesignDiagnosticSnapshot(void) {
    if (!NSThread.isMainThread) {
        __block NSDictionary* result;
        dispatch_sync(dispatch_get_main_queue(), ^{ result = BHTLiquidGlassDesignDiagnosticSnapshot(); });
        return result;
    }
    NSMutableArray* entries = [NSMutableArray array];
    NSArray* owners = BHTLiquidGlassTabOwners.allObjects ?: @[];
    for (UIViewController* owner in owners) {
        BHTGlassChromeState* state = BHTGlassState(owner, NO);
        if (!state) continue;
        UIView* root = owner.isViewLoaded ? owner.view : nil;
        BOOL overlay = BHTGlassDockUsesOverlayLayout(owner);
        BOOL rootSlotRemoved = overlay && root && root.superview && root.hidden && root.bounds.size.height <= 0.5 &&
            root.superview == state.material.superview;
        UIScrollView* scroll = state.scrollSource;
        BOOL viewportAttached = scroll.window && scroll.window == state.material.window;
        NSDictionary* viewport = viewportAttached ? @{
            @"frameInWindow": BHTGlassDiagnosticFrame([scroll convertRect:scroll.bounds toView:scroll.window]),
            @"adjustedBottomInset": @(scroll.adjustedContentInset.bottom),
            @"safeBottomInset": @(scroll.safeAreaInsets.bottom)} : @{};
        [entries addObject:@{@"ownerClass": NSStringFromClass([owner class]), @"material": state.materialKind ?: @"none",
            @"verticalRail": @(state.vertical), @"windowAttached": @(state.material.window != nil),
            @"width": @(state.material.bounds.size.width), @"height": @(state.material.bounds.size.height),
            @"materialUpdates": @(state.materialUpdates), @"selectionUpdates": @(state.material.selectionUpdates),
            @"materialRebuilds": @(state.materialRebuilds), @"collapsed": @(state.material.isCollapsed),
            @"collapseTransitions": @(state.collapseTransitions),
            @"manuallyExpanded": @(state.scrollState.manuallyExpanded),
            @"overlayLayoutRequested": @(overlay), @"bottomReservationRemoved": @(rootSlotRemoved),
            @"nativeRootHidden": @(root.hidden), @"nativeRootHeight": @(root.bounds.size.height),
            @"nativeRootFrame": root ? BHTGlassDiagnosticFrame(root.frame) : @{},
            @"activeDockedContent": @(BHTGlassDockHasActiveDockedContent(owner)),
            @"renderedEffectPresent": @(state.material.effect != nil),
            @"materialFraction": @(state.material.materialFraction), @"tintFraction": @(state.material.tintFraction),
            @"lastObservedViewportAtReportTime": viewport, @"lastObservedViewportAttached": @(viewportAttached),
            @"customButtons": @(state.material.buttonCount)}];
    }
    return @{@"enabled": @([BHTSettings boolForKey:@"liquid_glass_design"]),
        @"nativeGlassAvailable": @(BHTNativeLiquidGlassAvailable()),
        @"reduceTransparency": @(UIAccessibilityIsReduceTransparencyEnabled()),
        @"reduceMotion": @(UIAccessibilityIsReduceMotionEnabled()),
        @"opacityPercent": @(BHTGlassDockOpacity([BHTSettings integerForKey:@"glass_opacity"], NO) * 100),
        @"nativeTabActionsPreserved": @YES, @"nativeItemFramesManagedByX": @YES,
        @"implementation": @"owned_glass_dock", @"headerOverlayInstalled": @NO,
        @"surfaces": entries, @"capturesTextOrAccountIdentifiers": @NO};
}
