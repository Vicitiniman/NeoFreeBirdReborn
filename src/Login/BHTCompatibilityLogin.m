#import "Login/BHTCompatibilityLogin.h"

#import "Reply/BHTDetailedReplyDiagnostics.h"

#import "Compatibility/BHTCompatibilityReporter.h"
#import "Core/BHTBundle.h"

#import <WebKit/WebKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <stdbool.h>
#import <stdint.h>
#import <string.h>

static NSString* const BHTCompatibilityTargetVersion = @"12.9";
static NSString* const BHTMetricsHandlerName = @"bht";
static const NSTimeInterval BHTCompatibilityMinimumPreflightDuration = 12.0;

@protocol BHTXAuthPasswordCommandInitializing <NSObject>
// X 12.9 encodes this completion block as v28@?0B8@12@20.
- (instancetype)
    initWithContext:(id)context
          accountID:(id)accountID
        authContext:(id)authContext
         identifier:(NSString*)identifier
           password:(NSString*)password
     simCountryCode:(id)simCountryCode
httpRequestConfiguration:(id)requestConfiguration
supportOneFactorAuthorization:(BOOL)supportOneFactorAuthorization
   knownDeviceToken:(id)knownDeviceToken
          uiMetrics:(NSString* _Nullable)metrics
   authTokenStorage:(id)authTokenStorage
             source:(NSUInteger)source
responseModelBuilder:(id)responseBuilder
    completionBlock:
        (void (^)(BOOL success, id response, id error))completion;
@end

@protocol BHTNativeAccountInitializing <NSObject>
- (instancetype)initWithUsername:(NSString*)username
                          userID:(uint64_t)userID;
- (void)updateUserInfoAndCredentialsWithToken:(NSString*)token
                                       secret:(NSString*)secret
                                     username:(NSString*)username;
@end

typedef NS_ENUM(NSUInteger, BHTCompatibilityLoginEvent) {
    BHTCompatibilityLoginEventPresented = 0,
    BHTCompatibilityLoginEventAttempted,
    BHTCompatibilityLoginEventMetricsResolved,
    BHTCompatibilityLoginEventMetricsTimedOut,
    BHTCompatibilityLoginEventMetricsCollectorAttached,
    BHTCompatibilityLoginEventMetricsResolvedFromNavigation,
    BHTCompatibilityLoginEventMetricsResolvedFromScript,
    BHTCompatibilityLoginEventMinimumPreflightElapsed,
    BHTCompatibilityLoginEventCommandStarted,
    BHTCompatibilityLoginEventCommandCompletedSuccessfully,
    BHTCompatibilityLoginEventCommandCompletedUnsuccessfully,
    BHTCompatibilityLoginEventCommandPayloadPresent,
    BHTCompatibilityLoginEventCommandFailureObjectPresent,
    BHTCompatibilityLoginEventChallengeRecoveredFromFailedCompletion,
    BHTCompatibilityLoginEventChallengeRecoveredFromFailureObject,
    BHTCompatibilityLoginEventRejectionWithoutPayload,
    BHTCompatibilityLoginEventIdentifierNormalized,
    BHTCompatibilityLoginEventAuthenticated,
    BHTCompatibilityLoginEventChallengeRequired,
    BHTCompatibilityLoginEventChallengePresented,
    BHTCompatibilityLoginEventAccountRegistered,
    BHTCompatibilityLoginEventFailed,
    BHTCompatibilityLoginEventCount,
};

static atomic_ulong
    BHTCompatibilityLoginCounters[BHTCompatibilityLoginEventCount];
static atomic_ulong BHTCompatibilityAddAccountEntryInstalled;
static atomic_ulong BHTCompatibilityAddAccountEntryOpened;
static atomic_ulong BHTCompatibilityAccountHandoffAttempted;
static atomic_ulong BHTCompatibilityAccountHandoffDispatched;
static atomic_ulong BHTCompatibilityAccountHandoffFailed;
static atomic_ulong BHTCompatibilityNativeInitialAttempted;
static atomic_ulong BHTCompatibilityNativeInitialDispatched;
static atomic_ulong BHTCompatibilityNativeInitialCallbackInvoked;
static atomic_ulong BHTCompatibilityNativeInitialFailed;
static atomic_bool BHTCompatibilityNativeInitialDispatchPending;
static __weak UIViewController*
    BHTCompatibilityNativeInitialPresentedController;
static atomic_ulong BHTCompatibilityNativeAddAccountAttempted;
static atomic_ulong BHTCompatibilityNativeAddAccountDispatched;
static atomic_ulong BHTCompatibilityNativeAddAccountFailed;
static atomic_bool BHTCompatibilityPreLoginReportSharePending;
static NSString* BHTCompatibilityLoginLastStage = @"idle";
static NSString* BHTCompatibilityLoginLastFailure = @"none";
static BOOL BHTCompatibilityLastCommandSucceeded;
static BOOL BHTCompatibilityLastCommandPayloadPresent;
static BOOL BHTCompatibilityLastCommandFailureObjectPresent;
static NSString* BHTCompatibilityLastCommandPayloadClass = @"none";
static NSString* BHTCompatibilityLastCommandFailureClass = @"none";
static NSString* BHTCompatibilityLastCommandFailureDomain = @"none";
static NSInteger BHTCompatibilityLastCommandFailureCode;
static __weak UIViewController*
    BHTCompatibilityPresentedSignInController;
static char BHTCompatibilityEntryButtonKey;
static char BHTCompatibilityReportButtonKey;
static char BHTCompatibilityEntryTargetKey;
static char BHTCompatibilityAddAccountItemKey;
static char BHTCompatibilityAddAccountTargetKey;
static void* BHTCompatibilityFrameworkHandle;

static NSObject* BHTCompatibilityLoginLock(void) {
    static NSObject* lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static NSString* BHTCompatibilityLocalized(NSString* key) {
    return [[BHTBundle sharedBundle] localizedStringForKey:key];
}

static void BHTCompatibilitySetStage(
    NSString* stage,
    NSString* failureCategory) {
    @synchronized(BHTCompatibilityLoginLock()) {
        if (stage.length > 0) {
            BHTCompatibilityLoginLastStage = [stage copy];
        }
        if (failureCategory.length > 0) {
            BHTCompatibilityLoginLastFailure =
                [failureCategory copy];
        }
    }
}

static void BHTCompatibilityRecord(
    BHTCompatibilityLoginEvent event,
    NSString* stage,
    NSString* failureCategory) {
    if (event < BHTCompatibilityLoginEventCount) {
        atomic_fetch_add_explicit(
            &BHTCompatibilityLoginCounters[event], 1,
            memory_order_relaxed);
    }
    BHTCompatibilitySetStage(stage, failureCategory);
}

static NSString* BHTCompatibilityDiagnosticClassName(id value) {
    if (!value) return @"none";
    Class cls = object_getClass(value);
    const char* name = cls ? class_getName(cls) : NULL;
    if (!name) return @"unknown";
    NSString* result = [NSString stringWithUTF8String:name];
    if (result.length == 0) return @"unknown";
    return result.length <= 128
               ? result
               : [result substringToIndex:128];
}

static NSString* BHTCompatibilityBoundedFailureDomain(id failure) {
    if (![failure isKindOfClass:NSError.class]) return @"none";
    NSString* domain = ((NSError*)failure).domain;
    if (domain.length == 0) return @"none";
    return domain.length <= 128
               ? domain
               : [domain substringToIndex:128];
}

static NSInteger BHTCompatibilityFailureCode(id failure) {
    return [failure isKindOfClass:NSError.class]
               ? ((NSError*)failure).code
               : 0;
}

static void BHTCompatibilityRecordCommandCompletion(
    BOOL success, id payload, id failure) {
    BHTCompatibilityRecord(
        success
            ? BHTCompatibilityLoginEventCommandCompletedSuccessfully
            : BHTCompatibilityLoginEventCommandCompletedUnsuccessfully,
        success ? @"command_completed" : @"command_rejected", nil);
    if (payload) {
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventCommandPayloadPresent,
            nil, nil);
    }
    if (failure) {
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventCommandFailureObjectPresent,
            nil, nil);
    }
    @synchronized(BHTCompatibilityLoginLock()) {
        BHTCompatibilityLastCommandSucceeded = success;
        BHTCompatibilityLastCommandPayloadPresent = payload != nil;
        BHTCompatibilityLastCommandFailureObjectPresent = failure != nil;
        BHTCompatibilityLastCommandPayloadClass =
            BHTCompatibilityDiagnosticClassName(payload);
        BHTCompatibilityLastCommandFailureClass =
            BHTCompatibilityDiagnosticClassName(failure);
        BHTCompatibilityLastCommandFailureDomain =
            BHTCompatibilityBoundedFailureDomain(failure);
        BHTCompatibilityLastCommandFailureCode =
            BHTCompatibilityFailureCode(failure);
    }
}

static NSString* BHTCompatibilityFailureCategory(
    id failure, BOOL payloadPresent) {
    if ([failure isKindOfClass:NSError.class] &&
        [((NSError*)failure).domain isEqualToString:NSURLErrorDomain]) {
        return @"network_failure";
    }
    return payloadPresent
               ? @"authentication_rejected_with_payload"
               : @"authentication_rejected";
}

static NSString* BHTNormalizedCompatibilityIdentifier(
    NSString* identifier, BOOL* didNormalize) {
    if (didNormalize) *didNormalize = NO;
    NSString* normalized = [identifier
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![normalized hasPrefix:@"@"] || normalized.length <= 1) {
        return normalized;
    }
    NSString* candidate = [normalized substringFromIndex:1];
    static NSCharacterSet* invalidHandleCharacters;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        invalidHandleCharacters = [[NSCharacterSet
            characterSetWithCharactersInString:
                @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"]
            invertedSet];
    });
    if ([candidate rangeOfCharacterFromSet:
                       invalidHandleCharacters].location != NSNotFound) {
        return normalized;
    }
    if (didNormalize) *didNormalize = YES;
    return candidate;
}

static NSString* BHTAppVersion(void) {
    id value = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static BOOL BHTCompatibilityVersionIsSupported(void) {
    return [BHTAppVersion()
        isEqualToString:BHTCompatibilityTargetVersion];
}

static void BHTLoadCompatibilityFrameworkIfNeeded(void) {
    if (NSClassFromString(
            @"TFSTwitterAPIXAuthPasswordCommand")) {
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* frameworksPath =
            NSBundle.mainBundle.privateFrameworksPath;
        NSString* binaryPath = [[frameworksPath
            stringByAppendingPathComponent:
                @"TwitterSPMMigration.framework"]
            stringByAppendingPathComponent:
                @"TwitterSPMMigration"];
        if (binaryPath.length > 0) {
            BHTCompatibilityFrameworkHandle = dlopen(
                binaryPath.fileSystemRepresentation,
                RTLD_LAZY | RTLD_LOCAL);
        }
    });
}

static BOOL BHTClassResponds(
    NSString* className, NSString* selectorName) {
    Class cls = NSClassFromString(className);
    return cls &&
           [cls respondsToSelector:NSSelectorFromString(selectorName)];
}

static id BHTGuestAccountIdentifier(void) {
    void* address =
        dlsym(RTLD_DEFAULT, "TFSTwitterAPIGuestAccountID");
    if (!address && BHTCompatibilityFrameworkHandle) {
        address = dlsym(
            BHTCompatibilityFrameworkHandle,
            "TFSTwitterAPIGuestAccountID");
    }
    if (!address) return nil;
    __unsafe_unretained id* value =
        (__unsafe_unretained id*)address;
    return value ? *value : nil;
}

static const char* BHTUnqualifiedObjCType(const char* type) {
    while (type && strchr("rnNoORV", type[0]) != NULL) {
        type++;
    }
    return type;
}

static BOOL BHTSignatureArgumentIsObject(
    NSMethodSignature* signature, NSUInteger index) {
    if (!signature || index >= signature.numberOfArguments) {
        return NO;
    }
    const char* type = BHTUnqualifiedObjCType(
        [signature getArgumentTypeAtIndex:index]);
    return type && type[0] == '@';
}

static BOOL BHTSignatureArgumentIsInteger(
    NSMethodSignature* signature, NSUInteger index) {
    if (!signature || index >= signature.numberOfArguments) {
        return NO;
    }
    const char* type = BHTUnqualifiedObjCType(
        [signature getArgumentTypeAtIndex:index]);
    return type && strchr("qQlL", type[0]) != NULL;
}

static BOOL BHTSignatureArgumentIsNSUInteger(
    NSMethodSignature* signature, NSUInteger index) {
    if (!signature || index >= signature.numberOfArguments) {
        return NO;
    }
    const char* type = BHTUnqualifiedObjCType(
        [signature getArgumentTypeAtIndex:index]);
    return type && strcmp(type, @encode(NSUInteger)) == 0;
}

