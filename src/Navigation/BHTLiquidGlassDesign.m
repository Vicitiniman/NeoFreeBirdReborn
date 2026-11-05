#import "BHTLiquidGlassDesign.h"
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
@property(nonatomic, strong) UIVisualEffectView* material;
@property(nonatomic, strong) UIView* selection;
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
static NSHashTable<UINavigationBar*>* BHTLiquidGlassNavigationBars;

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
        BHTLiquidGlassNavigationBars = [NSHashTable weakObjectsHashTable];
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
        state.material = [[UIVisualEffectView alloc] initWithEffect:nil];
        state.material.userInteractionEnabled = NO;
        state.material.isAccessibilityElement = NO;
        state.material.layer.cornerCurve = kCACornerCurveContinuous;
        state.material.clipsToBounds = YES;
        state.selection = [UIView new];
        state.selection.userInteractionEnabled = NO;
        state.selection.isAccessibilityElement = NO;
        state.selection.layer.cornerCurve = kCACornerCurveContinuous;
        [state.material.contentView addSubview:state.selection];
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
        // Public UIKit factory, verified against UIGlassEffect.h. Regular is
        // the first (zero-valued) NSInteger style. Runtime dispatch retains the
        // iOS 16.5 build SDK without relying on an inherited initializer.
        id candidate = ((id (*)(id, SEL, NSInteger))objc_msgSend)(NSClassFromString(@"UIGlassEffect"),
            NSSelectorFromString(@"effectWithStyle:"), 0);
        if ([candidate isKindOfClass:UIVisualEffect.class]) effect = candidate;
    }
    if (!effect && !UIAccessibilityIsReduceTransparencyEnabled()) {
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
        kind = @"system_material";
    }
    state.material.effect = effect;
    state.material.backgroundColor = effect ? UIColor.clearColor : [Palette currentSurfaceColor];
    state.material.overrideUserInterfaceStyle = [Palette currentPaletteUsesDarkAppearance]
        ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    state.material.layer.borderColor = [[Palette currentSeparatorColor] colorWithAlphaComponent:0.4].CGColor;
    state.material.layer.borderWidth = UIAccessibilityDarkerSystemColorsEnabled() ? 1 : 0.5;
    state.selection.backgroundColor = [(CurrentAccentColor() ?: UIColor.systemBlueColor)
        colorWithAlphaComponent:UIAccessibilityDarkerSystemColorsEnabled() ? 0.28 : 0.14];
    state.materialKind = kind;
    state.traits = host.traitCollection;
    state.generation = BHTLiquidGlassGeneration;
    state.materialUpdates++;
}

void BHTUpdateLiquidGlassTabBar(UIViewController* controller) {
    if (!NSThread.isMainThread || !controller.isViewLoaded) return;
    BHTRegisterLiquidGlassObservers();
    [BHTLiquidGlassTabOwners addObject:controller];
    if (![BHTSettings boolForKey:@"liquid_glass_design"] || !BHTIsSupportedHost()) { BHTGlassRestore(controller); return; }
    UIView* tabBar = BHTGlassObject(controller, @"tabBar");
    NSArray* tabs = BHTGlassObject(controller, @"tabViews");
    if (![tabBar isKindOfClass:UIView.class] || ![tabs isKindOfClass:NSArray.class] || !tabs.count ||
        ![tabBar isDescendantOfView:controller.view] || CGRectIsEmpty(tabBar.bounds)) {
        BHTGlassRestore(controller);
        return;
    }
    UIView* host = tabBar == controller.view ? tabBar : tabBar.superview;
    BHTGlassChromeState* state = BHTGlassState(controller, YES);
    if (state.updating) return;
    state.updating = YES;
    @try {
        CGRect nativeFrame = [tabBar convertRect:tabBar.bounds toView:host];
        state.vertical = nativeFrame.size.height > nativeFrame.size.width;
        CGRect frame = BHTLiquidGlassFrame(nativeFrame, state.vertical);
        if (CGRectIsEmpty(frame)) return;
        BHTGlassClearView(state, controller.view, NO);
        BHTGlassClearView(state, tabBar, NO);
        for (NSString* name in @[@"tabBarBackgroundView", @"tabBarDivider"]) {
            UIView* background = BHTGlassObject(controller, name);
            if ([background isKindOfClass:UIView.class] && background != tabBar &&
                ![tabBar isDescendantOfView:background]) BHTGlassClearView(state, background, YES);
        }
        if (state.material.superview != host) {
            if (host == tabBar) [host insertSubview:state.material atIndex:0];
            else [host insertSubview:state.material belowSubview:tabBar];
        }
        BOOL hidden = host == tabBar ? NO : tabBar.hidden;
        CGFloat alpha = host == tabBar ? 1 : tabBar.alpha;
        if (state.material.hidden != hidden) state.material.hidden = hidden;
        if (state.material.alpha != alpha) state.material.alpha = alpha;
        if (!CGRectEqualToRect(state.material.frame, frame)) state.material.frame = frame;
        CGFloat radius = state.vertical ? MIN(24, frame.size.width / 2) : frame.size.height / 2;
        if (state.material.layer.cornerRadius != radius) state.material.layer.cornerRadius = radius;
        BHTGlassUpdateMaterial(state, host);
        CGRect selected = CGRectZero;
        for (UIView* tab in tabs) {
            if (![tab isKindOfClass:UIView.class] || ![tab isDescendantOfView:tabBar]) continue;
            SEL selector = NSSelectorFromString(@"isSelected");
            Method method = class_getInstanceMethod(tab.class, selector);
            char result[16] = {0};
            if (!method || method_getNumberOfArguments(method) != 2) continue;
            method_getReturnType(method, result, sizeof(result));
            if ((result[0] == 'B' || result[0] == 'c') && ((BOOL (*)(id, SEL))objc_msgSend)(tab, selector)) {
                CGRect item = [tab convertRect:tab.bounds toView:host];
                selected = BHTLiquidGlassSelectionFrame(item, frame);
                if (!CGRectIsEmpty(selected)) selected = CGRectOffset(selected, -frame.origin.x, -frame.origin.y);
                break;
            }
        }
        if (!CGRectEqualToRect(state.selectedFrame, selected)) {
            BOOL animate = !CGRectIsEmpty(state.selectedFrame) && !CGRectIsEmpty(selected) &&
                state.material.window && !UIAccessibilityIsReduceMotionEnabled();
            state.selectedFrame = selected;
            state.selectionUpdates++;
            void (^layout)(void) = ^{
                state.selection.frame = selected;
                state.selection.layer.cornerRadius = MIN(22, MIN(selected.size.width, selected.size.height) / 2);
            };
            if (animate) [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState |
                UIViewAnimationOptionAllowUserInteraction animations:layout completion:nil];
            else layout();
        }
        BOOL hideSelection = CGRectIsEmpty(selected);
        if (state.selection.hidden != hideSelection) state.selection.hidden = hideSelection;
    } @finally { state.updating = NO; }
}

