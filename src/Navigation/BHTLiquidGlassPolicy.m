#import "BHTLiquidGlassPolicy.h"
#include <math.h>
#import <objc/runtime.h>
#import <objc/message.h>

NSNumber* BHTLiquidGlassNavigationOverride(BOOL enabled, BOOL classic, BOOL available) {
    // Our dock uses the verified native entry/delegate pipeline, independent
    // of X's glass rollout and the device's material-rendering API.
    (void)available;
    return enabled || classic ? @NO : nil;
}

CGRect BHTGlassDockFrame(CGRect native, CGRect host, CGFloat safeBottom, NSUInteger count, BOOL vertical, BOOL labels) {
    if (!count || CGRectIsEmpty(native) || CGRectIsEmpty(host) ||
        !isfinite(native.origin.x) || !isfinite(native.origin.y) ||
        !isfinite(native.size.width) || !isfinite(native.size.height) ||
        !isfinite(host.size.width) || !isfinite(host.size.height)) return CGRectZero;
    if (vertical) {
        CGFloat width = MIN(84, MAX(0, native.size.width - 12));
        CGFloat height = MIN(MAX(0, host.size.height - 24), count * 60.0 + 24);
        if (width < 44 || height < 44) return CGRectZero;
        CGFloat y = MAX(CGRectGetMinY(host) + 12, MIN(CGRectGetMidY(native) - height / 2, CGRectGetMaxY(host) - height - 12));
        return CGRectMake(CGRectGetMidX(native) - width / 2, y, width, height);
    }
    CGFloat available = MAX(0, host.size.height - MAX(0, safeBottom));
    CGFloat height = MIN(labels ? 66 : 58, available);
    CGFloat width = MIN(600, MAX(0, MIN(native.size.width, host.size.width) - 40));
    if (width < 44 || height < 44) return CGRectZero;
    CGFloat bottom = MIN(CGRectGetMinY(host) + available, CGRectGetMaxY(native));
    available = MAX(0, bottom - CGRectGetMinY(host));
    height = MIN(height, available);
    if (height < 44) return CGRectZero;
    CGFloat gap = MIN(10, MAX(0, available - height));
    return CGRectMake(CGRectGetMidX(native) - width / 2,
        bottom - height - gap, width, height);
}

CGRect BHTGlassDockCompactFrame(CGRect expanded, BOOL rightToLeft) {
    if (CGRectIsEmpty(expanded)) return CGRectZero;
    CGFloat diameter = MIN(58, MIN(expanded.size.width, expanded.size.height));
    return CGRectMake(rightToLeft ? CGRectGetMaxX(expanded) - diameter : expanded.origin.x,
        CGRectGetMaxY(expanded) - diameter, diameter, diameter);
}

CGRect BHTGlassDockVisibleFrame(CGRect nativeFrame, BOOL overlayEnabled, BOOL activeDockedContent) {
    if (!overlayEnabled || activeDockedContent || CGRectIsEmpty(nativeFrame) || CGRectIsInfinite(nativeFrame)) return nativeFrame;
    // Native layout measures MIN Y, not height. Anchor the empty reservation
    // at the old bar's bottom; CGRectZero would reserve the entire screen.
    return CGRectMake(nativeFrame.origin.x, CGRectGetMaxY(nativeFrame), nativeFrame.size.width, 0);
}

CGFloat BHTGlassDockOpacity(NSInteger percentage, BOOL reduceTransparency) {
    return reduceTransparency ? 1 : MIN(100, MAX(0, percentage)) / 100.0;
}

BOOL BHTGlassOpacityPreferenceIsValid(id value) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
    double opacity = [value doubleValue];
    return isfinite(opacity) && opacity >= 0 && opacity <= 100 && opacity == floor(opacity);
}

CGRect BHTGlassDockAvoidedComposeFrame(CGRect nativeFrame, CGRect dockFrame) {
    if (CGRectIsEmpty(nativeFrame) || CGRectIsEmpty(dockFrame) || !CGRectIntersectsRect(nativeFrame, dockFrame)) return nativeFrame;
    nativeFrame.origin.y = MAX(0, MIN(nativeFrame.origin.y, CGRectGetMinY(dockFrame) - nativeFrame.size.height - 12));
    return nativeFrame;
}

void BHTGlassDockReveal(BHTGlassDockScrollState* state, BOOL manualOverride) {
    if (!state) return;
    state->collapsed = NO;
    state->distance = 0;
    state->direction = 0;
    if (manualOverride) state->manuallyExpanded = YES;
}

void BHTGlassDockResetScroll(BHTGlassDockScrollState* state, BOOL samePage) {
    if (!state) return;
    BOOL manual = samePage && state->manuallyExpanded;
    *state = (BHTGlassDockScrollState){0};
    state->manuallyExpanded = manual;
}