static BOOL BHTSignatureArgumentIsBoolean(
    NSMethodSignature* signature, NSUInteger index) {
    if (!signature || index >= signature.numberOfArguments) {
        return NO;
    }
    const char* type = BHTUnqualifiedObjCType(
        [signature getArgumentTypeAtIndex:index]);
    return type &&
           (type[0] == 'B' || type[0] == 'c' || type[0] == 'C');
}

static BOOL BHTSignatureReturnsVoid(
    NSMethodSignature* signature) {
    if (!signature) return NO;
    const char* returnType = BHTUnqualifiedObjCType(
        signature.methodReturnType);
    return returnType && returnType[0] == 'v';
}

static BOOL BHTSignatureArgumentMatchesType(
    NSMethodSignature* signature,
    NSUInteger index,
    const char* expectedType) {
    if (!signature || !expectedType ||
        index >= signature.numberOfArguments) {
        return NO;
    }
    const char* type = BHTUnqualifiedObjCType(
        [signature getArgumentTypeAtIndex:index]);
    return type && strcmp(type, expectedType) == 0;
}

static NSMethodSignature* BHTInstanceMethodSignature(
    Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    const char* typeEncoding =
        method ? method_getTypeEncoding(method) : NULL;
    return typeEncoding
               ? [NSMethodSignature
                     signatureWithObjCTypes:typeEncoding]
               : nil;
}

static BOOL BHTPasswordCommandSignatureIsSupported(void) {
    Class commandClass =
        NSClassFromString(@"TFSTwitterAPIXAuthPasswordCommand");
    SEL initializer = NSSelectorFromString(
        @"initWithContext:accountID:authContext:identifier:"
         @"password:simCountryCode:httpRequestConfiguration:"
         @"supportOneFactorAuthorization:knownDeviceToken:"
         @"uiMetrics:authTokenStorage:source:responseModelBuilder:"
         @"completionBlock:");
    NSMethodSignature* signature =
        BHTInstanceMethodSignature(commandClass, initializer);
    if (!signature || signature.numberOfArguments != 16) return NO;

    const char* returnType =
        BHTUnqualifiedObjCType(signature.methodReturnType);
    if (!returnType || returnType[0] != '@') return NO;

    for (NSUInteger index = 2; index <= 8; index++) {
        if (!BHTSignatureArgumentIsObject(signature, index)) {
            return NO;
        }
    }
    if (!BHTSignatureArgumentIsBoolean(signature, 9)) {
        return NO;
    }
    for (NSUInteger index = 10; index <= 12; index++) {
        if (!BHTSignatureArgumentIsObject(signature, index)) {
            return NO;
        }
    }
    if (!BHTSignatureArgumentIsNSUInteger(signature, 13)) {
        return NO;
    }
    for (NSUInteger index = 14; index <= 15; index++) {
        if (!BHTSignatureArgumentIsObject(signature, index)) {
            return NO;
        }
    }
    return YES;
}

static BOOL BHTNativeAccountSignaturesAreSupported(void) {
    Class accountClass = NSClassFromString(@"TFNTwitterAccount");
    NSMethodSignature* initializer =
        BHTInstanceMethodSignature(
            accountClass,
            NSSelectorFromString(@"initWithUsername:userID:"));
    const char* initializerReturn = BHTUnqualifiedObjCType(
        initializer.methodReturnType);
    if (!initializer || initializer.numberOfArguments != 4 ||
        !initializerReturn || initializerReturn[0] != '@' ||
        !BHTSignatureArgumentIsObject(initializer, 2) ||
        !BHTSignatureArgumentIsInteger(initializer, 3)) {
        return NO;
    }

    NSMethodSignature* update =
        BHTInstanceMethodSignature(
            accountClass,
            NSSelectorFromString(
                @"updateUserInfoAndCredentialsWithToken:"
                 @"secret:username:"));
    const char* updateReturn =
        BHTUnqualifiedObjCType(update.methodReturnType);
    return update && update.numberOfArguments == 5 &&
           updateReturn && updateReturn[0] == 'v' &&
           BHTSignatureArgumentIsObject(update, 2) &&
           BHTSignatureArgumentIsObject(update, 3) &&
           BHTSignatureArgumentIsObject(update, 4);
}

static BOOL BHTLoginChallengeFactorySignatureIsSupported(
    Class factoryClass, SEL selector) {
    Method method = class_getClassMethod(factoryClass, selector);
    const char* typeEncoding =
        method ? method_getTypeEncoding(method) : NULL;
    NSMethodSignature* signature =
        typeEncoding
            ? [NSMethodSignature signatureWithObjCTypes:typeEncoding]
            : nil;
    const char* returnType =
        BHTUnqualifiedObjCType(signature.methodReturnType);
    return signature && signature.numberOfArguments == 9 &&
           returnType && returnType[0] == '@' &&
           BHTSignatureArgumentIsInteger(signature, 2) &&
           BHTSignatureArgumentIsInteger(signature, 3) &&
           BHTSignatureArgumentIsObject(signature, 4) &&
           BHTSignatureArgumentIsObject(signature, 5) &&
           BHTSignatureArgumentIsInteger(signature, 6) &&
           BHTSignatureArgumentIsObject(signature, 7) &&
           BHTSignatureArgumentIsInteger(signature, 8);
}

static BOOL BHTHostAccountSwitchSignatureIsSupported(void) {
    Class hostClass =
        NSClassFromString(@"T1HostViewController");
    SEL selector =
        NSSelectorFromString(@"viewAccount:animated:");
    NSMethodSignature* signature =
        BHTInstanceMethodSignature(hostClass, selector);
    const char* returnType =
        BHTUnqualifiedObjCType(signature.methodReturnType);
    return hostClass &&
           [hostClass respondsToSelector:
                          NSSelectorFromString(
                              @"sharedHostViewController")] &&
           signature && signature.numberOfArguments == 4 &&
           returnType && returnType[0] == 'v' &&
           BHTSignatureArgumentIsObject(signature, 2) &&
           BHTSignatureArgumentIsBoolean(signature, 3);
}

static BOOL BHTNativeAddAccountCompletionGetterIsSupported(void) {
    Class accountsClass =
        NSClassFromString(@"T1AccountsViewController");
    NSMethodSignature* signature =
        BHTInstanceMethodSignature(
            accountsClass,
            NSSelectorFromString(@"didAddAccountBlock"));
    const char* returnType =
        BHTUnqualifiedObjCType(signature.methodReturnType);
    return signature && signature.numberOfArguments == 2 &&
           returnType && returnType[0] == '@';
}

// This is X 12.9's own JetX/Jetfuel login entry. Keep the guard exact because
// the selector is private and must never be called against an unexpected ABI.
static BOOL BHTNativeInitialSignInSignatureIsSupported(void) {
    Class hostClass = NSClassFromString(@"T1HostViewController");
    SEL sharedSelector =
        NSSelectorFromString(@"sharedHostViewController");
    SEL loginSelector =
        NSSelectorFromString(@"showLoginFlowWithSource:completion:");
    NSMethodSignature* signature =
        BHTInstanceMethodSignature(hostClass, loginSelector);
    return hostClass &&
           [hostClass respondsToSelector:sharedSelector] &&
           signature && signature.numberOfArguments == 4 &&
           BHTSignatureReturnsVoid(signature) &&
           BHTSignatureArgumentMatchesType(
               signature, 2, @encode(NSInteger)) &&
           BHTSignatureArgumentMatchesType(
               signature, 3, "@?");
}

// X's existing-account action owns all registration and switching callbacks.
// BOOL NO selects sign-in while YES selects sign-up in X 12.9.
static BOOL BHTNativeAddAccountSignInSignatureIsSupported(void) {
    Class accountsClass =
        NSClassFromString(@"T1AccountsViewController");
    SEL selector = NSSelectorFromString(@"_addAccount:sender:");
    NSMethodSignature* signature =
        BHTInstanceMethodSignature(accountsClass, selector);
    return accountsClass && signature &&
           signature.numberOfArguments == 4 &&
           BHTSignatureReturnsVoid(signature) &&
           BHTSignatureArgumentMatchesType(
               signature, 2, @encode(BOOL)) &&
           BHTSignatureArgumentMatchesType(
               signature, 3, "@");
}

static NSArray<NSString*>*
BHTMissingNativeCompatibilityRequirements(void) {
    NSMutableArray<NSString*>* missing =
        [NSMutableArray array];
    if (!BHTCompatibilityVersionIsSupported()) {
        [missing addObject:@"appVersion"];
        return [missing copy];
    }
    Class hostClass = NSClassFromString(@"T1HostViewController");
    if (!hostClass) {
        [missing addObject:@"hostControllerClass"];
    } else {
        if (![hostClass respondsToSelector:
                           NSSelectorFromString(
                               @"sharedHostViewController")]) {
            [missing addObject:@"sharedHostControllerSelector"];
        }
        if (!BHTNativeInitialSignInSignatureIsSupported()) {
            [missing addObject:@"nativeLoginFlowABI"];
        }
    }
    return [missing copy];
}

static NSArray<NSString*>*
BHTMissingCompatibilityRequirements(void) {
    NSMutableArray<NSString*>* missing =
        [NSMutableArray array];
    if (!BHTCompatibilityVersionIsSupported()) {
        [missing addObject:@"appVersion"];
        return [missing copy];
    }

    BHTLoadCompatibilityFrameworkIfNeeded();
    if (!BHTGuestAccountIdentifier()) {
        [missing addObject:@"guestIdentifier"];
    }

    BOOL commandClass =
        NSClassFromString(
            @"TFSTwitterAPIXAuthPasswordCommand") != Nil;
    BOOL serviceRunnerClass =
        NSClassFromString(@"TFSTwitterServiceRunner") != Nil;
    BOOL requestConfigurationClass =
        NSClassFromString(@"TNUServiceHTTPConfiguration") != Nil;
    BOOL authStorageClass =
        NSClassFromString(@"T1OnboardingAuthTokenStorage") != Nil;
    BOOL resultBuilderClass =
        NSClassFromString(
            @"TFSTwitterXAuthPasswordResponseBuilder") != Nil;
    BOOL accountClass =
        NSClassFromString(@"TFNTwitterAccount") != Nil;
    BOOL accountManagerClass =
        NSClassFromString(@"TFNTwitter") != Nil;
    BOOL hostControllerClass =
        NSClassFromString(@"T1HostViewController") != Nil;
    BOOL challengeFactoryClass =
        NSClassFromString(@"T1LoginChallengeFactory") != Nil;

    if (!commandClass) {
        [missing addObject:@"commandClass"];
    }
    if (!serviceRunnerClass) {
        [missing addObject:@"serviceRunnerClass"];
    }
    if (!requestConfigurationClass) {
        [missing addObject:@"requestConfigurationClass"];
    }
    if (!authStorageClass) {
        [missing addObject:@"authStorageClass"];
    }
    if (!resultBuilderClass) {
        [missing addObject:@"resultBuilderClass"];
    }
    if (!accountClass) {
        [missing addObject:@"accountClass"];
    }
    if (!accountManagerClass) {
        [missing addObject:@"accountManagerClass"];
    }
    if (!hostControllerClass) {
        [missing addObject:@"hostControllerClass"];
    }
    if (!challengeFactoryClass) {
        [missing addObject:@"challengeFactoryClass"];
    }

    if (serviceRunnerClass &&
        !BHTClassResponds(
            @"TFSTwitterServiceRunner", @"APICommandContext")) {
        [missing addObject:@"serviceContextMethod"];
    }
    if (serviceRunnerClass &&
        !BHTClassResponds(
            @"TFSTwitterServiceRunner", @"APICommandLoader")) {
        [missing addObject:@"serviceLoaderMethod"];
    }
    if (requestConfigurationClass &&
        !BHTClassResponds(
            @"TNUServiceHTTPConfiguration",
            @"configurationForForegroundRetriableRequest")) {
        [missing addObject:@"requestConfigurationMethod"];
    }
    if (accountClass &&
        !BHTClassResponds(
            @"TFNTwitterAccount", @"knownDeviceToken")) {
        [missing addObject:@"knownDeviceMethod"];
    }
    if (accountClass &&
        !BHTNativeAccountSignaturesAreSupported()) {
        [missing addObject:@"accountABI"];
    }
    if (accountManagerClass &&
        !BHTClassResponds(@"TFNTwitter", @"sharedTwitter")) {
        [missing addObject:@"sharedAccountManagerMethod"];
    }
    if (accountManagerClass &&
        !BHTClassResponds(@"TFNTwitter", @"saveSharedTwitter")) {
        [missing addObject:@"saveAccountManagerMethod"];
    }
    if (hostControllerClass &&
        !BHTHostAccountSwitchSignatureIsSupported()) {
        [missing addObject:@"hostSwitchABI"];
    }
    if (commandClass &&
        !BHTPasswordCommandSignatureIsSupported()) {
        [missing addObject:@"commandABI"];
    }

    return [missing copy];
}

