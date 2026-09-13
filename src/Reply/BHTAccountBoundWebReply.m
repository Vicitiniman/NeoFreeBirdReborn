#import "Reply/BHTAccountBoundWebReply.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>

typedef NS_ENUM(NSUInteger, BHTAccountBoundWebReplyEvent) {
    BHTAccountBoundWebReplyEventEligible = 0,
    BHTAccountBoundWebReplyEventClassUnavailable,
    BHTAccountBoundWebReplyEventInitializerABIRejected,
    BHTAccountBoundWebReplyEventKeepInWebviewABIRejected,
    BHTAccountBoundWebReplyEventInitReturnedNil,
    BHTAccountBoundWebReplyEventInitException,
    BHTAccountBoundWebReplyEventAccountIdentityMismatch,
    BHTAccountBoundWebReplyEventPresentationAccepted,
    BHTAccountBoundWebReplyEventPresentationRejected,
    BHTAccountBoundWebReplyEventAlreadyPresented,
    BHTAccountBoundWebReplyEventDismissed,
    BHTAccountBoundWebReplyEventCustomFallbackUsed,
    BHTAccountBoundWebReplyEventCustomFallbackFailed,
    BHTAccountBoundWebReplyEventCount,
};

static NSString* const BHTAccountBoundWebReplyEventNames[] = {
    @"nativeRouteEligible",
    @"nativeClassUnavailable",
    @"nativeInitializerABIRejected",
    @"nativeKeepInWebviewABIRejected",
    @"nativeInitReturnedNil",
    @"nativeInitException",
    @"nativeAccountIdentityMismatch",
    @"nativePresentationAccepted",
    @"nativePresentationRejected",
    @"nativeAlreadyPresented",
    @"nativeDismissed",
    @"customFallbackAfterNativeFailure",
    @"allVisibleRoutesUnavailable",
};

_Static_assert(
    sizeof(BHTAccountBoundWebReplyEventNames) /
            sizeof(BHTAccountBoundWebReplyEventNames[0]) ==
        BHTAccountBoundWebReplyEventCount,
    "Account-bound web reply names must match the enum");

static atomic_ulong BHTAccountBoundWebReplyCounters[
    BHTAccountBoundWebReplyEventCount];
static atomic_bool BHTAccountBoundWebReplyKeepHookInstalled;
static atomic_bool BHTAccountBoundWebReplyTransitionPending;
static __weak UINavigationController*
    BHTActiveAccountBoundWebReplyNavigationController;
static char BHTAccountBoundWebReplyControllerMarkerKey;
static char BHTAccountBoundWebReplyDismissalDelegateKey;

static void BHTRecordAccountBoundWebReply(
    BHTAccountBoundWebReplyEvent event) {
    if (event >= BHTAccountBoundWebReplyEventCount) return;
    atomic_fetch_add_explicit(
        &BHTAccountBoundWebReplyCounters[event], 1,
        memory_order_relaxed);
}

static const char* BHTAccountBoundUnqualifiedType(
    const char* type) {
    while (type &&
           (*type == 'r' || *type == 'n' || *type == 'N' ||
            *type == 'o' || *type == 'O' || *type == 'R' ||
            *type == 'V')) {
        type++;
    }
    return type;
}

static BOOL BHTAccountBoundClassIsSubclassOfClass(
    Class candidate,
    Class expected) {
    if (!candidate || !expected) return NO;
    for (Class current = candidate;
         current;
         current = class_getSuperclass(current)) {
        if (current == expected) return YES;
    }
    return NO;
}

static BOOL BHTAccountBoundObjectGetterHasExactABI(
    Class cls,
    SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 2) {
        return NO;
    }
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* result =
        BHTAccountBoundUnqualifiedType(returnType);
    return result && *result == '@';
}

static BOOL BHTAccountBoundObjectMethodHasOneObjectArgumentExactABI(
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
        BHTAccountBoundUnqualifiedType(returnType);
    const char* argument =
        BHTAccountBoundUnqualifiedType(argumentType);
    return result && *result == '@' &&
           argument && *argument == '@';
}

static BOOL BHTAccountBoundInitializerHasExactABI(
    Class cls,
    SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 9) {
        return NO;
    }
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* result =
        BHTAccountBoundUnqualifiedType(returnType);
    if (!result || *result != '@') return NO;

    const char expectedTypes[] = {'@', '@', 'B', 'B', '@', '@', '@'};
    for (unsigned int index = 0; index < 7; index++) {
        char argumentType[16] = {0};
        method_getArgumentType(
            method, index + 2, argumentType,
            sizeof(argumentType));
        const char* argument =
            BHTAccountBoundUnqualifiedType(argumentType);
        if (!argument || *argument != expectedTypes[index]) {
            return NO;
        }
    }
    return YES;
}

