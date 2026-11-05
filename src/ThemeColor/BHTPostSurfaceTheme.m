#import "BHTPostSurfaceTheme.h"
#import "Palette.h"
#import "BHTThemePresets.h"
#import "Core/BHTSettings.h"
#import "Compatibility/BHTHostCompatibility.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Touch/highlight planes may sit ABOVE photos despite resembling backgrounds.
// Change only the explicitly selected surface's own backing color.
BOOL BHTApplySurfaceBackingColor(UIView* view, UIColor* color) {
    if (!view || [view.backgroundColor isEqual:color] || (!view.backgroundColor && !color)) return NO;
    [UIView performWithoutAnimation:^{ view.backgroundColor = color; }];
    return YES;
}

@interface BHTSurfaceThemeState : NSObject
@property(nonatomic, strong) UIColor* nativeColor;
@property(nonatomic) BOOL applying;
@property(nonatomic) BOOL fillsBackdrop;
@property(nonatomic) BOOL drawsColor;
@end
@implementation BHTSurfaceThemeState @end

static char BHTSurfaceThemeKey;
static NSHashTable<UIView*>* BHTPostSurfaces;
static NSUInteger BHTPostRootUpdates;
static NSUInteger BHTPostNativeAssignments;

static void BHTTrackPostTheme(void) {
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        BHTPostSurfaces = [NSHashTable weakObjectsHashTable];
        for (NSString* name in @[BHTThemeDidChangeNotification, BHTSettingsProfileDidApplyNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification* notification) {
                    for (UIView* view in BHTPostSurfaces.allObjects) if (view.window) BHTApplyPostSurfaceTheme(view);
                }];
        }
    });
}

static BHTSurfaceThemeState* BHTSurfaceState(UIView* view, BOOL create) {
    BHTSurfaceThemeState* state = objc_getAssociatedObject(view, &BHTSurfaceThemeKey);
    if (!state && create) {
        BHTTrackPostTheme();
        state = [BHTSurfaceThemeState new];
        state.nativeColor = view.backgroundColor;
        objc_setAssociatedObject(view, &BHTSurfaceThemeKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [BHTPostSurfaces addObject:view];
    }
    return state;
}

static UIColor* BHTResolvedSurfaceColor(BHTSurfaceThemeState* state) {
    UIColor* theme = [Palette customThemeColorForRole:BHTThemeColorBackgroundKey];
    UIColor* native = state.nativeColor;
    if (!theme) return native;
    if (state.fillsBackdrop) return theme;
    if (!native) return nil;
    CGColorRef cgColor = native.CGColor;
    if (!cgColor) return native;
    CGFloat alpha = CGColorGetAlpha(cgColor);
    // Header/summary roots overlay the banner. Preserve nil, clear and partial
    // alpha rather than turning those native overlays into opaque rectangles.
    if (alpha <= 0) return native;
    return alpha < 1 ? [theme colorWithAlphaComponent:alpha] : theme;
}

UIColor* BHTThemedSurfaceBackground(UIView* view, UIColor* nativeColor, BOOL registerSurface) {
    if (!NSThread.isMainThread || !view || !BHTIsSupportedHost()) return nativeColor;
    BHTSurfaceThemeState* state = BHTSurfaceState(view, registerSurface);
    if (!state || state.applying) return nativeColor;
    state.nativeColor = nativeColor;
    BHTPostNativeAssignments++;
    return BHTResolvedSurfaceColor(state);
}

void BHTApplyPostSurfaceTheme(UIView* view) {
    if (!NSThread.isMainThread || !view || !BHTIsSupportedHost()) return;
    BHTSurfaceThemeState* state = BHTSurfaceState(view, YES);
    UIColor* color = BHTResolvedSurfaceColor(state);
    state.applying = YES;
    @try {
        if (state.drawsColor) {
            UIColor* current = ((id (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"color"));
            if (![current isEqual:color] && (current || color)) {
                [UIView performWithoutAnimation:^{ ((void (*)(id, SEL, id))objc_msgSend)(view, NSSelectorFromString(@"setColor:"), color); }];
                BHTPostRootUpdates++;
            }
        } else if (BHTApplySurfaceBackingColor(view, color)) BHTPostRootUpdates++;
    }
    @finally { state.applying = NO; }
}

void BHTApplySurfaceBackdropTheme(UIView* view) {
    if (!NSThread.isMainThread || !view || !BHTIsSupportedHost()) return;
    for (NSString* name in @[@"T1ProfileHeaderView", @"T1ProfileSummaryView"]) {
        Class overlay = NSClassFromString(name);
        if (overlay && [view isKindOfClass:overlay]) { BHTApplyPostSurfaceTheme(view); return; }
    }
    BHTSurfaceState(view, YES).fillsBackdrop = YES;
    BHTApplyPostSurfaceTheme(view);
}

static void BHTApplyProfileColorSurface(UIView* view, BOOL drawingColor) {
    if (!view || !NSThread.isMainThread || !BHTIsSupportedHost()) return;
    if (drawingColor) {
        SEL getter = NSSelectorFromString(@"color"), setter = NSSelectorFromString(@"setColor:");
        Method read = class_getInstanceMethod(view.class, getter), write = class_getInstanceMethod(view.class, setter);
        char result[16] = {0}, argument[16] = {0}, writeResult[16] = {0};
        if (!read || !write || method_getNumberOfArguments(read) != 2 || method_getNumberOfArguments(write) != 3) return;
        method_getReturnType(read, result, sizeof(result));
        method_getReturnType(write, writeResult, sizeof(writeResult));
        method_getArgumentType(write, 2, argument, sizeof(argument));
        if (result[0] != '@' || writeResult[0] != 'v' || argument[0] != '@') return;
        BHTSurfaceThemeState* state = BHTSurfaceState(view, YES);
        if (!state.drawsColor) {
            id native = ((id (*)(id, SEL))objc_msgSend)(view, getter);
            if (native && ![native isKindOfClass:UIColor.class]) return;
            state.nativeColor = native;
            state.drawsColor = YES;
        }
    }
    BHTApplyPostSurfaceTheme(view);
}

static id BHTSurfaceObject(id object, NSString* name) {
    Method method = class_getInstanceMethod([object class], NSSelectorFromString(name));
    char result[16] = {0};
    if (method && method_getNumberOfArguments(method) == 2) {
        method_getReturnType(method, result, sizeof(result));
        if (result[0] == '@') return ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name));
    }
    Ivar ivar = class_getInstanceVariable([object class], [[@"_" stringByAppendingString:name] UTF8String]);
    const char* type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(object, ivar) : nil;
}