static BOOL BHTCompatibilityRuntimeIsAvailable(void) {
    return BHTMissingCompatibilityRequirements().count == 0;
}

BOOL BHTCompatibilitySignInIsAvailable(void) {
    return BHTCompatibilityRuntimeIsAvailable();
}

static id BHTSendObject(id target, SEL selector) {
    if (!target || !selector ||
        ![target respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(target, selector);
}

static uint64_t BHTSendUnsignedValue(id target, SEL selector) {
    if (!target || !selector ||
        ![target respondsToSelector:selector]) {
        return 0;
    }

    NSMethodSignature* signature =
        [target methodSignatureForSelector:selector];
    const char* returnType = signature.methodReturnType;
    while (returnType &&
           strchr("rnNoORV", returnType[0]) != NULL) {
        returnType++;
    }
    if (returnType && returnType[0] == '@') {
        id value = BHTSendObject(target, selector);
        return [value respondsToSelector:@selector(unsignedLongLongValue)]
                   ? [value unsignedLongLongValue]
                   : 0;
    }
    return ((uint64_t (*)(id, SEL))objc_msgSend)(
        target, selector);
}

static NSInteger BHTSendIntegerValue(
    id target, SEL selector) {
    return (NSInteger)BHTSendUnsignedValue(target, selector);
}

static UIViewController* BHTTopViewController(
    UIViewController* controller) {
    UIViewController* current = controller;
    while (current) {
        if (current.presentedViewController &&
            !current.presentedViewController.isBeingDismissed) {
            current = current.presentedViewController;
            continue;
        }
        if ([current isKindOfClass:UINavigationController.class]) {
            UIViewController* visible =
                [(UINavigationController*)current visibleViewController];
            if (visible && visible != current) {
                current = visible;
                continue;
            }
        }
        if ([current isKindOfClass:UITabBarController.class]) {
            UIViewController* selected =
                [(UITabBarController*)current selectedViewController];
            if (selected && selected != current) {
                current = selected;
                continue;
            }
        }
        break;
    }
    return current;
}

static UIViewController* BHTActiveViewController(void) {
    UIWindow* activeWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState !=
                UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
            for (UIWindow* window in ((UIWindowScene*)scene).windows) {
                if (window.isKeyWindow) {
                    activeWindow = window;
                    break;
                }
            }
            if (activeWindow) break;
        }
    }
    if (!activeWindow) {
        activeWindow = UIApplication.sharedApplication.keyWindow;
    }
    return BHTTopViewController(activeWindow.rootViewController);
}

static BOOL BHTCompatibilityMetricsURLIsAllowed(NSURL* URL) {
    if (!URL ||
        ![URL.scheme.lowercaseString isEqualToString:@"https"]) {
        return NO;
    }
    NSString* host = URL.host.lowercaseString;
    return [host isEqualToString:@"x.com"] ||
           [host hasSuffix:@".x.com"] ||
           [host isEqualToString:@"twitter.com"] ||
           [host hasSuffix:@".twitter.com"];
}

@interface BHTCompatibilityMetricsCollector
    : NSObject <WKScriptMessageHandler, WKNavigationDelegate>
@property(nonatomic, strong) WKWebView* webView;
@property(nonatomic, weak) UIView* hostView;
@property(nonatomic, copy)
    void (^completion)(NSString* _Nullable metrics);
@property(nonatomic) BOOL finished;
- (void)startWithCompletion:
    (void (^)(NSString* _Nullable metrics))completion;
- (BOOL)consumeURL:(NSURL*)URL;
- (void)finishWithMetrics:(NSString*)metrics;
- (void)cancel;
@end

@implementation BHTCompatibilityMetricsCollector

- (BOOL)consumeURL:(NSURL*)URL {
    if (self.finished ||
        !BHTCompatibilityMetricsURLIsAllowed(URL)) {
        return NO;
    }
    NSURLComponents* components = [NSURLComponents
        componentsWithURL:URL resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem* item in components.queryItems ?: @[]) {
        if (![item.name isEqualToString:@"result"]) continue;
        NSString* metrics = item.value;
        if (metrics.length == 0 || metrics.length > 65536) {
            continue;
        }
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventMetricsResolved,
            @"metrics_resolved", nil);
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventMetricsResolvedFromNavigation,
            nil, nil);
        [self finishWithMetrics:metrics];
        return YES;
    }
    return NO;
}

- (void)startWithCompletion:
    (void (^)(NSString* _Nullable metrics))completion {
    self.completion = completion;

    WKWebViewConfiguration* configuration =
        [WKWebViewConfiguration new];
    configuration.websiteDataStore =
        [WKWebsiteDataStore nonPersistentDataStore];

    WKUserContentController* contentController =
        [WKUserContentController new];
    NSString* source =
        @"(function(){function rep(u){try{var p=new URL(String(u),"
         @"window.location.href);var r=p.searchParams.get('result');"
         @"if(typeof r==='string'&&r.length>0&&r.length<=65536){"
         @"window.webkit.messageHandlers.bht.postMessage(r);}}catch(e){}}"
         @"var of=window.fetch;if(of){window.fetch=function(){try{"
         @"rep(arguments[0]&&arguments[0].url?arguments[0].url:"
         @"arguments[0]);}catch(e){}return of.apply(this,arguments);"
         @"};}var oo=XMLHttpRequest.prototype.open;"
         @"XMLHttpRequest.prototype.open=function(m,u){try{rep(u);}"
         @"catch(e){}return oo.apply(this,arguments);};"
         @"if(navigator.sendBeacon){var sb=navigator.sendBeacon.bind("
         @"navigator);navigator.sendBeacon=function(u,d){try{rep(u);}"
         @"catch(e){}return sb(u,d);};}})();";
    WKUserScript* script = [[WKUserScript alloc]
        initWithSource:source
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
      forMainFrameOnly:NO];
    [contentController addUserScript:script];
    [contentController addScriptMessageHandler:self
                                          name:BHTMetricsHandlerName];
    configuration.userContentController = contentController;

    self.webView =
        [[WKWebView alloc] initWithFrame:CGRectZero
                           configuration:configuration];
    self.webView.navigationDelegate = self;
    self.webView.alpha = 0.0;
    self.webView.userInteractionEnabled = NO;
    self.webView.accessibilityElementsHidden = YES;
    if (self.hostView) {
        self.webView.frame = self.hostView.bounds;
        self.webView.autoresizingMask =
            UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;
        [self.hostView addSubview:self.webView];
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventMetricsCollectorAttached,
            nil, nil);
    }
    NSURL* endpoint =
        [NSURL URLWithString:@"https://x.com/i/js_inst?native=true"];
    if (!endpoint) {
        [self finishWithMetrics:nil];
        return;
    }
    NSURLRequest* request = [NSURLRequest
        requestWithURL:endpoint
           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
       timeoutInterval:12.0];
    [self.webView loadRequest:request];

    __weak typeof(self) weakSelf = self;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(12.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            if (!weakSelf || weakSelf.finished) return;
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventMetricsTimedOut,
                @"metrics_timeout", nil);
            [weakSelf finishWithMetrics:nil];
        });
}

- (void)userContentController:
            (WKUserContentController*)userContentController
      didReceiveScriptMessage:(WKScriptMessage*)message {
    if (self.finished ||
        ![message.name isEqualToString:BHTMetricsHandlerName] ||
        ![message.body isKindOfClass:NSString.class] ||
        !BHTCompatibilityMetricsURLIsAllowed(
            message.frameInfo.request.URL)) {
        return;
    }

    NSString* metrics = (NSString*)message.body;
    if (metrics.length > 0 && metrics.length <= 65536) {
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventMetricsResolved,
            @"metrics_resolved", nil);
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventMetricsResolvedFromScript,
            nil, nil);
        [self finishWithMetrics:metrics];
    }
}

- (void)webView:(__unused WKWebView*)webView
    decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction
                    decisionHandler:
                        (void (^)(WKNavigationActionPolicy))decisionHandler {
    BOOL consumed = [self consumeURL:navigationAction.request.URL];
    decisionHandler(consumed
                        ? WKNavigationActionPolicyCancel
                        : WKNavigationActionPolicyAllow);
}

