//
//  ReplyApplicationDiagnostics.x
//  NeoFreeBird
//
//  X 12.9-only observation of decoded and prepared CreateTweet results. X's
//  decoder/preparation runs first. The standard diagnostic records fixed
//  presence categories only. A separately confirmed one-shot beta diagnostic
//  may also retain a bounded, credential-redacted CreateTweet JSON snapshot;
//  it is available only through the explicit detailed export path.
//

#import "Compatibility/BHTCompatibilityReporter.h"
#import "Reply/BHTDetailedReplyDiagnostics.h"
#import "Reply/BHTReplyApplicationDiagnostics.h"

#import <objc/message.h>
#import <objc/runtime.h>
#import <stddef.h>
#import <stdlib.h>

static Class BHTReplyApplicationRequestClass;
static Class BHTReplyApplicationEndpointResponseClass;
static Class BHTReplyApplicationCreateTweetResponseClass;
static Class BHTReplyApplicationCreateTweetPayloadClass;
static Class BHTReplyApplicationSwiftValueClass;
static Ivar BHTReplyApplicationCreateTweetIvar;
static Ivar BHTReplyApplicationTweetResultsIvar;
static BOOL BHTReplyApplicationModelLayoutAvailable;
static char BHTReplyApplicationDetailedRequestTokenKey;

static const char* BHTReplyApplicationUnqualifiedType(
    const char* type) {
    while (type &&
           (*type == 'r' || *type == 'n' || *type == 'N' ||
            *type == 'o' || *type == 'O' || *type == 'R' ||
            *type == 'V')) {
        type++;
    }
    return type;
}

static BOOL BHTReplyApplicationMethodHasDecoderABI(
    Class cls, SEL selector) {
    if (!cls || !selector) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 4) {
        return NO;
    }

    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* result =
        BHTReplyApplicationUnqualifiedType(returnType);
    if (!result || result[0] != '@' || result[1] != '\0') {
        return NO;
    }

    for (unsigned int index = 2; index < 4; index++) {
        char argumentType[16] = {0};
        method_getArgumentType(
            method, index, argumentType,
            sizeof(argumentType));
        const char* argument =
            BHTReplyApplicationUnqualifiedType(argumentType);
        if (!argument || argument[0] != '^' ||
            argument[1] != '@' || argument[2] != '\0') {
            return NO;
        }
    }
    return YES;
}

static BOOL BHTReplyApplicationMethodHasRequestOperationInitializerABI(
    Class cls, SEL selector) {
    if (!cls || !selector) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 6) return NO;

    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* result =
        BHTReplyApplicationUnqualifiedType(returnType);
    if (!result || result[0] != '@' || result[1] != '\0') return NO;

    const char expected[] = {'@', '#', '@', '@'};
    for (unsigned int index = 0; index < 4; index++) {
        char argumentType[16] = {0};
        method_getArgumentType(
            method, index + 2, argumentType, sizeof(argumentType));
        const char* argument =
            BHTReplyApplicationUnqualifiedType(argumentType);
        if (!argument || argument[0] != expected[index] ||
            argument[1] != '\0') {
            return NO;
        }
    }
    return YES;
}

static BOOL BHTReplyApplicationMethodReturnsObjectWithNoArguments(
    Class cls, SEL selector) {
    if (!cls || !selector) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 2) {
        return NO;
    }
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* result =
        BHTReplyApplicationUnqualifiedType(returnType);
    return result && result[0] == '@' && result[1] == '\0';
}

static BOOL BHTReplyApplicationMethodReturnsVoidWithNoArguments(
    Class cls, SEL selector) {
    if (!cls || !selector) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 2) {
        return NO;
    }
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* result =
        BHTReplyApplicationUnqualifiedType(returnType);
    return result && result[0] == 'v' && result[1] == '\0';
}