static BOOL BHTAccountBoundReplyURLIsAllowed(NSURL* URL) {
    if (![URL isKindOfClass:NSURL.class] ||
        ![URL.scheme.lowercaseString isEqualToString:@"https"] ||
        ![URL.host.lowercaseString isEqualToString:@"x.com"] ||
        ![URL.lastPathComponent isEqualToString:@"tweet"]) {
        return NO;
    }
    return YES;
}

static BOOL BHTAccountBoundPresenterIsAvailable(
    UIViewController* presenter) {
    return presenter && presenter.viewIfLoaded.window &&
           !presenter.isBeingDismissed &&
           !presenter.isMovingFromParentViewController &&
           presenter.presentedViewController == nil;
}

@interface BHTAccountBoundWebReplyDismissalDelegate
    : NSObject <UIAdaptivePresentationControllerDelegate>
@end

@implementation BHTAccountBoundWebReplyDismissalDelegate

- (void)dismissVisibleReply:
    (__unused id)sender {
    UINavigationController* active =
        BHTActiveAccountBoundWebReplyNavigationController;
    if (!active) return;
    BHTActiveAccountBoundWebReplyNavigationController = nil;
    atomic_store_explicit(
        &BHTAccountBoundWebReplyTransitionPending,
        false, memory_order_release);
    UIViewController* dismissingController =
        active.presentingViewController ?: active;
    [dismissingController
        dismissViewControllerAnimated:YES
                           completion:^{
                               BHTRecordAccountBoundWebReply(
                                   BHTAccountBoundWebReplyEventDismissed);
                           }];
}

- (void)presentationControllerDidDismiss:
    (UIPresentationController*)presentationController {
    UINavigationController* active =
        BHTActiveAccountBoundWebReplyNavigationController;
    if (active != presentationController.presentedViewController) {
        return;
    }
    BHTActiveAccountBoundWebReplyNavigationController = nil;
    atomic_store_explicit(
        &BHTAccountBoundWebReplyTransitionPending,
        false, memory_order_release);
    BHTRecordAccountBoundWebReply(
        BHTAccountBoundWebReplyEventDismissed);
}

@end


BOOL BHTAccountBoundWebReplyOwnsController(id controller) {
    if (!controller) return NO;
    return [objc_getAssociatedObject(
        controller,
        &BHTAccountBoundWebReplyControllerMarkerKey) boolValue];
}

void BHTMarkAccountBoundWebReplyKeepInWebviewHookInstalled(void) {
    atomic_store_explicit(
        &BHTAccountBoundWebReplyKeepHookInstalled,
        true, memory_order_release);
}

static UINavigationController* BHTAccountBoundNavigationController(
    UIViewController* root) {
    Class hostNavigationClass =
        NSClassFromString(@"T1WebNavigationController");
    SEL initializer = @selector(initWithRootViewController:);
    if (BHTAccountBoundClassIsSubclassOfClass(
            hostNavigationClass,
            UINavigationController.class) &&
        BHTAccountBoundObjectMethodHasOneObjectArgumentExactABI(
            hostNavigationClass, initializer)) {
        @try {
            typedef id (*BHTNavigationInitializer)(
                id, SEL, UIViewController*);
            id navigation =
                ((BHTNavigationInitializer)objc_msgSend)(
                    [hostNavigationClass alloc], initializer, root);
            if ([navigation
                    isKindOfClass:UINavigationController.class]) {
                return navigation;
            }
        } @catch (__unused NSException* exception) {
        }
    }
    return [[UINavigationController alloc]
        initWithRootViewController:root];
}