- (void)webView:(__unused WKWebView*)webView
    decidePolicyForNavigationResponse:(WKNavigationResponse*)navigationResponse
                    decisionHandler:
                        (void (^)(WKNavigationResponsePolicy))decisionHandler {
    BOOL consumed = [self consumeURL:navigationResponse.response.URL];
    decisionHandler(consumed
                        ? WKNavigationResponsePolicyCancel
                        : WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView*)webView
    didReceiveServerRedirectForProvisionalNavigation:
        (__unused WKNavigation*)navigation {
    [self consumeURL:webView.URL];
}

- (void)webView:(WKWebView*)webView
    didFinishNavigation:(__unused WKNavigation*)navigation {
    [self consumeURL:webView.URL];
}

- (void)cancel {
    if (self.finished) return;
    self.finished = YES;
    [self.webView stopLoading];
    self.webView.navigationDelegate = nil;
    [self.webView removeFromSuperview];
    [self.webView.configuration.userContentController
        removeScriptMessageHandlerForName:BHTMetricsHandlerName];
    self.webView = nil;
    self.completion = nil;
}

- (void)finishWithMetrics:(NSString*)metrics {
    if (self.finished) return;
    self.finished = YES;
    [self.webView stopLoading];
    self.webView.navigationDelegate = nil;
    [self.webView removeFromSuperview];
    [self.webView.configuration.userContentController
        removeScriptMessageHandlerForName:BHTMetricsHandlerName];
    self.webView = nil;

    void (^completion)(NSString*) = self.completion;
    self.completion = nil;
    if (completion) completion(metrics);
}

- (void)dealloc {
    self.webView.navigationDelegate = nil;
    [self.webView removeFromSuperview];
    [self.webView.configuration.userContentController
        removeScriptMessageHandlerForName:BHTMetricsHandlerName];
}

@end

static id BHTCreatePasswordCommand(
    NSString* identifier,
    NSString* password,
    NSString* metrics,
    void (^completion)(BOOL success, id response, id error)) {
    Class serviceRunner =
        NSClassFromString(@"TFSTwitterServiceRunner");
    Class configurationClass =
        NSClassFromString(@"TNUServiceHTTPConfiguration");
    Class accountClass =
        NSClassFromString(@"TFNTwitterAccount");
    Class storageClass =
        NSClassFromString(@"T1OnboardingAuthTokenStorage");
    Class builderClass =
        NSClassFromString(@"TFSTwitterXAuthPasswordResponseBuilder");
    Class commandClass =
        NSClassFromString(@"TFSTwitterAPIXAuthPasswordCommand");

    id context = BHTSendObject(
        serviceRunner, NSSelectorFromString(@"APICommandContext"));
    id accountID = BHTGuestAccountIdentifier();
    id authContext = nil;
    id simCountryCode = nil;
    id requestConfiguration = BHTSendObject(
        configurationClass,
        NSSelectorFromString(
            @"configurationForForegroundRetriableRequest"));
    BOOL supportOneFactorAuthorization = NO;
    id knownDeviceToken = BHTSendObject(
        accountClass, NSSelectorFromString(@"knownDeviceToken"));
    id authTokenStorage = [[storageClass alloc] init];
    // X 12.9 encodes source: as NSUInteger; native-compatible callers use 0.
    NSUInteger source = 0;
    id responseBuilder = [[builderClass alloc] init];
    id completionBlock = [completion copy];

    if (!context || !accountID || !requestConfiguration ||
        !authTokenStorage || !responseBuilder ||
        identifier.length == 0 || password.length == 0) {
        return nil;
    }

    if (!BHTPasswordCommandSignatureIsSupported()) {
        return nil;
    }

    id<BHTXAuthPasswordCommandInitializing> allocatedCommand =
        (id)[commandClass alloc];
    return [allocatedCommand
        initWithContext:context
              accountID:accountID
            authContext:authContext
             identifier:identifier
               password:password
         simCountryCode:simCountryCode
httpRequestConfiguration:requestConfiguration
supportOneFactorAuthorization:supportOneFactorAuthorization
       knownDeviceToken:knownDeviceToken
              uiMetrics:metrics
       authTokenStorage:authTokenStorage
                 source:source
   responseModelBuilder:responseBuilder
        completionBlock:completionBlock];
}

static BOOL BHTStartPasswordCommand(id command) {
    if (!command) return NO;
    Class serviceRunner =
        NSClassFromString(@"TFSTwitterServiceRunner");
    id loader = BHTSendObject(
        serviceRunner, NSSelectorFromString(@"APICommandLoader"));
    SEL start = NSSelectorFromString(@"startCommand:");
    if (!loader || ![loader respondsToSelector:start]) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(
        loader, start, command);
    return YES;
}

static id BHTBuildNativeAccount(
    NSString* token,
    NSString* secret,
    NSString* screenName,
    uint64_t userID) {
    if (token.length == 0 || secret.length == 0 ||
        screenName.length == 0 || userID == 0) {
        return nil;
    }

    Class accountClass =
        NSClassFromString(@"TFNTwitterAccount");
    SEL initializer =
        NSSelectorFromString(@"initWithUsername:userID:");
    SEL update = NSSelectorFromString(
        @"updateUserInfoAndCredentialsWithToken:secret:username:");
    if (!accountClass ||
        ![accountClass instancesRespondToSelector:initializer] ||
        ![accountClass instancesRespondToSelector:update]) {
        return nil;
    }

    id<BHTNativeAccountInitializing> account =
        [(id<BHTNativeAccountInitializing>)[accountClass alloc]
            initWithUsername:screenName
                     userID:userID];
    if (!account) return nil;
    [account updateUserInfoAndCredentialsWithToken:token
                                           secret:secret
                                         username:screenName];
    return account;
}

static BOOL BHTRegisterNativeAccount(id account) {
    if (!account) return NO;
    Class twitterClass = NSClassFromString(@"TFNTwitter");
    id twitter = BHTSendObject(
        twitterClass, NSSelectorFromString(@"sharedTwitter"));
    id accountService = BHTSendObject(
        twitter, NSSelectorFromString(@"accountService"));
    SEL addAccount = NSSelectorFromString(@"addAccount:");
    SEL save = NSSelectorFromString(@"saveSharedTwitter");
    if (!twitter || !accountService ||
        ![accountService respondsToSelector:addAccount] ||
        ![twitterClass respondsToSelector:save]) {
        return NO;
    }

    ((void (*)(id, SEL, id))objc_msgSend)(
        accountService, addAccount, account);
    ((void (*)(id, SEL))objc_msgSend)(twitterClass, save);

    SEL refresh = NSSelectorFromString(@"refreshForced:source:");
    if ([account respondsToSelector:refresh]) {
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(
            account, refresh, NO, nil);
    }

    Class notificationClass =
        NSClassFromString(@"TFSAccountNotification");
    NSString* notificationName = BHTSendObject(
        notificationClass,
        NSSelectorFromString(@"TFSAccountsDidChange"));
    if ([notificationName isKindOfClass:NSString.class] &&
        notificationName.length > 0) {
        [NSNotificationCenter.defaultCenter
            postNotificationName:notificationName
                          object:twitter
                        userInfo:nil];
    }
    BHTCompatibilityRecord(
        BHTCompatibilityLoginEventAccountRegistered,
        @"account_registered", nil);
    return YES;
}

static BOOL BHTSwitchToNativeAccount(id account) {
    atomic_fetch_add_explicit(
        &BHTCompatibilityAccountHandoffAttempted, 1,
        memory_order_relaxed);
    if (!account ||
        !BHTHostAccountSwitchSignatureIsSupported()) {
        atomic_fetch_add_explicit(
            &BHTCompatibilityAccountHandoffFailed, 1,
            memory_order_relaxed);
        return NO;
    }
    Class hostClass =
        NSClassFromString(@"T1HostViewController");
    UIViewController* host = (UIViewController*)BHTSendObject(
        hostClass,
        NSSelectorFromString(@"sharedHostViewController"));
    SEL viewAccount =
        NSSelectorFromString(@"viewAccount:animated:");
    if (host && [host respondsToSelector:viewAccount]) {
        @try {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(
                host, viewAccount, account, YES);
            atomic_fetch_add_explicit(
                &BHTCompatibilityAccountHandoffDispatched, 1,
                memory_order_relaxed);
            return YES;
        } @catch (__unused NSException* exception) {
            atomic_fetch_add_explicit(
                &BHTCompatibilityAccountHandoffFailed, 1,
                memory_order_relaxed);
            return NO;
        }
    }
    atomic_fetch_add_explicit(
        &BHTCompatibilityAccountHandoffFailed, 1,
        memory_order_relaxed);
    return NO;
}

typedef void (^BHTCompatibilityResult)(
    BOOL success, NSString* _Nullable failureCategory);
typedef void (^BHTNativeDidAddAccountBlock)(
    id controller, id account);

typedef struct {
    void* isa;
    int32_t flags;
    int32_t reserved;
    void (*invoke)(void*, ...);
    void* descriptor;
} BHTBlockLiteral;

enum {
    BHTBlockHasCopyDispose = (1 << 25),
    BHTBlockHasSignature = (1 << 30),
};

static BOOL BHTNativeDidAddAccountBlockIsSupported(id value) {
    if (!value) return NO;

    Class blockClass = object_getClass(value);
    const char* className =
        blockClass ? class_getName(blockClass) : NULL;
    if (!className || !strstr(className, "Block")) {
        return NO;
    }

    BHTBlockLiteral* block =
        (__bridge BHTBlockLiteral*)value;
    if (!block->descriptor ||
        !(block->flags & BHTBlockHasSignature)) {
        return NO;
    }

    uintptr_t descriptor =
        (uintptr_t)block->descriptor +
        (sizeof(uintptr_t) * 2);
    if (block->flags & BHTBlockHasCopyDispose) {
        descriptor += sizeof(void*) * 2;
    }
    const char* typeEncoding =
        *(const char* const*)descriptor;
    if (!typeEncoding) return NO;

    @try {
        NSMethodSignature* signature =
            [NSMethodSignature
                signatureWithObjCTypes:typeEncoding];
        const char* returnType =
            BHTUnqualifiedObjCType(
                signature.methodReturnType);
        return signature &&
               signature.numberOfArguments == 3 &&
               returnType && returnType[0] == 'v' &&
               BHTSignatureArgumentIsObject(signature, 1) &&
               BHTSignatureArgumentIsObject(signature, 2);
    } @catch (__unused NSException* exception) {
        return NO;
    }
}

static void BHTCompleteSignedOutFlowAndSwitchAccount(
    id account,
    UIViewController* compatibilityController,
    BHTCompatibilityResult result) {
    Class hostClass =
        NSClassFromString(@"T1HostViewController");
    UIViewController* host = (UIViewController*)BHTSendObject(
        hostClass,
        NSSelectorFromString(@"sharedHostViewController"));
    if (!host ||
        ![host respondsToSelector:
                   NSSelectorFromString(@"viewAccount:animated:")]) {
        if (result) result(NO, @"account_switch_failed");
        return;
    }

    void (^switchAccount)(void) = ^{
        BOOL switched = BHTSwitchToNativeAccount(account);
        if (result) {
            result(
                switched,
                switched ? nil : @"account_switch_failed");
        }
    };

    id signedOutFlow = BHTSendObject(
        host, NSSelectorFromString(@"signedOutOnboardingFlow"));
    SEL completeSelector =
        NSSelectorFromString(@"completeFlowAnimated:completion:");
    if (signedOutFlow &&
        [signedOutFlow respondsToSelector:completeSelector]) {
        // Let X tear down its full signed-out flow before switching. This
        // avoids depending on a private presenter hierarchy.
        @try {
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(
                signedOutFlow, completeSelector, YES,
                [switchAccount copy]);
        } @catch (__unused NSException* exception) {
            if (result) result(NO, @"account_switch_failed");
        }
        return;
    }

    UIViewController* modal =
        compatibilityController.navigationController ?:
        compatibilityController;
    if (modal.presentingViewController) {
        [modal dismissViewControllerAnimated:YES
                                  completion:switchAccount];
    } else {
        switchAccount();
    }
}

static void BHTCompleteAddAccountFlow(
    id account,
    UIViewController* compatibilityController,
    UIViewController* accountsController,
    UIViewController* challengePresenter,
    BHTCompatibilityResult result) {
    if (!account || !accountsController) {
        if (result) result(NO, @"account_switch_failed");
        return;
    }

    SEL callbackSelector =
        NSSelectorFromString(@"didAddAccountBlock");
    id callbackValue =
        BHTNativeAddAccountCompletionGetterIsSupported()
            ? BHTSendObject(
                  accountsController, callbackSelector)
            : nil;
    BHTNativeDidAddAccountBlock didAddAccount =
        BHTNativeDidAddAccountBlockIsSupported(callbackValue)
            ? [callbackValue copy]
            : nil;

    void (^finishAccountFlow)(void) = ^{
        if (didAddAccount) {
            atomic_fetch_add_explicit(
                &BHTCompatibilityAccountHandoffAttempted, 1,
                memory_order_relaxed);
            @try {
                // X 12.9's native completion uses
                // (accountsController, account). Its encoded block ABI is
                // validated above before this private callback is invoked.
                didAddAccount(accountsController, account);
                atomic_fetch_add_explicit(
                    &BHTCompatibilityAccountHandoffDispatched, 1,
                    memory_order_relaxed);
                if (result) result(YES, nil);
            } @catch (__unused NSException* exception) {
                atomic_fetch_add_explicit(
                    &BHTCompatibilityAccountHandoffFailed, 1,
                    memory_order_relaxed);
                BOOL switched =
                    BHTSwitchToNativeAccount(account);
                if (result) {
                    result(
                        switched,
                        switched
                            ? nil
                            : @"account_switch_failed");
                }
            }
            return;
        }

        BOOL switched = BHTSwitchToNativeAccount(account);
        if (result) {
            result(
                switched,
                switched ? nil : @"account_switch_failed");
        }
    };

    void (^dismissCompatibility)(void) = ^{
        UIViewController* modal =
            compatibilityController.navigationController ?:
            compatibilityController;
        if (modal.presentingViewController &&
            !modal.isBeingDismissed) {
            [modal dismissViewControllerAnimated:YES
                                      completion:finishAccountFlow];
        } else {
            finishAccountFlow();
        }
    };

    if (challengePresenter.presentedViewController &&
        !challengePresenter.presentedViewController.isBeingDismissed) {
        [challengePresenter
            dismissViewControllerAnimated:YES
                               completion:dismissCompatibility];
    } else {
        dismissCompatibility();
    }
}

static BOOL BHTPresentNativeLoginChallenge(
    id response,
    NSString* fallbackUsername,
    UIViewController* compatibilityController,
    UIViewController* addAccountController,
    BHTCompatibilityResult result) {
    SEL requestIDSelector =
        NSSelectorFromString(@"loginVerificationRequestId");
    SEL challengeURLSelector =
        NSSelectorFromString(@"challengeURLString");
    id requestID = BHTSendObject(response, requestIDSelector);
    id challengeURL =
        BHTSendObject(response, challengeURLSelector);
    if (!requestID || !challengeURL) return NO;

    Class factoryClass =
        NSClassFromString(@"T1LoginChallengeFactory");
    Class hostClass =
        NSClassFromString(@"T1HostViewController");
    SEL factorySelector = NSSelectorFromString(
        @"loginChallengeWithMode:loginType:requestID:user:"
         @"userID:URLString:loginCause:");
    UIViewController* host = (UIViewController*)BHTSendObject(
        hostClass,
        NSSelectorFromString(@"sharedHostViewController"));
    if (!factoryClass ||
        !BHTLoginChallengeFactorySignatureIsSupported(
            factoryClass, factorySelector) ||
        !host) {
        if (result) result(NO, @"challenge_runtime_missing");
        return YES;
    }

    UIViewController* challengePresenter =
        addAccountController
            ? BHTTopViewController(compatibilityController)
            : host;
    if (!challengePresenter) {
        if (result) {
            result(NO, @"challenge_presentation_failed");
        }
        return YES;
    }

    BOOL securityKeyEnabled = NO;
    Class switchesClass =
        NSClassFromString(@"TPSDeviceFeatureSwitches");
    SEL securityKeySelector =
        NSSelectorFromString(@"isSecurityKeyAuthEnabled");
    if ([switchesClass respondsToSelector:securityKeySelector]) {
        securityKeyEnabled =
            ((BOOL (*)(id, SEL))objc_msgSend)(
                switchesClass, securityKeySelector);
    }
    NSInteger mode = securityKeyEnabled ? 1 : 0;
    NSInteger loginType = BHTSendIntegerValue(
        response,
        NSSelectorFromString(@"loginVerificationRequestType"));
    NSInteger loginCause = BHTSendIntegerValue(
        response,
        NSSelectorFromString(@"loginVerificationRequestCause"));
    uint64_t userID = BHTSendUnsignedValue(
        response,
        NSSelectorFromString(@"loginVerificationUserId"));
    if (userID == 0) {
        userID = BHTSendUnsignedValue(
            response, NSSelectorFromString(@"userId"));
    }

    id challenge =
        ((id (*)(id, SEL, NSInteger, NSInteger, id, id,
                 uint64_t, id, NSInteger))objc_msgSend)(
            factoryClass, factorySelector, mode, loginType,
            requestID, fallbackUsername ?: @"", userID,
            challengeURL, loginCause);
    if (!challenge) {
        if (result) result(NO, @"challenge_creation_failed");
        return YES;
    }

    SEL didAddSelector =
        NSSelectorFromString(@"setDidAddAccountBlock:");
    if (![challenge respondsToSelector:didAddSelector]) {
        if (result) result(NO, @"challenge_completion_missing");
        return YES;
    }
    {
        void (^didAddAccount)(id, id) =
            ^(__unused id firstValue, id account) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    BOOL registered = NO;
                    @try {
                        registered =
                            BHTRegisterNativeAccount(account);
                    } @catch (__unused NSException* exception) {
                        registered = NO;
                    }
                    if (!registered) {
                        if (result) {
                            result(
                                NO,
                                @"account_registration_failed");
                        }
                        return;
                    }
                    BHTDetailedReplyDiagnosticsNoteCompatibilityAccount(
                        account);
                    BHTCompatibilityRecord(
                        BHTCompatibilityLoginEventAuthenticated,
                        @"authenticated", nil);

                    if (addAccountController) {
                        BHTCompleteAddAccountFlow(
                            account, compatibilityController,
                            addAccountController,
                            challengePresenter, result);
                        return;
                    }

                    void (^switchAccount)(void) = ^{
                        BOOL switched =
                            BHTSwitchToNativeAccount(account);
                        if (result) {
                            result(
                                switched,
                                switched
                                    ? nil
                                    : @"account_switch_failed");
                        }
                    };
                    if (host.presentedViewController &&
                        !host.presentedViewController.isBeingDismissed) {
                        [host
                            dismissViewControllerAnimated:YES
                                               completion:switchAccount];
                    } else {
                        switchAccount();
                    }
                });
            };
        ((void (*)(id, SEL, id))objc_msgSend)(
            challenge, didAddSelector, [didAddAccount copy]);
    }

    SEL setProvider =
        NSSelectorFromString(@"setLoginChallengeProvider:");
    if ([host respondsToSelector:setProvider]) {
        ((void (*)(id, SEL, id))objc_msgSend)(
            host, setProvider, challenge);
    }

    SEL presentSelector = NSSelectorFromString(
        @"presentLoginChallengeFromViewController:animated:completion:");
    if (![challenge respondsToSelector:presentSelector]) {
        if (result) result(NO, @"challenge_presentation_missing");
        return YES;
    }

    void (^presentChallenge)(void) = ^{
        @try {
            ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(
                challenge, presentSelector,
                challengePresenter, YES, nil);
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventChallengePresented,
                @"challenge_presented", nil);
        } @catch (__unused NSException* exception) {
            if (result) {
                result(NO, @"challenge_presentation_failed");
            }
        }
    };

    SEL flowSelector =
        NSSelectorFromString(@"signedOutOnboardingFlow");
    id signedOutFlow = BHTSendObject(host, flowSelector);
    SEL completeSelector =
        NSSelectorFromString(@"completeFlowAnimated:completion:");
    if (!addAccountController && signedOutFlow &&
        [signedOutFlow respondsToSelector:completeSelector]) {
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(
            signedOutFlow, completeSelector, NO,
            [presentChallenge copy]);
    } else {
        presentChallenge();
    }
    return YES;
}

