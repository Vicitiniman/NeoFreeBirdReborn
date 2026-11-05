#import "BHTComposeButtonVisibility.h"
#import "Core/BHTSettings.h"
#import <objc/runtime.h>
#import <objc/message.h>

@interface BHTComposeVisibilityState : NSObject
@property(nonatomic, weak) id owner;
@property(nonatomic) BOOL nativeHidden;
@property(nonatomic) BOOL nativeInteraction;
@property(nonatomic) BOOL nativeAccessibilityHidden;
@property(nonatomic) BOOL applying;
@end
@implementation BHTComposeVisibilityState @end
static char BHTComposeVisibilityKey;
static NSHashTable* BHTComposeButtonOwners;

static UIView* BHTComposeButtonForOwner(id owner) {
    SEL selector = NSSelectorFromString(@"floatingActionButton");
    Method method = class_getInstanceMethod([owner class], selector);
    char type[16] = {0};
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != '@') return nil;
    id button = ((id (*)(id, SEL))objc_msgSend)(owner, selector);
    Class native = NSClassFromString(@"TFNFloatingActionButton");
    return native && [button isKindOfClass:native] ? button : nil;
}

BOOL BHTComposeButtonRequestedHidden(UIView* button, BOOL nativeHidden) {
    BHTComposeVisibilityState* state = objc_getAssociatedObject(button, &BHTComposeVisibilityKey);
    if (!state.owner || state.applying || BHTComposeButtonForOwner(state.owner) != button) return nativeHidden;
    state.nativeHidden = nativeHidden;
    return [BHTSettings boolForKey:@"hide_compose_button"] || nativeHidden;
}

void BHTTrackComposeButtonOwner(id owner) {
    if (!NSThread.isMainThread || !owner) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        BHTComposeButtonOwners = [NSHashTable weakObjectsHashTable];
        [NSNotificationCenter.defaultCenter addObserverForName:BHTSettingsProfileDidApplyNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification* note) { BHTRefreshComposeButtonVisibility(); }];
    });
    [BHTComposeButtonOwners addObject:owner];
    UIView* button = BHTComposeButtonForOwner(owner);
    if (!button) return;
    BHTComposeVisibilityState* state = objc_getAssociatedObject(button, &BHTComposeVisibilityKey);
    if (!state) {
        state = [BHTComposeVisibilityState new];
        state.nativeHidden = button.hidden;
        state.nativeInteraction = button.userInteractionEnabled;
        state.nativeAccessibilityHidden = button.accessibilityElementsHidden;
        objc_setAssociatedObject(button, &BHTComposeVisibilityKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    state.owner = owner;
    BOOL hide = [BHTSettings boolForKey:@"hide_compose_button"];
    state.applying = YES;
    @try {
        button.hidden = hide || state.nativeHidden;
        button.userInteractionEnabled = hide ? NO : state.nativeInteraction;
        button.accessibilityElementsHidden = hide ? YES : state.nativeAccessibilityHidden;
    } @finally { state.applying = NO; }
}

void BHTRefreshComposeButtonLayout(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ BHTRefreshComposeButtonLayout(); }); return; }
    SEL selector = NSSelectorFromString(@"_t1_layoutFloatingActionButton");
    for (id owner in BHTComposeButtonOwners.allObjects) {
        Method method = class_getInstanceMethod([owner class], selector);
        char result[16] = {0};
        if (!method || method_getNumberOfArguments(method) != 2) continue;
        method_getReturnType(method, result, sizeof(result));
        if (result[0] == 'B' || result[0] == 'c') ((BOOL (*)(id, SEL))objc_msgSend)(owner, selector);
    }
}

void BHTRefreshComposeButtonVisibility(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ BHTRefreshComposeButtonVisibility(); }); return; }
    for (id owner in BHTComposeButtonOwners.allObjects) BHTTrackComposeButtonOwner(owner);
    BHTRefreshComposeButtonLayout();
}

NSDictionary* BHTComposeButtonVisibilityDiagnostics(void) {
    if (!NSThread.isMainThread) {
        __block NSDictionary* result;
        dispatch_sync(dispatch_get_main_queue(), ^{ result = BHTComposeButtonVisibilityDiagnostics(); });
        return result;
    }
    return @{@"hiddenByPreference": @([BHTSettings boolForKey:@"hide_compose_button"]),
        @"scopedToMainComposeOwner": @YES, @"registeredOwners": @(BHTComposeButtonOwners.allObjects.count)};
}