static BOOL BHTReplyApplicationResolveSingleObjectIvar(
    Class cls,
    const char* expectedName,
    ptrdiff_t expectedOffset,
    Ivar* resolvedIvar) {
    if (!cls || !expectedName || !resolvedIvar) return NO;
    unsigned int count = 0;
    Ivar* ivars = class_copyIvarList(cls, &count);
    Ivar ivar = class_getInstanceVariable(cls, expectedName);
    BOOL valid =
        ivars && count == 1 && ivar && ivars[0] == ivar &&
        ivar_getOffset(ivar) == expectedOffset &&
        expectedOffset >= 0 &&
        (NSUInteger)expectedOffset % sizeof(id) == 0 &&
        (NSUInteger)expectedOffset + sizeof(id) ==
            class_getInstanceSize(cls);
    free(ivars);
    if (valid) *resolvedIvar = ivar;
    return valid;
}

static BHTNativeReplyModelStructureState
BHTReplyApplicationModelStructureState(id model) {
    if (model && BHTReplyApplicationSwiftValueClass &&
        object_getClass(model) ==
            BHTReplyApplicationSwiftValueClass) {
        // GraphQLActionResponse<CreateTweetOperationResponse> is a Swift
        // value and crosses this Objective-C seam as an opaque Foundation
        // box. Recognize only the exact wrapper class; never unbox it.
        return BHTNativeReplyModelStructureStateOpaqueSwiftValueBox;
    }
    if (!BHTReplyApplicationModelLayoutAvailable) {
        return BHTNativeReplyModelStructureStateLayoutUnavailable;
    }
    if (!model ||
        object_getClass(model) !=
            BHTReplyApplicationCreateTweetResponseClass) {
        return BHTNativeReplyModelStructureStateUnexpectedModelClass;
    }
    @try {
        id createTweet = object_getIvar(
            model, BHTReplyApplicationCreateTweetIvar);
        if (!createTweet) {
            return
                BHTNativeReplyModelStructureStateMissingCreateTweet;
        }
        if (object_getClass(createTweet) !=
            BHTReplyApplicationCreateTweetPayloadClass) {
            return BHTNativeReplyModelStructureStateUnexpectedCreateTweetClass;
        }
        id tweetResults = object_getIvar(
            createTweet, BHTReplyApplicationTweetResultsIvar);
        return tweetResults
            ? BHTNativeReplyModelStructureStatePayloadPresent
            : BHTNativeReplyModelStructureStateMissingTweetResults;
    } @catch (__unused NSException* exception) {
        return BHTNativeReplyModelStructureStateLayoutUnavailable;
    }
}

static id BHTReplyApplicationOriginalRequest(id response) {
    SEL originalRequestSelector =
        NSSelectorFromString(@"originalRequest");
    id originalRequest =
        ((id (*)(id, SEL))objc_msgSend)(
            response, originalRequestSelector);
    if (!BHTReplyApplicationRequestClass ||
        ![originalRequest
            isKindOfClass:BHTReplyApplicationRequestClass]) {
        return nil;
    }
    return originalRequest;
}

static NSURL* BHTReplyApplicationURLFromRequest(id originalRequest) {
    SEL URLSelector = NSSelectorFromString(@"URL");
    if (!BHTReplyApplicationRequestClass ||
        ![originalRequest
            isKindOfClass:BHTReplyApplicationRequestClass]) {
        return nil;
    }
    id candidateURL =
        ((id (*)(id, SEL))objc_msgSend)(
            originalRequest, URLSelector);
    return [candidateURL isKindOfClass:NSURL.class]
        ? candidateURL
        : nil;
}

static NSURL* BHTReplyApplicationRequestURL(id response) {
    return BHTReplyApplicationURLFromRequest(
        BHTReplyApplicationOriginalRequest(response));
}

static NSDictionary* BHTReplyApplicationDetailedToken(id response) {
    id request = BHTReplyApplicationOriginalRequest(response);
    id token = request
        ? objc_getAssociatedObject(
              request, &BHTReplyApplicationDetailedRequestTokenKey)
        : nil;
    return [token isKindOfClass:NSDictionary.class] ? token : nil;
}