@interface BHTCompatibilityLoginViewController
    : UIViewController <UITextFieldDelegate>
@property(nonatomic, strong) UITextField* usernameField;
@property(nonatomic, strong) UITextField* passwordField;
@property(nonatomic, strong) UIButton* signInButton;
@property(nonatomic, strong) UIActivityIndicatorView* activity;
@property(nonatomic, strong) UILabel* statusLabel;
@property(nonatomic, strong)
    BHTCompatibilityMetricsCollector* metricsCollector;
@property(nonatomic) BOOL cancelled;
@property(nonatomic) BOOL requestStarted;
@property(nonatomic) BOOL sharingReport;
@property(nonatomic) BOOL runtimeAvailable;
@property(nonatomic, weak) UIViewController* addAccountController;
@end

@implementation BHTCompatibilityLoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.runtimeAvailable =
        BHTCompatibilityRuntimeIsAvailable();
    self.title =
        BHTCompatibilityLocalized(@"COMPATIBILITY_SIGN_IN_TITLE");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                 target:self
                                 action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc]
            initWithTitle:BHTCompatibilityLocalized(
                              @"COMPATIBILITY_SIGN_IN_SHARE_REPORT")
                     style:UIBarButtonItemStylePlain
                    target:self
                    action:@selector(shareLoginReport:)];
    self.navigationItem.rightBarButtonItem.accessibilityIdentifier =
        @"NeoFreeBird.ShareLoginReport";

    UILabel* heading = [UILabel new];
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    heading.text =
        BHTCompatibilityLocalized(@"COMPATIBILITY_SIGN_IN_HEADING");
    heading.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    heading.adjustsFontForContentSizeCategory = YES;
    heading.numberOfLines = 0;

    UILabel* detail = [UILabel new];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.text =
        BHTCompatibilityLocalized(@"COMPATIBILITY_SIGN_IN_DETAIL");
    detail.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    detail.textColor = UIColor.secondaryLabelColor;
    detail.adjustsFontForContentSizeCategory = YES;
    detail.numberOfLines = 0;

    self.usernameField = [UITextField new];
    self.usernameField.translatesAutoresizingMaskIntoConstraints = NO;
    self.usernameField.placeholder =
        BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_USERNAME_PLACEHOLDER");
    self.usernameField.textContentType = UITextContentTypeUsername;
    self.usernameField.autocapitalizationType =
        UITextAutocapitalizationTypeNone;
    self.usernameField.autocorrectionType =
        UITextAutocorrectionTypeNo;
    self.usernameField.returnKeyType = UIReturnKeyNext;
    self.usernameField.delegate = self;
    self.usernameField.borderStyle = UITextBorderStyleRoundedRect;

    self.passwordField = [UITextField new];
    self.passwordField.translatesAutoresizingMaskIntoConstraints = NO;
    self.passwordField.placeholder =
        BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_PASSWORD_PLACEHOLDER");
    self.passwordField.textContentType = UITextContentTypePassword;
    self.passwordField.secureTextEntry = YES;
    self.passwordField.returnKeyType = UIReturnKeyGo;
    self.passwordField.delegate = self;
    self.passwordField.borderStyle = UITextBorderStyleRoundedRect;

    self.signInButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.signInButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.signInButton
        setTitle:BHTCompatibilityLocalized(
                     @"COMPATIBILITY_SIGN_IN_ACTION")
        forState:UIControlStateNormal];
    self.signInButton.titleLabel.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.signInButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    self.signInButton.backgroundColor = UIColor.systemBlueColor;
    [self.signInButton setTitleColor:UIColor.whiteColor
                           forState:UIControlStateNormal];
    self.signInButton.layer.cornerRadius = 12.0;
    [self.signInButton addTarget:self
                          action:@selector(signInTapped)
                forControlEvents:UIControlEventTouchUpInside];

    self.activity =
        [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:
                UIActivityIndicatorViewStyleMedium];
    self.activity.translatesAutoresizingMaskIntoConstraints = NO;
    self.activity.hidesWhenStopped = YES;

    self.statusLabel = [UILabel new];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.adjustsFontForContentSizeCategory = YES;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;

    UILabel* privacy = [UILabel new];
    privacy.translatesAutoresizingMaskIntoConstraints = NO;
    privacy.text =
        BHTCompatibilityLocalized(@"COMPATIBILITY_SIGN_IN_PRIVACY");
    privacy.font =
        [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    privacy.textColor = UIColor.tertiaryLabelColor;
    privacy.adjustsFontForContentSizeCategory = YES;
    privacy.numberOfLines = 0;
    privacy.textAlignment = NSTextAlignmentCenter;

    UIStackView* stack = [[UIStackView alloc]
        initWithArrangedSubviews:@[
            heading, detail, self.usernameField,
            self.passwordField, self.signInButton,
            self.activity, self.statusLabel, privacy
        ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14.0;
    [stack setCustomSpacing:24.0 afterView:detail];
    [stack setCustomSpacing:20.0
                 afterView:self.passwordField];
    [self.view addSubview:stack];

    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor
            constraintEqualToAnchor:safe.leadingAnchor
                           constant:24.0],
        [stack.trailingAnchor
            constraintEqualToAnchor:safe.trailingAnchor
                           constant:-24.0],
        [stack.topAnchor
            constraintGreaterThanOrEqualToAnchor:safe.topAnchor
                                        constant:24.0],
        [stack.centerYAnchor
            constraintEqualToAnchor:safe.centerYAnchor
                           constant:-20.0],
        [self.usernameField.heightAnchor constraintEqualToConstant:48.0],
        [self.passwordField.heightAnchor constraintEqualToConstant:48.0],
        [self.signInButton.heightAnchor constraintEqualToConstant:50.0],
    ]];

    NSString* initialStatus =
        self.runtimeAvailable
            ? @""
            : BHTCompatibilityLocalized(
                  @"COMPATIBILITY_SIGN_IN_RUNTIME_ERROR");
    [self setBusy:NO status:initialStatus];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.runtimeAvailable) {
        [self.usernameField becomeFirstResponder];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    BOOL dismissed = self.isBeingDismissed ||
        self.navigationController.isBeingDismissed;
    if (dismissed && !self.requestStarted) {
        self.cancelled = YES;
        [self.metricsCollector cancel];
        self.metricsCollector = nil;
        self.passwordField.text = @"";
    }
}

- (void)shareLoginReport:(UIBarButtonItem*)sender {
    if (self.sharingReport || self.requestStarted ||
        self.metricsCollector || self.presentedViewController) {
        return;
    }

    self.sharingReport = YES;
    sender.enabled = NO;
    [self.view endEditing:YES];

    __weak typeof(self) weakSelf = self;
    BHTWriteCompatibilityReportAsync(^(NSURL* reportURL) {
        BHTCompatibilityLoginViewController* strongSelf =
            weakSelf;
        if (!strongSelf) {
            if (reportURL.isFileURL) {
                [NSFileManager.defaultManager
                    removeItemAtURL:reportURL
                              error:nil];
            }
            return;
        }

        strongSelf.sharingReport = NO;
        sender.enabled =
            !strongSelf.requestStarted &&
            !strongSelf.metricsCollector;
        if (!reportURL.isFileURL) {
            if (strongSelf.viewIfLoaded.window) {
                strongSelf.statusLabel.textColor =
                    UIColor.systemRedColor;
                strongSelf.statusLabel.text =
                    BHTCompatibilityLocalized(
                        @"COMPATIBILITY_SIGN_IN_REPORT_ERROR");
            }
            return;
        }
        if (strongSelf.cancelled ||
            strongSelf.requestStarted ||
            strongSelf.metricsCollector ||
            strongSelf.presentedViewController ||
            !strongSelf.viewIfLoaded.window) {
            [NSFileManager.defaultManager
                removeItemAtURL:reportURL
                          error:nil];
            return;
        }

        UIActivityViewController* share =
            [[UIActivityViewController alloc]
                initWithActivityItems:@[reportURL]
                applicationActivities:nil];
        UIPopoverPresentationController* popover =
            share.popoverPresentationController;
        if (sender) {
            popover.barButtonItem = sender;
        } else {
            popover.sourceView = strongSelf.view;
            popover.sourceRect = CGRectMake(
                CGRectGetMidX(strongSelf.view.bounds),
                CGRectGetMidY(strongSelf.view.bounds),
                1.0, 1.0);
        }
        share.completionWithItemsHandler =
            ^(__unused UIActivityType activityType,
              __unused BOOL completed,
              __unused NSArray* returnedItems,
              __unused NSError* activityError) {
                [NSFileManager.defaultManager
                    removeItemAtURL:reportURL
                              error:nil];
            };
        [strongSelf presentViewController:share
                                animated:YES
                              completion:nil];
    });
}

