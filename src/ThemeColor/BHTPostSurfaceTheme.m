#import "BHTPostSurfaceTheme.h"
#import "Palette.h"
#import "BHTThemePresets.h"
#import "Core/BHTSettings.h"
#import "Compatibility/BHTHostCompatibility.h"
#import <objc/runtime.h>
#import <objc/message.h>

BOOL BHTPostSurfaceIsBackground(NSString* name, CGRect frame, CGRect bounds) {
    static NSSet* backgrounds;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ backgrounds = [NSSet setWithArray:@[@"UIView", @"TFNSolidColorView", @"TFNTappableHighlightView", @"T1QuotedStatusCompactCardView"]]; });
    if (![backgrounds containsObject:name] ||
        CGRectIsEmpty(bounds) || CGRectIsEmpty(frame)) return NO;
    CGRect covered = CGRectIntersection(frame, bounds);
    return !CGRectIsNull(covered) && covered.size.width >= bounds.size.width * 0.8 && covered.size.height >= bounds.size.height * 0.8;
}

static NSHashTable<UIView*>* BHTPostSurfaces;
static NSHashTable<UIViewController*>* BHTThemeContainers;
static char BHTPostPlanesKey;
static char BHTPostChildrenKey;
static NSUInteger BHTPostRootUpdates, BHTPostPlaneUpdates;

static void BHTTrackPostTheme(void) {
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        BHTPostSurfaces = [NSHashTable weakObjectsHashTable];
        BHTThemeContainers = [NSHashTable weakObjectsHashTable];
        for (NSString* name in @[BHTThemeDidChangeNotification, BHTSettingsProfileDidApplyNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification* notification) {
                    for (UIView* view in BHTPostSurfaces.allObjects) if (view.window)
                        BHTApplyPostSurfaceTheme(view, [objc_getAssociatedObject(view, &BHTPostPlanesKey) boolValue]);
                    for (UIViewController* owner in BHTThemeContainers.allObjects) if (owner.isViewLoaded && owner.view.window)
                        BHTApplyAppContainerTheme(owner);
                }];
        }
    });
}

static id BHTPostObject(id object, NSString* name) {
    Method method = class_getInstanceMethod([object class], NSSelectorFromString(name));
    char result[16] = {0};
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    method_getReturnType(method, result, sizeof(result));
    return result[0] == '@' ? ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name)) : nil;
}

void BHTApplyPostSurfaceTheme(UIView* view, BOOL includePlanes) {
    if (!NSThread.isMainThread || !view || !BHTIsSupportedHost()) return;
    BHTTrackPostTheme();
    [BHTPostSurfaces addObject:view];
    NSNumber* previousMode = objc_getAssociatedObject(view, &BHTPostPlanesKey);
    if (!previousMode || previousMode.boolValue != includePlanes)
        objc_setAssociatedObject(view, &BHTPostPlanesKey, @(includePlanes), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIColor* color = [Palette currentBackgroundColor];
    if (color && ![view.backgroundColor isEqual:color]) { view.backgroundColor = color; BHTPostRootUpdates++; }
    if (!includePlanes) return;
    // These composable post hosts retain independent background planes. Only
    // inspect their own direct views, never recurse into media/text/card trees.
    NSMutableArray* candidates = [view.subviews mutableCopy];
    id set = BHTPostObject(view, @"viewSet");
    Ivar ivar = set ? class_getInstanceVariable([set class], "_views") : NULL;
    const char* type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    id values = type && type[0] == '@' ? object_getIvar(set, ivar) : nil;
    if ([values isKindOfClass:NSArray.class]) for (id value in values) {
        if ([value isKindOfClass:UIView.class] && ![candidates containsObject:value]) [candidates addObject:value];
        if (candidates.count >= 32) break;
    }
    NSMutableSet* classes = [NSMutableSet set];
    NSUInteger budget = 32;
    for (id value in candidates) {
        if (!budget--) break;
        if (![value isKindOfClass:UIView.class] || value == view) continue;
        UIView* plane = value;
        NSString* name = NSStringFromClass(plane.class);
        [classes addObject:name];
        if (plane.superview != view || !BHTPostSurfaceIsBackground(name, plane.frame, view.bounds)) continue;
        // A plain container with children may host a player or an image.
        if ([name isEqualToString:@"UIView"] && plane.subviews.count) continue;
        if ([name isEqualToString:@"TFNSolidColorView"]) {
            SEL selector = NSSelectorFromString(@"setColor:");
            Method method = class_getInstanceMethod(plane.class, selector);
            char result[16] = {0}, argument[16] = {0};
            if (method && method_getNumberOfArguments(method) == 3) {
                method_getReturnType(method, result, sizeof(result));
                method_getArgumentType(method, 2, argument, sizeof(argument));
                if (result[0] == 'v' && argument[0] == '@' && ![BHTPostObject(plane, @"color") isEqual:color]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(plane, selector, color);
                    BHTPostPlaneUpdates++;
                }
            }
        } else if (![plane.backgroundColor isEqual:color]) { plane.backgroundColor = color; BHTPostPlaneUpdates++; }
    }
    NSSet* previous = objc_getAssociatedObject(view, &BHTPostChildrenKey);
    if (![previous isEqualToSet:classes]) objc_setAssociatedObject(view, &BHTPostChildrenKey, [classes copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void BHTApplyAppContainerTheme(UIViewController* controller) {
    if (!NSThread.isMainThread || !controller.isViewLoaded || !BHTIsSupportedHost()) return;
    BHTTrackPostTheme();
    [BHTThemeContainers addObject:controller];
    UIColor* color = [Palette currentBackgroundColor];
    if (color && ![controller.view.backgroundColor isEqual:color]) controller.view.backgroundColor = color;
    UIWindow* window = controller.view.window;
    if (window && color && ![window.backgroundColor isEqual:color]) window.backgroundColor = color;
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
            @"height": @(view.bounds.size.height), @"directViewClasses":
            [(NSSet*)objc_getAssociatedObject(view, &BHTPostChildrenKey) allObjects] ?: @[]}];
    }
    return @{@"rootUpdates": @(BHTPostRootUpdates), @"planeUpdates": @(BHTPostPlaneUpdates),
        @"surfaces": views, @"recursiveMediaTraversal": @NO, @"capturesPostText": @NO};
}