void BHTUpdateLiquidGlassNavigationBar(UINavigationBar* bar) {
    if (!NSThread.isMainThread) return;
    BHTRegisterLiquidGlassObservers();
    [BHTLiquidGlassNavigationBars addObject:bar];
    if (![BHTSettings boolForKey:@"liquid_glass_design"] || !BHTIsSupportedHost()) { BHTGlassRestore(bar); return; }
    // Limit the retrofit to TFNNavigationBar's known background owner. Native
    // XNavigation bars retain UIKit's own glass/scroll-edge implementation.
    UIView* background = BHTGlassObject(bar, @"backgroundView");
    if (![background isKindOfClass:UIView.class] || background == bar || background.superview != bar ||
        CGRectIsEmpty(background.frame)) return;
    BHTGlassChromeState* state = BHTGlassState(bar, YES);
    if (state.updating) return;
    state.updating = YES;
    @try {
        BHTGlassClearView(state, background, YES);
        BHTGlassClearView(state, bar, NO);
        if (state.material.superview != bar) [bar insertSubview:state.material atIndex:0];
        if (!CGRectEqualToRect(state.material.frame, background.frame)) state.material.frame = background.frame;
        if (state.material.layer.cornerRadius != 0) state.material.layer.cornerRadius = 0;
        state.selection.hidden = YES;
        BHTGlassUpdateMaterial(state, bar);
    } @finally { state.updating = NO; }
}

void BHTRefreshLiquidGlassDesign(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ BHTRefreshLiquidGlassDesign(); }); return; }
    BHTRegisterLiquidGlassObservers();
    BHTLiquidGlassGeneration++;
    for (UIViewController* owner in BHTLiquidGlassTabOwners.allObjects) BHTUpdateLiquidGlassTabBar(owner);
    for (UINavigationBar* bar in BHTLiquidGlassNavigationBars.allObjects) BHTUpdateLiquidGlassNavigationBar(bar);
}

NSDictionary* BHTLiquidGlassDesignDiagnosticSnapshot(void) {
    if (!NSThread.isMainThread) {
        __block NSDictionary* result;
        dispatch_sync(dispatch_get_main_queue(), ^{ result = BHTLiquidGlassDesignDiagnosticSnapshot(); });
        return result;
    }
    NSMutableArray* entries = [NSMutableArray array];
    NSArray* owners = [(BHTLiquidGlassTabOwners.allObjects ?: @[]) arrayByAddingObjectsFromArray:
        BHTLiquidGlassNavigationBars.allObjects ?: @[]];
    for (id owner in owners) {
        BHTGlassChromeState* state = BHTGlassState(owner, NO);
        if (!state) continue;
        [entries addObject:@{@"ownerClass": NSStringFromClass([owner class]), @"material": state.materialKind ?: @"none",
            @"verticalRail": @(state.vertical), @"windowAttached": @(state.material.window != nil),
            @"width": @(state.material.bounds.size.width), @"height": @(state.material.bounds.size.height),
            @"materialUpdates": @(state.materialUpdates), @"selectionUpdates": @(state.selectionUpdates)}];
    }
    return @{@"enabled": @([BHTSettings boolForKey:@"liquid_glass_design"]),
        @"nativeGlassAvailable": @(BHTNativeLiquidGlassAvailable()),
        @"reduceTransparency": @(UIAccessibilityIsReduceTransparencyEnabled()),
        @"reduceMotion": @(UIAccessibilityIsReduceMotionEnabled()),
        @"nativeTabActionsPreserved": @YES, @"nativeTabFramesPreserved": @YES,
        @"surfaces": entries, @"capturesTextOrAccountIdentifiers": @NO};
}