- (void)cancelTapped {
    if (self.requestStarted) return;
    self.cancelled = YES;
    [self.metricsCollector cancel];
    self.metricsCollector = nil;
    self.passwordField.text = @"";
    [self.view endEditing:YES];
    UIViewController* modal = self.navigationController ?: self;
    [modal dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
    if (textField == self.usernameField) {
        [self.passwordField becomeFirstResponder];
    } else {
        [self signInTapped];
    }
    return YES;
}

- (void)setBusy:(BOOL)busy status:(NSString*)status {
    BOOL controlsEnabled =
        self.runtimeAvailable && !busy;
    self.usernameField.enabled = controlsEnabled;
    self.passwordField.enabled = controlsEnabled;
    self.signInButton.enabled = controlsEnabled;
    self.signInButton.alpha = controlsEnabled ? 1.0 : 0.55;
    self.navigationItem.leftBarButtonItem.enabled =
        !self.requestStarted;
    self.navigationItem.rightBarButtonItem.enabled =
        !busy && !self.sharingReport;
    self.navigationController.modalInPresentation = busy;
    if (busy) {
        [self.activity startAnimating];
    } else {
        [self.activity stopAnimating];
    }
    self.statusLabel.textColor =
        busy ? UIColor.secondaryLabelColor : UIColor.systemRedColor;
    self.statusLabel.text = status ?: @"";
}

- (NSString*)messageForFailureCategory:(NSString*)category {
    if ([category isEqualToString:@"unsupported_version"]) {
        return BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_VERSION_ERROR");
    }
    if ([category isEqualToString:@"missing_runtime"]) {
        return BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_RUNTIME_ERROR");
    }
    if ([category isEqualToString:@"authentication_rejected"]) {
        return BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_REJECTED_ERROR");
    }
    if ([category
            isEqualToString:@"authentication_rejected_with_payload"]) {
        return BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_REJECTED_ERROR");
    }
    if ([category isEqualToString:@"network_failure"]) {
        return BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_NETWORK_ERROR");
    }
    return BHTCompatibilityLocalized(
        @"COMPATIBILITY_SIGN_IN_GENERIC_ERROR");
}

- (void)finishWithSuccess:
            (BOOL)success
          failureCategory:(NSString*)failureCategory {
    if (success) {
        self.passwordField.text = @"";
        UIViewController* modal =
            self.navigationController ?: self;
        if (modal.presentingViewController) {
            [modal dismissViewControllerAnimated:YES
                                      completion:nil];
        }
        return;
    }

    NSString* category =
        failureCategory.length > 0
            ? failureCategory
            : @"unknown";
    BHTCompatibilityRecord(
        BHTCompatibilityLoginEventFailed,
        @"failed", category);
    self.requestStarted = NO;
    [self setBusy:NO
           status:[self messageForFailureCategory:category]];
}

- (void)handlePasswordResponse:
            (BOOL)success
                        response:(id)response
                           error:(id)error
                fallbackUsername:(NSString*)fallbackUsername {
    BHTCompatibilityRecordCommandCompletion(
        success, response, error);

    SEL requestIDSelector =
        NSSelectorFromString(@"loginVerificationRequestId");
    SEL challengeURLSelector =
        NSSelectorFromString(@"challengeURLString");
    id challengePayload = response;
    id requestID = BHTSendObject(
        challengePayload, requestIDSelector);
    id challengeURL = BHTSendObject(
        challengePayload, challengeURLSelector);
    if ((!requestID || !challengeURL) && error) {
        id failureRequestID = BHTSendObject(error, requestIDSelector);
        id failureChallengeURL =
            BHTSendObject(error, challengeURLSelector);
        if (failureRequestID && failureChallengeURL) {
            challengePayload = error;
            requestID = failureRequestID;
            challengeURL = failureChallengeURL;
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventChallengeRecoveredFromFailureObject,
                nil, nil);
        }
    }
    if (requestID && challengeURL) {
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventChallengeRequired,
            @"challenge_required", nil);
        if (!success) {
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventChallengeRecoveredFromFailedCompletion,
                nil, nil);
        }
        __weak typeof(self) weakSelf = self;
        BOOL handled = NO;
        @try {
            handled = BHTPresentNativeLoginChallenge(
                challengePayload, fallbackUsername, self,
                self.addAccountController,
                ^(BOOL challengeSuccess,
                  NSString* challengeFailure) {
                    dispatch_async(
                        dispatch_get_main_queue(), ^{
                            [weakSelf
                                finishWithSuccess:challengeSuccess
                                 failureCategory:challengeFailure];
                        });
                });
        } @catch (__unused NSException* exception) {
            handled = YES;
            [self finishWithSuccess:NO
                   failureCategory:@"challenge_exception"];
        }
        if (handled) return;
    }

    if (!success || !response) {
        if (!response) {
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventRejectionWithoutPayload,
                nil, nil);
        }
        [self finishWithSuccess:NO
               failureCategory:BHTCompatibilityFailureCategory(
                                   error, response != nil)];
        return;
    }

    NSString* token =
        BHTSendObject(response, NSSelectorFromString(@"token"));
    NSString* secret =
        BHTSendObject(response, NSSelectorFromString(@"tokenSecret"));
    NSString* screenName =
        BHTSendObject(response, NSSelectorFromString(@"screenName"));
    if (screenName.length == 0) {
        screenName =
            BHTSendObject(response, NSSelectorFromString(@"username"));
    }
    uint64_t userID = BHTSendUnsignedValue(
        response, NSSelectorFromString(@"userId"));

    if (token.length > 0 && secret.length > 0) {
        BOOL registered = NO;
        id account = nil;
        @try {
            account = BHTBuildNativeAccount(
                token, secret,
                screenName.length > 0
                    ? screenName
                    : fallbackUsername,
                userID);
            registered = BHTRegisterNativeAccount(account);
            if (registered) {
                BHTDetailedReplyDiagnosticsNoteCompatibilityAccount(
                    account);
            }
        } @catch (__unused NSException* exception) {
            registered = NO;
        }
        if (!registered) {
            [self
                finishWithSuccess:NO
                 failureCategory:@"account_registration_failed"];
            return;
        }
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventAuthenticated,
            @"authenticated", nil);

        self.passwordField.text = @"";
        BHTCompatibilityResult completion =
            ^(BOOL switched, NSString* switchFailure) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self
                        finishWithSuccess:switched
                         failureCategory:switchFailure];
                });
            };
        if (self.addAccountController) {
            BHTCompleteAddAccountFlow(
                account, self, self.addAccountController,
                nil, completion);
        } else {
            BHTCompleteSignedOutFlowAndSwitchAccount(
                account, self, completion);
        }
        return;
    }

    [self finishWithSuccess:NO
           failureCategory:@"unsupported_response"];
}

- (void)startPasswordCommandForUsername:
            (NSString*)username
                                 password:(NSString*)password
                                  metrics:(NSString*)metrics {
    if (self.cancelled) return;
    self.requestStarted = YES;
    self.navigationItem.leftBarButtonItem.enabled = NO;
    __weak typeof(self) weakSelf = self;
    void (^completion)(BOOL, id, id) =
        ^(BOOL success, id response, id error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                BHTCompatibilityLoginViewController* strongSelf =
                    weakSelf;
                if (!strongSelf || strongSelf.cancelled) return;
                @try {
                    [strongSelf
                        handlePasswordResponse:success
                                      response:response
                                         error:error
                              fallbackUsername:username];
                } @catch (__unused NSException* exception) {
                    [strongSelf
                        finishWithSuccess:NO
                         failureCategory:@"response_exception"];
                }
            });
        };

    id command = nil;
    @try {
        command = BHTCreatePasswordCommand(
            username, password, metrics, completion);
        if (!command || !BHTStartPasswordCommand(command)) {
            self.requestStarted = NO;
            [self finishWithSuccess:NO
                   failureCategory:@"command_start_failed"];
            return;
        }
    } @catch (__unused NSException* exception) {
        self.requestStarted = NO;
        [self finishWithSuccess:NO
               failureCategory:@"command_exception"];
        return;
    }
    BHTCompatibilityRecord(
        BHTCompatibilityLoginEventCommandStarted,
        @"command_started", nil);
    self.statusLabel.text =
        BHTCompatibilityLocalized(
            @"COMPATIBILITY_SIGN_IN_CONTACTING_X");
}

- (void)signInTapped {
    if (self.cancelled || self.requestStarted ||
        self.metricsCollector || self.sharingReport) {
        return;
    }
    if (!BHTCompatibilityVersionIsSupported()) {
        [self finishWithSuccess:NO
               failureCategory:@"unsupported_version"];
        return;
    }
    if (!BHTCompatibilityRuntimeIsAvailable()) {
        self.runtimeAvailable = NO;
        [self finishWithSuccess:NO
               failureCategory:@"missing_runtime"];
        return;
    }

    BOOL identifierNormalized = NO;
    NSString* username = BHTNormalizedCompatibilityIdentifier(
        self.usernameField.text, &identifierNormalized);
    if (identifierNormalized) {
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventIdentifierNormalized,
            nil, nil);
    }
    NSString* password = [self.passwordField.text copy];
    if (username.length == 0 || password.length == 0) {
        [self setBusy:NO
               status:BHTCompatibilityLocalized(
                          @"COMPATIBILITY_SIGN_IN_REQUIRED_ERROR")];
        return;
    }

    BHTCompatibilityRecord(
        BHTCompatibilityLoginEventAttempted,
        @"preparing_metrics", nil);
    self.passwordField.text = @"";
    [self.view endEditing:YES];
    [self setBusy:YES
           status:BHTCompatibilityLocalized(
                      @"COMPATIBILITY_SIGN_IN_PREPARING")];

    self.metricsCollector =
        [BHTCompatibilityMetricsCollector new];
    self.metricsCollector.hostView = self.view;
    NSTimeInterval preflightStartedAt =
        NSProcessInfo.processInfo.systemUptime;
    __weak typeof(self) weakSelf = self;
    [self.metricsCollector
        startWithCompletion:^(__unused NSString* metrics) {
            NSTimeInterval elapsed =
                NSProcessInfo.processInfo.systemUptime -
                preflightStartedAt;
            NSTimeInterval remaining = MAX(
                0.0,
                BHTCompatibilityMinimumPreflightDuration - elapsed);
            dispatch_after(
                dispatch_time(
                    DISPATCH_TIME_NOW,
                    (int64_t)(remaining * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    BHTCompatibilityLoginViewController* strongSelf =
                        weakSelf;
                    if (!strongSelf || strongSelf.cancelled) return;
                    strongSelf.metricsCollector = nil;
                    BHTCompatibilityRecord(
                        BHTCompatibilityLoginEventMinimumPreflightElapsed,
                        @"preflight_complete", nil);
                    // The successful beta 29 and beta 36 device reports both
                    // reached X only after this preflight window and supplied
                    // nil uiMetrics. Keep the captured value diagnostic-only.
                    [strongSelf
                        startPasswordCommandForUsername:username
                                               password:password
                                                metrics:nil];
                });
        }];
}

@end

// Compatibility Sign-in is deliberately separate from X's normal onboarding.
// It uses the guarded X 12.9 password command and hands successful accounts
// back to X's own account service without changing the native sign-in action.
static void BHTPresentCompatibilitySignInForContext(
    UIViewController* presenter,
    UIViewController* addAccountController) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (BHTCompatibilityPresentedSignInController) {
            return;
        }

        UIViewController* source =
            BHTTopViewController(presenter) ?:
            BHTActiveViewController();
        if (!source) return;

        if (!BHTCompatibilityVersionIsSupported()) {
            UIAlertController* alert = [UIAlertController
                alertControllerWithTitle:
                    BHTCompatibilityLocalized(
                        @"COMPATIBILITY_SIGN_IN_TITLE")
                                 message:BHTCompatibilityLocalized(
                                             @"COMPATIBILITY_SIGN_IN_VERSION_ERROR")
                          preferredStyle:
                              UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction
                actionWithTitle:
                    BHTCompatibilityLocalized(
                        @"COMPATIBILITY_SIGN_IN_OK")
                          style:UIAlertActionStyleDefault
                        handler:nil]];
            [source presentViewController:alert
                                 animated:YES
                               completion:nil];
            return;
        }

        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventPresented,
            @"presented", @"none");
        BHTCompatibilityLoginViewController* login =
            [BHTCompatibilityLoginViewController new];
        login.addAccountController = addAccountController;
        UINavigationController* navigation =
            [[UINavigationController alloc]
                initWithRootViewController:login];
        navigation.modalPresentationStyle =
            UIModalPresentationFormSheet;
        navigation.preferredContentSize =
            CGSizeMake(520.0, 620.0);
        BHTCompatibilityPresentedSignInController =
            navigation;
        [source presentViewController:navigation
                            animated:YES
                          completion:nil];
    });
}

static void BHTSetReportShareSenderEnabled(
    id sender,
    BOOL enabled) {
    SEL selector = @selector(setEnabled:);
    if (sender && [sender respondsToSelector:selector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            sender, selector, enabled);
    }
}

