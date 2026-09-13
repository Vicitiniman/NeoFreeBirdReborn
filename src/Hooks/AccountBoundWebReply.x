//
//  AccountBoundWebReply.x
//  NeoFreeBird
//
//  Keeps only NeoFreeBird's marked, visible X 12.9 reply controller inside
//  the host web view. Every unmarked controller preserves X's original result.
//

#import "Reply/BHTAccountBoundWebReply.h"

#import <objc/runtime.h>

static const char* BHTAccountBoundHookUnqualifiedType(
    const char* type) {
    while (type &&
           (*type == 'r' || *type == 'n' || *type == 'N' ||
            *type == 'o' || *type == 'O' || *type == 'R' ||
            *type == 'V')) {
        type++;
    }
    return type;
}
static BOOL BHTAccountBoundKeepMethodHasExactABI(
    Class cls,
    SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 3) {
        return NO;
    }
    char returnType[16] = {0};
    char argumentType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    method_getArgumentType(method, 2, argumentType,
                           sizeof(argumentType));
    const char* result =
        BHTAccountBoundHookUnqualifiedType(returnType);
    const char* argument =
        BHTAccountBoundHookUnqualifiedType(argumentType);
    return result && *result == 'B' &&
           argument && *argument == 'q';
}

%group BHTAccountBoundWebReplyHooks

%hook T1WebViewController

- (BOOL)doesURLResultTypeOpenInWebview:(NSInteger)resultType {
    if (BHTAccountBoundWebReplyOwnsController(self)) {
        return YES;
    }
    return %orig(resultType);
}

%end

%end

%ctor {
    NSString* version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (![version isKindOfClass:NSString.class] ||
        ![version isEqualToString:@"12.24.1"]) {
        return;
    }
    Class webClass = NSClassFromString(@"T1WebViewController");
    SEL selector = NSSelectorFromString(
        @"doesURLResultTypeOpenInWebview:");
    if (BHTAccountBoundKeepMethodHasExactABI(
            webClass, selector)) {
        %init(BHTAccountBoundWebReplyHooks);
        BHTMarkAccountBoundWebReplyKeepInWebviewHookInstalled();
    }
}
