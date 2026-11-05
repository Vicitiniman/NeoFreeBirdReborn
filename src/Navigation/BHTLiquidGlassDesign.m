#import "BHTLiquidGlassDesign.h"
#import "BHTGlassDockView.h"
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
@end
@implementation BHTGlassChromeState @end

static char BHTLiquidGlassStateKey;
static NSUInteger BHTLiquidGlassGeneration = 1;
static NSHashTable<UIViewController*>* BHTLiquidGlassTabOwners;
static char BHTGlassDockOwnerKey;
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
        saved.hidesView = hide;
        [state.savedViews addObject:saved];
    }
    if (hide) {
        if (!view.hidden) view.hidden = YES;
    } else {
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
        if (saved.hidesView) {
            if (view.hidden) view.hidden = saved.hidden;
        } else {
            if ([view.backgroundColor isEqual:UIColor.clearColor]) view.backgroundColor = saved.background;
            if (!view.opaque) view.opaque = saved.opaque;
        }
    }
    objc_setAssociatedObject(owner, &BHTLiquidGlassStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void BHTGlassUpdateMaterial(BHTGlassChromeState* state, UIView* host) {
    NSString* kind = UIAccessibilityIsReduceTransparencyEnabled() ? @"opaque_accessibility" :
        (BHTNativeLiquidGlassAvailable() ? @"native_liquid_glass" : @"system_material");
    BOOL colorChanged = !state.traits || [host.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:state.traits];
    if (state.generation == BHTLiquidGlassGeneration && !colorChanged && [state.requestedMaterialKind isEqual:kind]) return;
    state.requestedMaterialKind = kind;
    UIVisualEffect* effect = nil;
    if ([kind isEqualToString:@"native_liquid_glass"]) {
        // Public UIKit clear glass (style 1), with our own controls inside its
        // content view. X's bar and navigation rollout are not used to draw it.
        id candidate = ((id (*)(id, SEL, NSInteger))objc_msgSend)(NSClassFromString(@"UIGlassEffect"),
            NSSelectorFromString(@"effectWithStyle:"), 1);
        if ([candidate respondsToSelector:NSSelectorFromString(@"setInteractive:")])
            ((void (*)(id, SEL, BOOL))objc_msgSend)(candidate, NSSelectorFromString(@"setInteractive:"), YES);
        if ([candidate isKindOfClass:UIVisualEffect.class]) effect = candidate;
    }
    if (!effect && !UIAccessibilityIsReduceTransparencyEnabled()) {
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
        kind = @"system_material";
    }
    state.material.effect = effect;
    state.material.backgroundColor = effect ? UIColor.clearColor : [Palette currentSurfaceColor];
    state.material.overrideUserInterfaceStyle = [Palette currentPaletteUsesDarkAppearance]
        ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    UIColor* edge = [Palette currentPaletteUsesDarkAppearance] ? UIColor.whiteColor : UIColor.blackColor;
    state.material.layer.borderColor = [edge colorWithAlphaComponent:0.22].CGColor;
    state.material.layer.borderWidth = UIAccessibilityDarkerSystemColorsEnabled() ? 1 : 0.5;
    state.materialKind = kind;
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
    if (![tabBar isKindOfClass:UIView.class] || ![tabs isKindOfClass:NSArray.class] || !tabs.count ||
        ![tabBar isDescendantOfView:controller.view] || CGRectIsEmpty(tabBar.bounds) || !BHTGlassDockCanRoute(controller, NO)) {
        BHTGlassRestore(controller);
        return;
    }
    for (id tab in tabs) if (![tab isKindOfClass:UIView.class]) { BHTGlassRestore(controller); return; }
    UIView* host = controller.view.superview ?: controller.view;
    BHTGlassChromeState* state = BHTGlassState(controller, YES);
    if (state.updating) return;
    state.updating = YES;
    @try {
        CGRect nativeFrame = [tabBar convertRect:tabBar.bounds toView:host];
        state.vertical = nativeFrame.size.height > nativeFrame.size.width;
        BOOL labels = [BHTSettings boolForKey:@"restore_tab_labels"];
        CGFloat safeBottom = host.safeAreaInsets.bottom;
        CGRect frame = BHTGlassDockFrame(nativeFrame, host.bounds, safeBottom, tabs.count, state.vertical, labels);
        if (CGRectIsEmpty(frame)) { BHTGlassRestore(controller); return; }
        BHTGlassClearView(state, controller.view, NO);
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
        double collapse = BHTGlassNumber(controller, @"tabBarCollapseRatio", 0);
        CGFloat alpha = hidden ? 0 : tabBar.alpha * MAX(0, MIN(1, 1 - collapse));
        if (state.material.hidden != hidden) state.material.hidden = hidden;
        if (state.material.alpha != alpha) state.material.alpha = alpha;
        state.material.userInteractionEnabled = !hidden && alpha > 0.05;
        if (!CGRectEqualToRect(state.material.frame, frame)) state.material.frame = frame;
        CGFloat radius = state.vertical ? MIN(24, frame.size.width / 2) : frame.size.height / 2;
        if (state.material.layer.cornerRadius != radius) state.material.layer.cornerRadius = radius;
        BHTGlassUpdateMaterial(state, host);
        [state.material updateTabs:tabs owner:controller vertical:state.vertical showLabels:labels
            textColor:[Palette currentTextColor] accent:(CurrentAccentColor() ?: UIColor.systemBlueColor)];
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
    for (UIViewController* owner in BHTLiquidGlassTabOwners.allObjects) BHTUpdateLiquidGlassTabBar(owner);
}

NSDictionary* BHTLiquidGlassDesignDiagnosticSnapshot(void) {
    if (!NSThread.isMainThread) {
        __block NSDictionary* result;
        dispatch_sync(dispatch_get_main_queue(), ^{ result = BHTLiquidGlassDesignDiagnosticSnapshot(); });
        return result;
    }
    NSMutableArray* entries = [NSMutableArray array];
    NSArray* owners = BHTLiquidGlassTabOwners.allObjects ?: @[];
    for (id owner in owners) {
        BHTGlassChromeState* state = BHTGlassState(owner, NO);
        if (!state) continue;
        [entries addObject:@{@"ownerClass": NSStringFromClass([owner class]), @"material": state.materialKind ?: @"none",
            @"verticalRail": @(state.vertical), @"windowAttached": @(state.material.window != nil),
            @"width": @(state.material.bounds.size.width), @"height": @(state.material.bounds.size.height),
            @"materialUpdates": @(state.materialUpdates), @"selectionUpdates": @(state.material.selectionUpdates),
            @"customButtons": @(state.material.buttonCount)}];
    }
    return @{@"enabled": @([BHTSettings boolForKey:@"liquid_glass_design"]),
        @"nativeGlassAvailable": @(BHTNativeLiquidGlassAvailable()),
        @"reduceTransparency": @(UIAccessibilityIsReduceTransparencyEnabled()),
        @"reduceMotion": @(UIAccessibilityIsReduceMotionEnabled()),
        @"nativeTabActionsPreserved": @YES, @"nativeTabFramesPreserved": @YES,
        @"implementation": @"owned_glass_dock", @"headerOverlayInstalled": @NO,
        @"surfaces": entries, @"capturesTextOrAccountIdentifiers": @NO};
}