static void BHTSharePreLoginCompatibilityReport(
    UIViewController* presenter,
    id sender) {
    dispatch_async(dispatch_get_main_queue(), ^{
        bool expectedPending = false;
        if (!atomic_compare_exchange_strong_explicit(
                &BHTCompatibilityPreLoginReportSharePending,
                &expectedPending, true,
                memory_order_acq_rel,
                memory_order_relaxed)) {
            return;
        }
        BHTSetReportShareSenderEnabled(sender, NO);
        __weak UIViewController* weakPresenter = presenter;
        BHTWriteCompatibilityReportAsync(^(NSURL* reportURL) {
            atomic_store_explicit(
                &BHTCompatibilityPreLoginReportSharePending,
                false, memory_order_release);
            BHTSetReportShareSenderEnabled(sender, YES);

            UIViewController* source =
                BHTTopViewController(weakPresenter) ?:
                BHTActiveViewController();
            if (!reportURL.isFileURL || !source) {
                if (reportURL.isFileURL) {
                    [NSFileManager.defaultManager
                        removeItemAtURL:reportURL
                                  error:nil];
                }
                if (source) {
                    UIAlertController* errorAlert = [UIAlertController
                        alertControllerWithTitle:
                            BHTCompatibilityLocalized(
                                @"COMPATIBILITY_SIGN_IN_TITLE")
                                         message:
                            BHTCompatibilityLocalized(
                                @"COMPATIBILITY_SIGN_IN_REPORT_ERROR")
                                  preferredStyle:
                            UIAlertControllerStyleAlert];
                    [errorAlert addAction:[UIAlertAction
                        actionWithTitle:BHTCompatibilityLocalized(
                                            @"COMPATIBILITY_SIGN_IN_OK")
                                  style:UIAlertActionStyleDefault
                                handler:nil]];
                    [source presentViewController:errorAlert
                                         animated:YES
                                       completion:nil];
                }
                return;
            }

            UIActivityViewController* share =
                [[UIActivityViewController alloc]
                    initWithActivityItems:@[reportURL]
                    applicationActivities:nil];
            UIPopoverPresentationController* popover =
                share.popoverPresentationController;
            if ([sender isKindOfClass:UIBarButtonItem.class]) {
                popover.barButtonItem = sender;
            } else if ([sender isKindOfClass:UIView.class]) {
                popover.sourceView = sender;
                popover.sourceRect = ((UIView*)sender).bounds;
            } else {
                popover.sourceView = source.view;
                popover.sourceRect = CGRectMake(
                    CGRectGetMidX(source.view.bounds),
                    CGRectGetMidY(source.view.bounds),
                    1.0, 1.0);
            }
            share.completionWithItemsHandler =
                ^(__unused UIActivityType activityType,
                  __unused BOOL completed,
                  __unused NSArray* returnedItems,
                  __unused NSError* activityError) {
                    [NSFileManager.defaultManager
                        removeItemAtURL:reportURL
                                  error:nil];
                };
            [source presentViewController:share
                                 animated:YES
                               completion:nil];
        });
    });
}

static void BHTPresentCompatibilityUnavailableAlert(
    UIViewController* presenter) {
    UIViewController* source =
        BHTTopViewController(presenter) ?:
        BHTActiveViewController();
    if (!source) return;
    NSString* message = BHTCompatibilityVersionIsSupported()
        ? BHTCompatibilityLocalized(
              @"COMPATIBILITY_SIGN_IN_RUNTIME_ERROR")
        : BHTCompatibilityLocalized(
              @"COMPATIBILITY_SIGN_IN_VERSION_ERROR");
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:
            BHTCompatibilityLocalized(
                @"COMPATIBILITY_SIGN_IN_TITLE")
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction
        actionWithTitle:BHTCompatibilityLocalized(
                            @"COMPATIBILITY_SIGN_IN_SHARE_REPORT")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction* action) {
                    dispatch_after(
                        dispatch_time(
                            DISPATCH_TIME_NOW,
                            (int64_t)(150 * NSEC_PER_MSEC)),
                        dispatch_get_main_queue(), ^{
                            BHTSharePreLoginCompatibilityReport(
                                presenter, nil);
                        });
                }]];
    [alert addAction:[UIAlertAction
        actionWithTitle:BHTCompatibilityLocalized(
                            @"COMPATIBILITY_SIGN_IN_OK")
                  style:UIAlertActionStyleCancel
                handler:nil]];
    [source presentViewController:alert
                         animated:YES
                       completion:nil];
}

static void BHTClearNativeInitialDispatchPending(void) {
    BHTCompatibilityNativeInitialPresentedController = nil;
    atomic_store_explicit(
        &BHTCompatibilityNativeInitialDispatchPending,
        false, memory_order_release);
}

static void BHTReconcileNativeInitialPresentation(
    UIViewController* hostController,
    UIViewController* baselinePresentedController,
    NSUInteger attempt) {
    if (!atomic_load_explicit(
            &BHTCompatibilityNativeInitialDispatchPending,
            memory_order_acquire)) {
        return;
    }

    UIViewController* observed =
        BHTCompatibilityNativeInitialPresentedController;
    if (observed) {
        if (!observed.presentingViewController ||
            observed.isBeingDismissed) {
            BHTClearNativeInitialDispatchPending();
            return;
        }
    } else {
        UIViewController* current =
            hostController.presentedViewController;
        if (current &&
            current != baselinePresentedController &&
            !current.isBeingDismissed) {
            BHTCompatibilityNativeInitialPresentedController =
                current;
        } else if (attempt >= 20) {
            // Recover only when X never presented a different controller.
            // Once a login controller is observed, the guard follows its
            // actual dismissal instead of expiring on a fixed timer.
            BHTClearNativeInitialDispatchPending();
            return;
        }
    }

    __weak UIViewController* weakHost = hostController;
    __weak UIViewController* weakBaseline =
        baselinePresentedController;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(500 * NSEC_PER_MSEC)),
        dispatch_get_main_queue(), ^{
            BHTReconcileNativeInitialPresentation(
                weakHost, weakBaseline, attempt + 1);
        });
}

static void BHTPresentNativeInitialCompatibilitySignIn(
    UIViewController* presenter) {
    dispatch_async(dispatch_get_main_queue(), ^{
        bool expectedPending = false;
        if (!atomic_compare_exchange_strong_explicit(
                &BHTCompatibilityNativeInitialDispatchPending,
                &expectedPending, true,
                memory_order_acq_rel,
                memory_order_relaxed)) {
            return;
        }
        atomic_fetch_add_explicit(
            &BHTCompatibilityNativeInitialAttempted, 1,
            memory_order_relaxed);
        BHTCompatibilityRecord(
            BHTCompatibilityLoginEventPresented,
            @"native_initial_requested", @"none");

        if (!BHTCompatibilityVersionIsSupported() ||
            !BHTNativeInitialSignInSignatureIsSupported()) {
            atomic_fetch_add_explicit(
                &BHTCompatibilityNativeInitialFailed, 1,
                memory_order_relaxed);
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventFailed,
                @"native_initial_unavailable",
                @"native_login_flow_unavailable");
            BHTClearNativeInitialDispatchPending();
            BHTPresentCompatibilityUnavailableAlert(presenter);
            return;
        }

        Class hostClass =
            NSClassFromString(@"T1HostViewController");
        SEL sharedSelector =
            NSSelectorFromString(@"sharedHostViewController");
        id host = ((id (*)(id, SEL))objc_msgSend)(
            (id)hostClass, sharedSelector);
        if (!host) {
            atomic_fetch_add_explicit(
                &BHTCompatibilityNativeInitialFailed, 1,
                memory_order_relaxed);
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventFailed,
                @"native_initial_host_missing",
                @"native_host_unavailable");
            BHTClearNativeInitialDispatchPending();
            BHTPresentCompatibilityUnavailableAlert(presenter);
            return;
        }

        UIViewController* hostController =
            [host isKindOfClass:UIViewController.class]
                ? (UIViewController*)host
                : nil;
        if (!hostController) {
            atomic_fetch_add_explicit(
                &BHTCompatibilityNativeInitialFailed, 1,
                memory_order_relaxed);
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventFailed,
                @"native_initial_host_type_mismatch",
                @"native_host_unavailable");
            BHTClearNativeInitialDispatchPending();
            BHTPresentCompatibilityUnavailableAlert(presenter);
            return;
        }
        UIViewController* baselinePresentedController =
            hostController.presentedViewController;

        SEL loginSelector = NSSelectorFromString(
            @"showLoginFlowWithSource:completion:");
        typedef void (^BHTNativeLoginCompletion)(void);
        typedef void (*BHTShowNativeLoginFunction)(
            id, SEL, NSInteger, BHTNativeLoginCompletion);
        BHTNativeLoginCompletion completion = ^{
            atomic_fetch_add_explicit(
                &BHTCompatibilityNativeInitialCallbackInvoked, 1,
                memory_order_relaxed);
            // X owns the callback semantics; completion confirms its flow
            // returned, not necessarily that authentication succeeded.
            BHTCompatibilitySetStage(
                @"native_initial_completion_called", nil);
        };
        @try {
            ((BHTShowNativeLoginFunction)objc_msgSend)(
                host, loginSelector, 0, [completion copy]);
            atomic_fetch_add_explicit(
                &BHTCompatibilityNativeInitialDispatched, 1,
                memory_order_relaxed);
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventAttempted,
                @"native_initial_dispatched", nil);
            BHTReconcileNativeInitialPresentation(
                hostController, baselinePresentedController, 0);
        } @catch (__unused NSException* exception) {
            atomic_fetch_add_explicit(
                &BHTCompatibilityNativeInitialFailed, 1,
                memory_order_relaxed);
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventFailed,
                @"native_initial_dispatch_failed",
                @"native_login_flow_exception");
            BHTClearNativeInitialDispatchPending();
            BHTPresentCompatibilityUnavailableAlert(presenter);
        }
    });
}

static void BHTPresentNativeAddAccountCompatibilitySignIn(
    UIViewController* accountsController,
    id sender) {
    dispatch_async(dispatch_get_main_queue(), ^{
        atomic_fetch_add_explicit(
            &BHTCompatibilityNativeAddAccountAttempted, 1,
            memory_order_relaxed);
        BHTCompatibilitySetStage(
            @"native_add_account_requested", @"none");
        Class accountsClass =
            NSClassFromString(@"T1AccountsViewController");
        SEL selector =
            NSSelectorFromString(@"_addAccount:sender:");
        if (!BHTCompatibilityVersionIsSupported() ||
            !accountsClass ||
            !accountsController ||
            ![accountsController isKindOfClass:accountsClass] ||
            !BHTNativeAddAccountSignInSignatureIsSupported() ||
            ![accountsController respondsToSelector:selector]) {
            atomic_fetch_add_explicit(
                &BHTCompatibilityNativeAddAccountFailed, 1,
                memory_order_relaxed);
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventFailed,
                @"native_add_account_unavailable",
                @"native_add_account_flow_unavailable");
            BHTPresentCompatibilityUnavailableAlert(
                accountsController);
            return;
        }

        @try {
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(
                accountsController, selector, NO,
                sender ?: accountsController);
            atomic_fetch_add_explicit(
                &BHTCompatibilityNativeAddAccountDispatched, 1,
                memory_order_relaxed);
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventAttempted,
                @"native_add_account_dispatched", nil);
        } @catch (__unused NSException* exception) {
            atomic_fetch_add_explicit(
                &BHTCompatibilityNativeAddAccountFailed, 1,
                memory_order_relaxed);
            BHTCompatibilityRecord(
                BHTCompatibilityLoginEventFailed,
                @"native_add_account_dispatch_failed",
                @"native_add_account_flow_exception");
            BHTPresentCompatibilityUnavailableAlert(
                accountsController);
        }
    });
}

void BHTPresentCompatibilitySignIn(
    UIViewController* presenter) {
    BHTPresentCompatibilitySignInForContext(
        presenter, nil);
}

void BHTPresentCompatibilitySignInForAddingAccount(
    UIViewController* accountsController) {
    BHTPresentCompatibilitySignInForContext(
        accountsController, accountsController);
}

@interface BHTCompatibilityEntryTarget : NSObject
@property(nonatomic, weak) UIViewController* presenter;
- (void)openCompatibilitySignIn;
- (void)shareCompatibilityReport:(id)sender;
- (void)openCompatibilitySignInForAddingAccount:(id)sender;
@end

@implementation BHTCompatibilityEntryTarget
- (void)openCompatibilitySignIn {
    BHTPresentCompatibilitySignIn(self.presenter);
}

- (void)shareCompatibilityReport:(id)sender {
    BHTSharePreLoginCompatibilityReport(
        self.presenter, sender);
}

- (void)openCompatibilitySignInForAddingAccount:(id)sender {
    atomic_fetch_add_explicit(
        &BHTCompatibilityAddAccountEntryOpened, 1,
        memory_order_relaxed);
    BHTPresentCompatibilitySignInForAddingAccount(
        self.presenter);
}
@end