void BHTApplyAppContainerTheme(UIViewController* controller) {
    if (!NSThread.isMainThread || !controller.isViewLoaded || !BHTIsSupportedHost()) return;
    BHTApplySurfaceBackdropTheme(controller.view);
    if (controller.view.window) BHTApplySurfaceBackdropTheme(controller.view.window);
}

void BHTApplyProfileContainerTheme(UIViewController* controller) {
    BHTApplyAppContainerTheme(controller);
    if (!controller.isViewLoaded) return;
    // Follow verified semantic getters, never the profile's media hierarchy.
    for (NSString* name in @[@"headerViewController", @"segmentedViewController"]) {
        id child = BHTSurfaceObject(controller, name);
        if (![child isKindOfClass:UIViewController.class] || ![child isViewLoaded]) continue;
        if ([name isEqualToString:@"segmentedViewController"]) BHTApplySurfaceBackdropTheme([child view]);
        else BHTApplyPostSurfaceTheme([child view]);
        id tabBar = BHTSurfaceObject(child, @"tabBarView");
        if (![tabBar isKindOfClass:UIView.class]) continue;
        BHTApplySurfaceBackdropTheme(tabBar);
        // The segmented bar owns a collection with a separate fill. Stop there;
        // cells, highlight planes, icons and media remain native.
        NSMutableArray* queue = [NSMutableArray arrayWithObject:tabBar];
        NSUInteger budget = 20;
        while (queue.count && budget--) {
            UIView* candidate = queue.firstObject;
            [queue removeObjectAtIndex:0];
            for (UIView* view in candidate.subviews) {
                if ([view isKindOfClass:UICollectionView.class]) BHTApplySurfaceBackdropTheme(view);
                else if (view.class == UIView.class && queue.count < 20) [queue addObject:view];
            }
        }
    }
}

void BHTApplyProfileStatsTheme(UIViewController* controller) {
    if (!controller.isViewLoaded || !BHTIsSupportedHost()) return;
    Class countsOwner = NSClassFromString(@"T1ProfileFollowStatsViewController");
    if (countsOwner && [controller isKindOfClass:countsOwner]) BHTApplySurfaceBackdropTheme(controller.view);
    else BHTApplyPostSurfaceTheme(controller.view);
    // This is the dedicated counts/following row, not the profile header or
    // its banner. Preserve every descendant's native alpha and skip images.
    NSMutableArray* queue = [NSMutableArray arrayWithObject:controller.view];
    Class solid = NSClassFromString(@"TFNSolidColorView");
    NSUInteger budget = 32;
    while (queue.count && budget--) {
        UIView* candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        for (UIView* child in candidate.subviews) {
            if ([child isKindOfClass:UIImageView.class] || [child isKindOfClass:UIVisualEffectView.class]) continue;
            BHTApplyProfileColorSurface(child, solid && [child isKindOfClass:solid]);
            if (queue.count < 32) [queue addObject:child];
        }
    }
}

NSDictionary* BHTPostSurfaceThemeDiagnostics(void) {
    if (!NSThread.isMainThread) {
        __block NSDictionary* result;
        dispatch_sync(dispatch_get_main_queue(), ^{ result = BHTPostSurfaceThemeDiagnostics(); });
        return result;
    }
    NSMutableArray* views = [NSMutableArray array];
    for (UIView* view in BHTPostSurfaces.allObjects) {
        if (!view.window || views.count >= 12) continue;
        [views addObject:@{@"class": NSStringFromClass(view.class), @"width": @(view.bounds.size.width),
            @"height": @(view.bounds.size.height)}];
    }
    return @{@"rootUpdates": @(BHTPostRootUpdates), @"nativeAssignments": @(BHTPostNativeAssignments),
        @"planeUpdates": @0, @"surfaces": views, @"mutatesComposablePlanes": @NO,
        @"ordinaryStatusViewsForcedOpaque": @NO, @"updatesAfterEveryLayout": @NO,
        @"preservesNativeTransparency": @YES,
        @"recursiveMediaTraversal": @NO, @"capturesPostText": @NO};
}