BOOL BHTGlassDockObserveScroll(BHTGlassDockScrollState* state, CGFloat offset, CGFloat maximumOffset,
                              BOOL dragging, BOOL decelerating, BOOL pinned) {
    if (!state || !isfinite(offset) || !isfinite(maximumOffset)) return NO;
    BOOL previous = state->collapsed;
    if (state->manuallyExpanded) {
        state->collapsed = NO;
        state->lastOffset = offset;
        state->hasOffset = YES;
        state->distance = 0;
        state->direction = 0;
        return previous != state->collapsed;
    }
    if (pinned || maximumOffset < 1 || offset <= 2) BHTGlassDockReveal(state, NO);
    if (pinned || maximumOffset < 1 || offset < 0 || offset > maximumOffset) {
        state->lastOffset = MAX(0, MIN(offset, MAX(0, maximumOffset)));
        state->hasOffset = YES;
        state->distance = 0;
        state->direction = 0;
        return previous != state->collapsed;
    }
    if (!state->hasOffset || (!dragging && !decelerating)) {
        state->lastOffset = offset;
        state->hasOffset = YES;
        state->distance = 0;
        return previous != state->collapsed;
    }
    CGFloat delta = offset - state->lastOffset;
    state->lastOffset = offset;
    // Ignore native restoration/layout jumps, and use hysteresis for finger jitter.
    if (fabs(delta) > 240) { state->distance = 0; state->direction = 0; return previous != state->collapsed; }
    if (fabs(delta) < 0.5) return previous != state->collapsed;
    NSInteger direction = delta > 0 ? 1 : -1;
    if (direction != state->direction) { state->direction = direction; state->distance = 0; }
    state->distance += fabs(delta);
    if (!state->collapsed && direction > 0 && state->distance >= 72) {
        state->collapsed = YES;
        state->distance = 0;
    } else if (state->collapsed && direction < 0 && state->distance >= 12) {
        BHTGlassDockReveal(state, NO);
    }
    return previous != state->collapsed;
}

CGSize BHTGlassDockContentSize(CGSize bounds, NSUInteger count, BOOL vertical) {
    return vertical ? CGSizeMake(bounds.width, MAX(bounds.height, count * 52.0 + 16)) :
        CGSizeMake(MAX(bounds.width, count * 52.0 + 16), bounds.height);
}

CGRect BHTGlassDockItemFrame(CGSize bounds, NSUInteger index, NSUInteger count, BOOL vertical) {
    if (!count || index >= count) return CGRectZero;
    CGSize content = BHTGlassDockContentSize(bounds, count, vertical);
    CGFloat length = ((vertical ? content.height : content.width) - 16) / count;
    return vertical ? CGRectMake(0, 8 + index * length, content.width, length) :
        CGRectMake(8 + index * length, 0, length, content.height);
}

NSString* BHTGlassDockSymbol(NSString* page, BOOL selected) {
    static NSDictionary* symbols;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ symbols = @{@"home": @"house", @"guide": @"magnifyingglass", @"search": @"magnifyingglass",
        @"ntab": @"bell", @"notifications": @"bell", @"likes": @"heart", @"profile": @"person.crop.circle",
        @"messages": @"bubble.left.and.bubble.right", @"chat": @"bubble.left.and.bubble.right",
        @"bookmarks": @"bookmark", @"communities": @"person.3", @"spaces": @"waveform",
        @"news": @"newspaper", @"lists": @"list.bullet", @"grok": @"sparkles", @"settings": @"gearshape"}; });
    NSString* symbol = symbols[page] ?: @"square.grid.2x2";
    if (selected && ![@[@"magnifyingglass", @"waveform", @"list.bullet", @"sparkles"] containsObject:symbol])
        return [symbol stringByAppendingString:@".fill"];
    return symbol;
}

static id BHTGlassDockObject(id object, NSString* name) {
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod([object class], selector);
    char result[16] = {0};
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    method_getReturnType(method, result, sizeof(result));
    return result[0] == '@' ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

BOOL BHTGlassDockCanRoute(id owner, BOOL longPress) {
    SEL selector = NSSelectorFromString(longPress ? @"customTabBar:longPressOnTabAtIndex:withView:" :
        @"customTabBar:selectTabAtIndex:withView:");
    Method method = class_getInstanceMethod([owner class], selector);
    if (!method || method_getNumberOfArguments(method) != 5) return NO;
    char result[16] = {0}, bar[16] = {0}, index[16] = {0}, view[16] = {0};
    method_getReturnType(method, result, sizeof(result));
    method_getArgumentType(method, 2, bar, sizeof(bar));
    method_getArgumentType(method, 3, index, sizeof(index));
    method_getArgumentType(method, 4, view, sizeof(view));
    if (!(result[0] == 'v' && bar[0] == '@' && (index[0] == 'q' || index[0] == 'Q') && view[0] == '@')) return NO;
    if (longPress) return YES;
    id native = BHTGlassDockObject(owner, @"tabBar");
    Method select = class_getInstanceMethod([native class], NSSelectorFromString(@"_selectTabAtIndex:sendControlAction:"));
    char send[16] = {0};
    if (!select || method_getNumberOfArguments(select) != 4) return NO;
    method_getReturnType(select, result, sizeof(result));
    method_getArgumentType(select, 2, index, sizeof(index));
    method_getArgumentType(select, 3, send, sizeof(send));
    return result[0] == 'v' && (index[0] == 'q' || index[0] == 'Q') && (send[0] == 'B' || send[0] == 'c');
}

BOOL BHTGlassDockRoute(id owner, id originalTab, BOOL longPress) {
    if (!originalTab || !BHTGlassDockCanRoute(owner, longPress)) return NO;
    NSArray* tabs = BHTGlassDockObject(owner, @"tabViews");
    id bar = BHTGlassDockObject(owner, @"tabBar");
    if (![tabs isKindOfClass:NSArray.class] || !bar) return NO;
    NSUInteger index = [tabs indexOfObjectIdenticalTo:originalTab];
    if (index == NSNotFound) return NO;
    if (!longPress) {
        // Replay the real selection entry point so the stock selection state
        // changes before its delegate action, including tapping Home again.
        ((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(bar,
            NSSelectorFromString(@"_selectTabAtIndex:sendControlAction:"), (NSInteger)index, YES);
        return YES;
    }
    SEL selector = NSSelectorFromString(longPress ? @"customTabBar:longPressOnTabAtIndex:withView:" :
        @"customTabBar:selectTabAtIndex:withView:");
    ((void (*)(id, SEL, id, NSInteger, id))objc_msgSend)(owner, selector, bar, (NSInteger)index, originalTab);
    return YES;
}