BHTAccountBoundWebReplyResult BHTTryPresentAccountBoundWebReply(
    NSURL* replyURL,
    id account,
    UIViewController* presenter) {
    NSString* version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (![version isKindOfClass:NSString.class] ||
        ![version isEqualToString:@"12.24.1"] ||
        !NSThread.isMainThread || !account ||
        !BHTAccountBoundReplyURLIsAllowed(replyURL)) {
        return BHTAccountBoundWebReplyResultUnavailable;
    }

    if (atomic_load_explicit(
            &BHTAccountBoundWebReplyTransitionPending,
            memory_order_acquire)) {
        BHTRecordAccountBoundWebReply(
            BHTAccountBoundWebReplyEventAlreadyPresented);
        return BHTAccountBoundWebReplyResultAlreadyPresented;
    }
    UINavigationController* active =
        BHTActiveAccountBoundWebReplyNavigationController;
    if (active && active.viewIfLoaded.window &&
        !active.isBeingDismissed) {
        BHTRecordAccountBoundWebReply(
            BHTAccountBoundWebReplyEventAlreadyPresented);
        return BHTAccountBoundWebReplyResultAlreadyPresented;
    }
    BHTActiveAccountBoundWebReplyNavigationController = nil;

    BHTRecordAccountBoundWebReply(
        BHTAccountBoundWebReplyEventEligible);
    if (!BHTAccountBoundPresenterIsAvailable(presenter)) {
        BHTRecordAccountBoundWebReply(
            BHTAccountBoundWebReplyEventPresentationRejected);
        return BHTAccountBoundWebReplyResultUnavailable;
    }

    Class webClass = NSClassFromString(@"T1WebViewController");
    Class baseWebClass =
        NSClassFromString(@"T1BaseWebViewController");
    if (!BHTAccountBoundClassIsSubclassOfClass(
            webClass, UIViewController.class) ||
        !BHTAccountBoundClassIsSubclassOfClass(
            webClass, baseWebClass)) {
        BHTRecordAccountBoundWebReply(
            BHTAccountBoundWebReplyEventClassUnavailable);
        return BHTAccountBoundWebReplyResultUnavailable;
    }

    SEL initializer = NSSelectorFromString(
        @"initWithRootURL:account:shouldAuthenticate:shouldPresentAsNativePage:sourceStatus:scribeComponent:scribeParameters:");
    SEL accountGetter = NSSelectorFromString(@"account");
    if (!BHTAccountBoundInitializerHasExactABI(
            webClass, initializer) ||
        !BHTAccountBoundObjectGetterHasExactABI(
            webClass, accountGetter)) {
        BHTRecordAccountBoundWebReply(
            BHTAccountBoundWebReplyEventInitializerABIRejected);
        return BHTAccountBoundWebReplyResultUnavailable;
    }
    if (!atomic_load_explicit(
            &BHTAccountBoundWebReplyKeepHookInstalled,
            memory_order_acquire)) {
        BHTRecordAccountBoundWebReply(
            BHTAccountBoundWebReplyEventKeepInWebviewABIRejected);
        return BHTAccountBoundWebReplyResultUnavailable;
    }

    UIViewController* webController = nil;
    @try {
        typedef id (*BHTWebInitializer)(
            id, SEL, NSURL*, id, BOOL, BOOL, id, id, id);
        webController =
            ((BHTWebInitializer)objc_msgSend)(
                [webClass alloc], initializer,
                replyURL, account, YES, NO,
                nil, nil, nil);
    } @catch (__unused NSException* exception) {
        BHTRecordAccountBoundWebReply(
            BHTAccountBoundWebReplyEventInitException);
        return BHTAccountBoundWebReplyResultUnavailable;
    }
    if (![webController
            isKindOfClass:UIViewController.class]) {
        BHTRecordAccountBoundWebReply(
            BHTAccountBoundWebReplyEventInitReturnedNil);
        return BHTAccountBoundWebReplyResultUnavailable;
    }

    id controllerAccount = nil;
    @try {
        controllerAccount =
            ((id (*)(id, SEL))objc_msgSend)(
                webController, accountGetter);
    } @catch (__unused NSException* exception) {
        controllerAccount = nil;
    }
    if (controllerAccount != account) {
        BHTRecordAccountBoundWebReply(
            BHTAccountBoundWebReplyEventAccountIdentityMismatch);
        return BHTAccountBoundWebReplyResultUnavailable;
    }
    objc_setAssociatedObject(
        webController,
        &BHTAccountBoundWebReplyControllerMarkerKey,
        @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UINavigationController* navigation =
        BHTAccountBoundNavigationController(webController);
    if (![navigation
            isKindOfClass:UINavigationController.class]) {
        BHTRecordAccountBoundWebReply(
            BHTAccountBoundWebReplyEventPresentationRejected);
        return BHTAccountBoundWebReplyResultUnavailable;
    }
    if (UI_USER_INTERFACE_IDIOM() ==
        UIUserInterfaceIdiomPad) {
        navigation.modalPresentationStyle =
            UIModalPresentationFormSheet;
        CGFloat availableHeight = MAX(
            520.0,
            UIScreen.mainScreen.bounds.size.height - 96.0);
        navigation.preferredContentSize = CGSizeMake(
            640.0, MIN(780.0, availableHeight));
    } else {
        navigation.modalPresentationStyle =
            UIModalPresentationFullScreen;
    }

    BHTAccountBoundWebReplyDismissalDelegate* delegate =
        [BHTAccountBoundWebReplyDismissalDelegate new];
    objc_setAssociatedObject(
        navigation,
        &BHTAccountBoundWebReplyDismissalDelegateKey,
        delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIBarButtonItem* closeItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                            target:delegate
                            action:@selector(dismissVisibleReply:)];
    webController.navigationItem.leftBarButtonItem = closeItem;
    atomic_store_explicit(
        &BHTAccountBoundWebReplyTransitionPending,
        true, memory_order_release);
    @try {
        BHTActiveAccountBoundWebReplyNavigationController =
            navigation;
        [presenter presentViewController:navigation
                               animated:YES
                             completion:^{
                                 atomic_store_explicit(
                                     &BHTAccountBoundWebReplyTransitionPending,
                                     false, memory_order_release);
                                 webController.navigationItem
                                     .leftBarButtonItem = closeItem;
                             }];
        BOOL accepted =
            presenter.presentedViewController == navigation ||
            navigation.presentingViewController == presenter;
        if (!accepted) {
            BHTActiveAccountBoundWebReplyNavigationController = nil;
            atomic_store_explicit(
                &BHTAccountBoundWebReplyTransitionPending,
                false, memory_order_release);
            BHTRecordAccountBoundWebReply(
                BHTAccountBoundWebReplyEventPresentationRejected);
            return BHTAccountBoundWebReplyResultUnavailable;
        }
        navigation.presentationController.delegate = delegate;
    } @catch (__unused NSException* exception) {
        BHTActiveAccountBoundWebReplyNavigationController = nil;
        atomic_store_explicit(
            &BHTAccountBoundWebReplyTransitionPending,
            false, memory_order_release);
        BHTRecordAccountBoundWebReply(
            BHTAccountBoundWebReplyEventPresentationRejected);
        return BHTAccountBoundWebReplyResultUnavailable;
    }

    BHTRecordAccountBoundWebReply(
        BHTAccountBoundWebReplyEventPresentationAccepted);
    return BHTAccountBoundWebReplyResultPresented;
}

void BHTRecordAccountBoundWebReplyCustomFallback(
    BOOL presented) {
    BHTRecordAccountBoundWebReply(
        presented
            ? BHTAccountBoundWebReplyEventCustomFallbackUsed
            : BHTAccountBoundWebReplyEventCustomFallbackFailed);
}

NSDictionary* BHTAccountBoundWebReplyDiagnosticSnapshot(void) {
    NSMutableDictionary* counters =
        [NSMutableDictionary
            dictionaryWithCapacity:
                BHTAccountBoundWebReplyEventCount];
    for (NSUInteger index = 0;
         index < BHTAccountBoundWebReplyEventCount; index++) {
        counters[BHTAccountBoundWebReplyEventNames[index]] =
            @(atomic_load_explicit(
                &BHTAccountBoundWebReplyCounters[index],
                memory_order_relaxed));
    }
    return @{
        @"counters": [counters copy],
        @"keepInWebviewHookInstalled":
            @(atomic_load_explicit(
                &BHTAccountBoundWebReplyKeepHookInstalled,
                memory_order_acquire)),
        @"transitionPending":
            @(atomic_load_explicit(
                &BHTAccountBoundWebReplyTransitionPending,
                memory_order_acquire)),
        @"x12_9Only": @YES,
        @"passesHookAccountByObjectIdentity": @YES,
        @"createsFreshControllerForEachReply": @YES,
        @"usesVisibleHostController": @YES,
        @"providesVisibleCloseControl": @YES,
        @"accessesHostWebView": @NO,
        @"readsCookiesOrTokens": @NO,
        @"injectsPageScripts": @NO,
        @"inspectsRequestBodies": @NO,
        @"capturesAccountData": @NO,
        @"capturesStatusIdentifiers": @NO,
        @"capturesRawErrors": @NO,
        @"observesSendCompletion": @NO,
        @"postsThroughHiddenWebView": @NO,
    };
}