void BHTInstallCompatibilitySignInEntry(
    UIViewController* onboardingController) {
    if (!onboardingController ||
        !BHTCompatibilityVersionIsSupported()) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (objc_getAssociatedObject(
                onboardingController,
                &BHTCompatibilityEntryButtonKey)) {
            return;
        }

        UIView* hostView = onboardingController.view;
        if (!hostView) return;

        BHTCompatibilityEntryTarget* target =
            [BHTCompatibilityEntryTarget new];
        target.presenter = onboardingController;

        UIButton* button =
            [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button
            setTitle:BHTCompatibilityLocalized(
                         @"COMPATIBILITY_SIGN_IN_TITLE")
            forState:UIControlStateNormal];
        button.titleLabel.font =
            [UIFont preferredFontForTextStyle:
                        UIFontTextStyleFootnote];
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        button.backgroundColor =
            [UIColor.secondarySystemBackgroundColor
                colorWithAlphaComponent:0.92];
        button.layer.cornerRadius = 15.0;
        button.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        button.layer.borderColor =
            UIColor.separatorColor.CGColor;
        button.contentEdgeInsets =
            UIEdgeInsetsMake(7.0, 12.0, 7.0, 12.0);
        button.accessibilityIdentifier =
            @"NeoFreeBird.CompatibilitySignIn";
        button.layer.zPosition = CGFLOAT_MAX;
        [button addTarget:target
                   action:@selector(openCompatibilitySignIn)
         forControlEvents:UIControlEventTouchUpInside];
        [hostView addSubview:button];

        UIButton* reportButton =
            [UIButton buttonWithType:UIButtonTypeSystem];
        reportButton.translatesAutoresizingMaskIntoConstraints = NO;
        [reportButton
            setTitle:BHTCompatibilityLocalized(
                         @"COMPATIBILITY_SIGN_IN_SHARE_REPORT")
            forState:UIControlStateNormal];
        reportButton.titleLabel.font =
            [UIFont preferredFontForTextStyle:
                        UIFontTextStyleCaption1];
        reportButton.titleLabel.adjustsFontForContentSizeCategory = YES;
        reportButton.backgroundColor =
            [UIColor.secondarySystemBackgroundColor
                colorWithAlphaComponent:0.92];
        reportButton.layer.cornerRadius = 13.0;
        reportButton.layer.borderWidth =
            1.0 / UIScreen.mainScreen.scale;
        reportButton.layer.borderColor =
            UIColor.separatorColor.CGColor;
        reportButton.contentEdgeInsets =
            UIEdgeInsetsMake(6.0, 10.0, 6.0, 10.0);
        reportButton.accessibilityIdentifier =
            @"NeoFreeBird.ShareLoginReport";
        reportButton.layer.zPosition = CGFLOAT_MAX;
        [reportButton addTarget:target
                         action:@selector(
                             shareCompatibilityReport:)
               forControlEvents:UIControlEventTouchUpInside];
        [hostView addSubview:reportButton];

        [NSLayoutConstraint activateConstraints:@[
            [button.topAnchor
                constraintEqualToAnchor:
                    hostView.safeAreaLayoutGuide.topAnchor
                               constant:10.0],
            [button.trailingAnchor
                constraintEqualToAnchor:
                    hostView.safeAreaLayoutGuide.trailingAnchor
                               constant:-12.0],
            [reportButton.topAnchor
                constraintEqualToAnchor:button.bottomAnchor
                               constant:8.0],
            [reportButton.trailingAnchor
                constraintEqualToAnchor:button.trailingAnchor],
        ]];
        [hostView bringSubviewToFront:button];
        [hostView bringSubviewToFront:reportButton];

        objc_setAssociatedObject(
            onboardingController,
            &BHTCompatibilityEntryButtonKey, button,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            onboardingController,
            &BHTCompatibilityReportButtonKey, reportButton,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            onboardingController,
            &BHTCompatibilityEntryTargetKey, target,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

void BHTInstallCompatibilityAddAccountSignInEntry(
    UIViewController* accountsController) {
    if (!accountsController ||
        !BHTCompatibilitySignInIsAvailable() ||
        !BHTNativeAddAccountCompletionGetterIsSupported()) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIBarButtonItem* item = objc_getAssociatedObject(
            accountsController,
            &BHTCompatibilityAddAccountItemKey);
        if (!item) {
            BHTCompatibilityEntryTarget* target =
                [BHTCompatibilityEntryTarget new];
            target.presenter = accountsController;

            item = [[UIBarButtonItem alloc]
                initWithTitle:BHTCompatibilityLocalized(
                                  @"COMPATIBILITY_SIGN_IN_ADD_ACCOUNT_ACTION")
                         style:UIBarButtonItemStylePlain
                        target:target
                        action:@selector(
                            openCompatibilitySignInForAddingAccount:)];
            item.accessibilityIdentifier =
                @"NeoFreeBird.CompatibilityAddAccountSignIn";
            item.accessibilityLabel =
                BHTCompatibilityLocalized(
                    @"COMPATIBILITY_SIGN_IN_TITLE");

            objc_setAssociatedObject(
                accountsController,
                &BHTCompatibilityAddAccountItemKey, item,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(
                accountsController,
                &BHTCompatibilityAddAccountTargetKey, target,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            atomic_fetch_add_explicit(
                &BHTCompatibilityAddAccountEntryInstalled, 1,
                memory_order_relaxed);
        }

        NSArray<UIBarButtonItem*>* currentItems =
            accountsController.navigationItem.rightBarButtonItems ?:
            @[];
        if (![currentItems containsObject:item]) {
            NSMutableArray<UIBarButtonItem*>* updatedItems =
                [currentItems mutableCopy];
            [updatedItems addObject:item];
            [accountsController.navigationItem
                setRightBarButtonItems:[updatedItems copy]
                              animated:NO];
        }
    });
}

NSDictionary<NSString*, id>*
BHTCompatibilitySignInDiagnosticSnapshot(void) {
    NSArray<NSString*>* missingRequirements =
        BHTMissingCompatibilityRequirements();
    NSArray<NSString*>* names = @[
        @"presented",
        @"attempted",
        @"metricsResolved",
        @"metricsTimedOut",
        @"metricsCollectorAttached",
        @"metricsResolvedFromNavigation",
        @"metricsResolvedFromScript",
        @"minimumPreflightElapsed",
        @"commandStarted",
        @"commandCompletedSuccessfully",
        @"commandCompletedUnsuccessfully",
        @"commandPayloadPresent",
        @"commandFailureObjectPresent",
        @"challengeRecoveredFromFailedCompletion",
        @"challengeRecoveredFromFailureObject",
        @"rejectionWithoutPayload",
        @"identifierNormalized",
        @"authenticated",
        @"challengeRequired",
        @"challengePresented",
        @"accountRegistered",
        @"failed",
    ];
    NSMutableDictionary* counters =
        [NSMutableDictionary dictionaryWithCapacity:names.count];
    [names enumerateObjectsUsingBlock:^(
               NSString* name, NSUInteger index, BOOL* stop) {
        counters[name] =
            @(atomic_load_explicit(
                &BHTCompatibilityLoginCounters[index],
                memory_order_relaxed));
    }];
    counters[@"addAccountEntryInstalled"] =
        @(atomic_load_explicit(
            &BHTCompatibilityAddAccountEntryInstalled,
            memory_order_relaxed));
    counters[@"addAccountEntryOpened"] =
        @(atomic_load_explicit(
            &BHTCompatibilityAddAccountEntryOpened,
            memory_order_relaxed));
    counters[@"accountHandoffAttempted"] =
        @(atomic_load_explicit(
            &BHTCompatibilityAccountHandoffAttempted,
            memory_order_relaxed));
    counters[@"accountHandoffDispatched"] =
        @(atomic_load_explicit(
            &BHTCompatibilityAccountHandoffDispatched,
            memory_order_relaxed));
    counters[@"accountHandoffFailed"] =
        @(atomic_load_explicit(
            &BHTCompatibilityAccountHandoffFailed,
            memory_order_relaxed));
    NSString* lastStage;
    NSString* lastFailure;
    BOOL lastCommandSucceeded;
    BOOL lastCommandPayloadPresent;
    BOOL lastCommandFailureObjectPresent;
    NSString* lastCommandPayloadClass;
    NSString* lastCommandFailureClass;
    NSString* lastCommandFailureDomain;
    NSInteger lastCommandFailureCode;
    @synchronized(BHTCompatibilityLoginLock()) {
        lastStage = [BHTCompatibilityLoginLastStage copy] ?: @"idle";
        lastFailure =
            [BHTCompatibilityLoginLastFailure copy] ?: @"none";
        lastCommandSucceeded =
            BHTCompatibilityLastCommandSucceeded;
        lastCommandPayloadPresent =
            BHTCompatibilityLastCommandPayloadPresent;
        lastCommandFailureObjectPresent =
            BHTCompatibilityLastCommandFailureObjectPresent;
        lastCommandPayloadClass =
            [BHTCompatibilityLastCommandPayloadClass copy] ?: @"none";
        lastCommandFailureClass =
            [BHTCompatibilityLastCommandFailureClass copy] ?: @"none";
        lastCommandFailureDomain =
            [BHTCompatibilityLastCommandFailureDomain copy] ?: @"none";
        lastCommandFailureCode =
            BHTCompatibilityLastCommandFailureCode;
    }
    Class accountsClass =
        NSClassFromString(@"T1AccountsViewController");
    BOOL nativeAddAccountCompletionSelectorAvailable =
        BHTNativeAddAccountCompletionGetterIsSupported();
    BOOL addAccountEntryAvailable =
        missingRequirements.count == 0 &&
        accountsClass &&
        [accountsClass instancesRespondToSelector:
                           @selector(viewWillAppear:)] &&
        [accountsClass instancesRespondToSelector:
                           @selector(viewDidAppear:)] &&
        nativeAddAccountCompletionSelectorAvailable;
    return @{
        @"targetAppVersion": BHTCompatibilityTargetVersion,
        @"appVersionSupported":
            @(BHTCompatibilityVersionIsSupported()),
        @"runtimeAvailable":
            @(missingRequirements.count == 0),
        @"missingRuntimeRequirements":
            missingRequirements,
        @"legacyPasswordRuntimeAvailable":
            @(missingRequirements.count == 0),
        @"legacyPasswordMissingRuntimeRequirements":
            missingRequirements,
        @"preLoginDiagnosticsEligible":
            @(BHTCompatibilityVersionIsSupported()),
        @"addAccountEntryAvailable":
            @(addAccountEntryAvailable),
        @"nativeAddAccountCompletionSelectorAvailable":
            @(nativeAddAccountCompletionSelectorAvailable),
        @"lastStage": lastStage,
        @"lastFailureCategory": lastFailure,
        @"lastCommandCompletionSucceeded": @(lastCommandSucceeded),
        @"lastCommandPayloadPresent": @(lastCommandPayloadPresent),
        @"lastCommandFailureObjectPresent":
            @(lastCommandFailureObjectPresent),
        @"lastCommandPayloadClass": lastCommandPayloadClass,
        @"lastCommandFailureClass": lastCommandFailureClass,
        @"lastCommandFailureDomain": lastCommandFailureDomain,
        @"lastCommandFailureCode": @(lastCommandFailureCode),
        @"counters": [counters copy],
        @"compatibilitySignInMode": @"dedicated_xauth_password",
        @"nativeSignInRemainsDefault": @YES,
        @"legacyPasswordCommandIsDefault": @NO,
        @"legacyPasswordCommandReachable": @YES,
        @"credentialEntryOwner": @"compatibility_screen_ephemeral",
        @"credentialPersistence": @"x_native_account_storage",
        @"xAuthClientMetadataPolicy":
            @"native_x_12_9",
        @"xAuthClientMetadataTargetVersion":
            BHTCompatibilityTargetVersion,
        @"xAuthClientMetadataOverrideInstalled": @NO,
        @"xAuthClientMetadataOverrideClaimed": @0,
        @"xAuthClientMetadataOverrideApplied": @0,
        @"xAuthClientMetadataScopeTimedOut": @0,
        @"compatibilityRequestProfile":
            @"beta29_native_12_9_preflight",
        @"preflightPolicy":
            @"minimum_12_second_then_nil_metrics",
        @"preflightMinimumDelaySeconds":
            @(BHTCompatibilityMinimumPreflightDuration),
        @"attestationOverridesIncluded": @NO,
        @"credentialBackupIncluded": @NO,
        @"uiMetricsPolicy": @"compatibility_nil",
        @"capturedMetricsUsedForAuthentication": @NO,
        @"capturesCredentials": @NO,
        @"capturesIdentifiers": @NO,
        @"capturesPayloadContents": @NO,
        @"capturesFailureDescriptions": @NO,
        @"capturesFailureUserInfo": @NO,
        @"capturesPrivacySafeFailureFingerprint": @YES,
    };
}