static BOOL BHTReplyApplicationGetObject(
    id object, NSString* selectorName, id __autoreleasing* value) {
    if (value) *value = nil;
    @try {
        id result = ((id (*)(id, SEL))objc_msgSend)(
            object, NSSelectorFromString(selectorName));
        if (value) *value = result;
        return YES;
    } @catch (__unused NSException* exception) {
        return NO;
    }
}

%group BHTDetailedWriteOriginalRequestBindingHooks

%hook TNLRequestOperation

- (id)initWithRequest:(__unsafe_unretained id)request
        responseClass:(Class)responseClass
        configuration:(__unsafe_unretained id)configuration
             delegate:(__unsafe_unretained id)delegate {
    id result = %orig(request, responseClass, configuration, delegate);
    if (!result ||
        !BHTDetailedReplyDiagnosticsNetworkCaptureMayBeActive()) {
        return result;
    }
    @try {
        if (object_getClass(request) != BHTReplyApplicationRequestClass ||
            responseClass != BHTReplyApplicationEndpointResponseClass) {
            return result;
        }
        NSURL* requestURL = BHTReplyApplicationURLFromRequest(request);
        NSDictionary* token =
            BHTDetailedReplyDiagnosticsApplicationTokenForRequestURL(
                requestURL);
        if (token) {
            objc_setAssociatedObject(
                request, &BHTReplyApplicationDetailedRequestTokenKey,
                token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (__unused NSException* exception) {
    }
    return result;
}

%end

%end

%group BHTNativeReplyApplicationDecoderHooks

%hook _TtC14GraphQLActions23GraphQLEndpointResponse

- (id)modelWithParseError:(id __autoreleasing*)parseError
                APIErrors:(id __autoreleasing*)APIErrors {
    NSUInteger sessionGeneration = 0;
    BOOL correlated = NO;
    if (BHTReplyWorkflowApplicationDiagnosticWindowMayBeActive()) {
        @try {
            correlated =
                BHTReplyWorkflowDiagnosticSessionForApplicationResponse(
                    &sessionGeneration);
        } @catch (__unused NSException* exception) {
        }
    }

    id model = %orig(parseError, APIErrors);

    @try {
        NSDictionary* detailedToken =
            BHTReplyApplicationDetailedToken(self);
        if (!correlated && !detailedToken) return model;
        NSURL* requestURL =
            BHTReplyApplicationRequestURL(self);
        id decodedParseError = parseError ? *parseError : nil;
        id decodedAPIErrors = APIErrors ? *APIErrors : nil;
        BHTNativeReplyModelStructureState modelStructureState =
            BHTNativeReplyModelStructureStateLayoutUnavailable;
        BOOL eligible =
            BHTNativeReplyApplicationRequestURLIsEligible(
                requestURL);
        if (eligible) {
            modelStructureState =
                BHTReplyApplicationModelStructureState(model);
        }
        if (correlated) {
            BHTRecordNativeReplyApplicationResult(
                sessionGeneration, requestURL, model,
                decodedParseError, decodedAPIErrors,
                modelStructureState);
        }
        if (eligible) {
            if (detailedToken) {
                BHTDetailedReplyDiagnosticsCaptureBoundDecodedResponse(
                    detailedToken, self, model,
                    decodedParseError, decodedAPIErrors);
            } else if (correlated) {
                BHTDetailedReplyDiagnosticsCaptureDecodedResponse(
                    sessionGeneration, self, model,
                    decodedParseError, decodedAPIErrors);
            }
        }
    } @catch (__unused NSException* exception) {
    }
    return model;
}

%end

%end

%group BHTNativeReplyApplicationPreparedHooks

%hook _TtC14GraphQLActions23GraphQLEndpointResponse

- (void)prepare {
    NSUInteger sessionGeneration = 0;
    BOOL correlated = NO;
    if (BHTReplyWorkflowApplicationDiagnosticWindowMayBeActive()) {
        @try {
            correlated =
                BHTReplyWorkflowDiagnosticSessionForApplicationResponse(
                    &sessionGeneration);
        } @catch (__unused NSException* exception) {
        }
    }

    %orig;

    @try {
        NSDictionary* detailedToken =
            BHTReplyApplicationDetailedToken(self);
        if (!correlated && !detailedToken) return;
        NSURL* requestURL =
            BHTReplyApplicationRequestURL(self);
        if (!BHTNativeReplyApplicationRequestURLIsEligible(
                requestURL)) {
            if (correlated) {
                BHTRecordNativeReplyPreparedResponse(
                    sessionGeneration, requestURL, NO,
                    nil, nil, nil, nil, nil, nil, nil, nil);
            }
            return;
        }
        id finalModel = nil;
        id finalParseError = nil;
        id finalOperationError = nil;
        id finalAPIErrors = nil;
        id effectiveModel = nil;
        id effectiveParseError = nil;
        id effectiveOperationError = nil;
        id effectiveAPIErrors = nil;
        BOOL observationComplete =
            BHTReplyApplicationGetObject(
                self, @"finalModel", &finalModel) &&
            BHTReplyApplicationGetObject(
                self, @"finalParseError", &finalParseError) &&
            BHTReplyApplicationGetObject(
                self, @"finalOperationError", &finalOperationError) &&
            BHTReplyApplicationGetObject(
                self, @"finalAPIErrors", &finalAPIErrors) &&
            BHTReplyApplicationGetObject(
                self, @"model", &effectiveModel) &&
            BHTReplyApplicationGetObject(
                self, @"parseError", &effectiveParseError) &&
            BHTReplyApplicationGetObject(
                self, @"operationError", &effectiveOperationError);
        // X's effective APIErrors getter calls -count on its final override.
        // An explicit NSNull override means "no errors" but cannot receive
        // that selector, so preserve X's intended absence without invoking it.
        if (observationComplete &&
            finalAPIErrors != NSNull.null) {
            observationComplete =
                BHTReplyApplicationGetObject(
                    self, @"APIErrors", &effectiveAPIErrors);
        }
        if (correlated) {
            BHTRecordNativeReplyPreparedResponse(
                sessionGeneration,
                requestURL,
                observationComplete,
                effectiveModel,
                effectiveParseError,
                effectiveOperationError,
                effectiveAPIErrors,
                finalModel,
                finalParseError,
                finalOperationError,
                finalAPIErrors);
        }
        if (detailedToken) {
            BHTDetailedReplyDiagnosticsCaptureBoundPreparedResponse(
                detailedToken,
                observationComplete,
                effectiveModel,
                effectiveParseError,
                effectiveOperationError,
                effectiveAPIErrors,
                finalModel,
                finalParseError,
                finalOperationError,
                finalAPIErrors);
        } else if (correlated) {
            BHTDetailedReplyDiagnosticsCapturePreparedResponse(
                sessionGeneration,
                observationComplete,
                effectiveModel,
                effectiveParseError,
                effectiveOperationError,
                effectiveAPIErrors,
                finalModel,
                finalParseError,
                finalOperationError,
                finalAPIErrors);
        }
    } @catch (__unused NSException* exception) {
    }
}

%end

%end

%ctor {
    NSString* version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (![version isKindOfClass:NSString.class] ||
        ![version isEqualToString:@"12.9"]) {
        return;
    }

    Class responseClass = NSClassFromString(
        @"_TtC14GraphQLActions23GraphQLEndpointResponse");
    Class requestClass = NSClassFromString(@"TFSAPIRequest");
    Class requestOperationClass =
        NSClassFromString(@"TNLRequestOperation");
    Class createTweetResponseClass = NSClassFromString(
        @"_TtC13GraphQLModels28CreateTweetOperationResponse");
    Class createTweetPayloadClass = NSClassFromString(
        @"_TtCC13GraphQLModels28CreateTweetOperationResponse11CreateTweet");
    Class swiftValueClass = NSClassFromString(@"__SwiftValue");
    SEL decoderSelector = NSSelectorFromString(
        @"modelWithParseError:APIErrors:");
    SEL originalRequestSelector =
        NSSelectorFromString(@"originalRequest");
    SEL URLSelector = NSSelectorFromString(@"URL");
    BHTReplyApplicationRequestClass = requestClass;
    BHTReplyApplicationEndpointResponseClass = responseClass;
    BHTReplyApplicationSwiftValueClass = swiftValueClass;
    if (swiftValueClass) {
        BHTMarkNativeReplySwiftValueBoxRecognitionAvailable();
    }
    Ivar createTweetIvar = NULL;
    Ivar tweetResultsIvar = NULL;
    if (BHTReplyApplicationResolveSingleObjectIvar(
            createTweetResponseClass, "createTweet", 16,
            &createTweetIvar) &&
        BHTReplyApplicationResolveSingleObjectIvar(
            createTweetPayloadClass, "tweetResults", 16,
            &tweetResultsIvar)) {
        BHTReplyApplicationCreateTweetResponseClass =
            createTweetResponseClass;
        BHTReplyApplicationCreateTweetPayloadClass =
            createTweetPayloadClass;
        BHTReplyApplicationCreateTweetIvar = createTweetIvar;
        BHTReplyApplicationTweetResultsIvar = tweetResultsIvar;
        BHTReplyApplicationModelLayoutAvailable = YES;
        BHTMarkNativeReplyModelStructureLayoutAvailable();
    }
    BOOL requestAccessorsAvailable =
        BHTReplyApplicationMethodReturnsObjectWithNoArguments(
            responseClass, originalRequestSelector) &&
        BHTReplyApplicationMethodReturnsObjectWithNoArguments(
            requestClass, URLSelector);
    SEL requestOperationInitializer = NSSelectorFromString(
        @"initWithRequest:responseClass:configuration:delegate:");
    BOOL applicationBindingHookAvailable =
        requestAccessorsAvailable && requestOperationClass &&
        BHTReplyApplicationMethodHasRequestOperationInitializerABI(
            requestOperationClass, requestOperationInitializer);
    if (applicationBindingHookAvailable) {
        %init(BHTDetailedWriteOriginalRequestBindingHooks);
    }
    BHTDetailedReplyDiagnosticsSetApplicationBindingHookAvailable(
        applicationBindingHookAvailable);
    if (requestAccessorsAvailable &&
        BHTReplyApplicationMethodHasDecoderABI(
            responseClass, decoderSelector)) {
        %init(BHTNativeReplyApplicationDecoderHooks);
        BHTMarkNativeReplyApplicationHookInstalled();
    }

    NSArray<NSString*>* preparedGetterNames = @[
        @"model",
        @"parseError",
        @"operationError",
        @"APIErrors",
        @"finalModel",
        @"finalParseError",
        @"finalOperationError",
        @"finalAPIErrors",
    ];
    BOOL preparedGettersAvailable = requestAccessorsAvailable;
    for (NSString* getterName in preparedGetterNames) {
        preparedGettersAvailable =
            preparedGettersAvailable &&
            BHTReplyApplicationMethodReturnsObjectWithNoArguments(
                responseClass,
                NSSelectorFromString(getterName));
    }
    if (preparedGettersAvailable &&
        BHTReplyApplicationMethodReturnsVoidWithNoArguments(
            responseClass, NSSelectorFromString(@"prepare"))) {
        %init(BHTNativeReplyApplicationPreparedHooks);
        BHTMarkNativeReplyPreparedHookInstalled();
    }
}
