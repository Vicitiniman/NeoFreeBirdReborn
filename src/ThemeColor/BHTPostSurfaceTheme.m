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

UIColor* BHTThemedSurfaceBackground(UIView* view, UIColor* nativeColor, BOOL registerSurface) {
    if (!NSThread.isMainThread || !view || !BHTIsSupportedHost()) return nativeColor;
    BHTSurfaceThemeState* state = BHTSurfaceState(view, registerSurface);
    if (!state || state.applying) return nativeColor;
    state.nativeColor = nativeColor;
    BHTPostNativeAssignments++;
    // No preset means preserve X's clear/opaque choice, including nil.
    return [Palette customThemeColorForRole:BHTThemeColorBackgroundKey] ?: nativeColor;
}

void BHTApplyPostSurfaceTheme(UIView* view) {
    if (!NSThread.isMainThread || !view || !BHTIsSupportedHost()) return;
    BHTSurfaceThemeState* state = BHTSurfaceState(view, YES);
    UIColor* color = [Palette customThemeColorForRole:BHTThemeColorBackgroundKey] ?: state.nativeColor;
    state.applying = YES;
    @try { if (BHTApplySurfaceBackingColor(view, color)) BHTPostRootUpdates++; }
    @finally { state.applying = NO; }
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
    BHTApplyPostSurfaceTheme(controller.view);
    if (controller.view.window) BHTApplyPostSurfaceTheme(controller.view.window);
}

void BHTApplyProfileContainerTheme(UIViewController* controller) {
    BHTApplyAppContainerTheme(controller);
    if (!controller.isViewLoaded) return;
    // Follow verified semantic getters, never the profile's media hierarchy.
    for (NSString* name in @[@"headerViewController", @"segmentedViewController"]) {
        id child = BHTSurfaceObject(controller, name);
        if (![child isKindOfClass:UIViewController.class] || ![child isViewLoaded]) continue;
        BHTApplyPostSurfaceTheme([child view]);
        id tabBar = BHTSurfaceObject(child, @"tabBarView");
        if (![tabBar isKindOfClass:UIView.class]) continue;
        BHTApplyPostSurfaceTheme(tabBar);
        // The segmented bar owns a collection with a separate fill. Stop there;
        // cells, highlight planes, icons and media remain native.
        NSMutableArray* queue = [NSMutableArray arrayWithObject:tabBar];
        NSUInteger budget = 20;
        while (queue.count && budget--) {
            UIView* candidate = queue.firstObject;
            [queue removeObjectAtIndex:0];
            for (UIView* view in candidate.subviews) {
                if ([view isKindOfClass:UICollectionView.class]) BHTApplyPostSurfaceTheme(view);
                else if (view.class == UIView.class && queue.count < 20) [queue addObject:view];
            }
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
        @"recursiveMediaTraversal": @NO, @"capturesPostText": @NO};
}
