//
//  ReplyNetworkDiagnostics.x
//  NeoFreeBird
//
//  X 12.9-only, metadata-only observation of native CreateTweet tasks.
//  Every original argument is forwarded unchanged.
//

#import "Reply/BHTReplyRequestDiagnostics.h"
#import "Reply/BHTDetailedReplyDiagnostics.h"
#import "Compatibility/BHTCompatibilityReporter.h"

#import <objc/runtime.h>

static const char* BHTReplyNetworkUnqualifiedType(
    const char* type) {
    while (type &&
           (*type == 'r' || *type == 'n' || *type == 'N' ||
            *type == 'o' || *type == 'O' || *type == 'R' ||
            *type == 'V')) {
        type++;
    }
    return type;
}

static BOOL BHTReplyNetworkMethodHasObjectShape(
    Class cls,
    SEL selector,
    BOOL returnsObject,
    unsigned int explicitArgumentCount) {
    if (!cls || !selector) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method ||
        method_getNumberOfArguments(method) !=
            explicitArgumentCount + 2) {
        return NO;
    }

    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* result =
        BHTReplyNetworkUnqualifiedType(returnType);
    if (!result ||
        (returnsObject ? *result != '@' : *result != 'v')) {
        return NO;
    }

    for (unsigned int index = 0;
         index < explicitArgumentCount; index++) {
        char argumentType[16] = {0};
        method_getArgumentType(
            method, index + 2, argumentType,
            sizeof(argumentType));
        const char* argument =
            BHTReplyNetworkUnqualifiedType(argumentType);
        if (!argument || *argument != '@') return NO;
    }
    return YES;
}

static void BHTReplyNetworkTagFailOpen(
    NSURLRequest* request,
    NSData* suppliedBodyData,
    NSURLSessionTask* task,
    BHTReplyRequestConstructorKind constructorKind) {
    BOOL replyWindowMayBeActive =
        BHTReplyWorkflowNetworkDiagnosticWindowMayBeActive();
    BOOL pairedCaptureMayBeActive =
        BHTDetailedReplyDiagnosticsNetworkCaptureMayBeActive();
    if (!replyWindowMayBeActive && !pairedCaptureMayBeActive) {
        return;
    }
    @try {
        NSUInteger replySessionGeneration = 0;
        if (replyWindowMayBeActive) {
            (void)BHTReplyWorkflowDiagnosticSessionForNetworkRequest(
                &replySessionGeneration);
        }
        if (pairedCaptureMayBeActive &&
            BHTDetailedReplyDiagnosticsRequestIsEligible(request)) {
            // The exact, deadline-aware POST/HTTPS/first-party/CreateTweet
            // gate above must run before this sole HTTPBody access.
            NSData* requestBody = suppliedBodyData ?: request.HTTPBody;
            BHTDetailedReplyDiagnosticsCaptureRequest(
                request, requestBody, task,
                constructorKind < BHTReplyRequestConstructorKindCount
                    ? @[
                          @"dataRequest",
                          @"dataRequestCompletion",
                          @"uploadData",
                          @"uploadDataCompletion",
                          @"uploadFile",
                          @"uploadFileCompletion",
                      ][constructorKind]
                    : @"unknown",
                replySessionGeneration);
        }
        if (replyWindowMayBeActive) {
            BHTTagPotentialNativeReplyRequest(
                request, task, constructorKind);
        }
    } @catch (__unused NSException* exception) {
    }
}

%group BHTNativeReplyDataRequestHook

%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request {
    NSURLSessionDataTask* task = %orig(request);
    BHTReplyNetworkTagFailOpen(
        request, nil, task, BHTReplyRequestConstructorData);
    return task;
}

%end

%end

%group BHTNativeReplyDataRequestCompletionHook

%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(id)completionHandler {
    NSURLSessionDataTask* task =
        %orig(request, completionHandler);
    BHTReplyNetworkTagFailOpen(
        request, nil, task,
        BHTReplyRequestConstructorDataCompletion);
    return task;
}

%end

%end

%group BHTNativeReplyUploadDataHook

%hook NSURLSession

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromData:(NSData*)bodyData {
    NSURLSessionUploadTask* task = %orig(request, bodyData);
    BHTReplyNetworkTagFailOpen(
        request, bodyData, task,
        BHTReplyRequestConstructorUploadData);
    return task;
}

%end

%end

%group BHTNativeReplyUploadDataCompletionHook

%hook NSURLSession

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromData:(NSData*)bodyData
                               completionHandler:(id)completionHandler {
    NSURLSessionUploadTask* task =
        %orig(request, bodyData, completionHandler);
    BHTReplyNetworkTagFailOpen(
        request, bodyData, task,
        BHTReplyRequestConstructorUploadDataCompletion);
    return task;
}

%end

%end

%group BHTNativeReplyUploadFileHook

%hook NSURLSession

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromFile:(NSURL*)fileURL {
    NSURLSessionUploadTask* task = %orig(request, fileURL);
    BHTReplyNetworkTagFailOpen(
        request, nil, task,
        BHTReplyRequestConstructorUploadFile);
    return task;
}

%end

%end


%group BHTNativeReplyUploadFileCompletionHook

%hook NSURLSession

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromFile:(NSURL*)fileURL
                               completionHandler:(id)completionHandler {
    NSURLSessionUploadTask* task =
        %orig(request, fileURL, completionHandler);
    BHTReplyNetworkTagFailOpen(
        request, nil, task,
        BHTReplyRequestConstructorUploadFileCompletion);
    return task;
}

%end

%end

%group BHTNativeReplyTNLCompletionHooks

%hook TNLURLSessionTaskOperation

- (void)_network_finalizeDidCompleteTask:(NSURLSessionTask*)task
                              URLSession:(NSURLSession*)session
                                   error:(NSError*)error {
    %orig(task, session, error);
    @try {
        BHTDetailedReplyDiagnosticsCompleteRequest(task, error);
        BHTCompletePotentialNativeReplyRequest(task, error);
    } @catch (__unused NSException* exception) {
    }
}

%end

%end

%group BHTNativeReplyTNLDelegateCompletionHooks

%hook TNLURLSessionTaskOperation

- (void)URLSession:(NSURLSession*)session
              task:(NSURLSessionTask*)task
didCompleteWithError:(NSError*)error {
    %orig(session, task, error);
    @try {
        BHTDetailedReplyDiagnosticsCompleteRequest(task, error);
        BHTCompletePotentialNativeReplyRequest(task, error);
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

    Class sessionClass = NSURLSession.class;
    if (BHTReplyNetworkMethodHasObjectShape(
            sessionClass,
            @selector(dataTaskWithRequest:), YES, 1)) {
        %init(BHTNativeReplyDataRequestHook);
        BHTMarkReplyRequestConstructorHookInstalled(
            BHTReplyRequestConstructorData);
    }
    if (BHTReplyNetworkMethodHasObjectShape(
            sessionClass,
            @selector(dataTaskWithRequest:completionHandler:),
            YES, 2)) {
        %init(BHTNativeReplyDataRequestCompletionHook);
        BHTMarkReplyRequestConstructorHookInstalled(
            BHTReplyRequestConstructorDataCompletion);
    }
    if (BHTReplyNetworkMethodHasObjectShape(
            sessionClass,
            @selector(uploadTaskWithRequest:fromData:),
            YES, 2)) {
        %init(BHTNativeReplyUploadDataHook);
        BHTMarkReplyRequestConstructorHookInstalled(
            BHTReplyRequestConstructorUploadData);
    }
    if (BHTReplyNetworkMethodHasObjectShape(
            sessionClass,
            @selector(uploadTaskWithRequest:fromData:completionHandler:),
            YES, 3)) {
        %init(BHTNativeReplyUploadDataCompletionHook);
        BHTMarkReplyRequestConstructorHookInstalled(
            BHTReplyRequestConstructorUploadDataCompletion);
    }
    if (BHTReplyNetworkMethodHasObjectShape(
            sessionClass,
            @selector(uploadTaskWithRequest:fromFile:),
            YES, 2)) {
        %init(BHTNativeReplyUploadFileHook);
        BHTMarkReplyRequestConstructorHookInstalled(
            BHTReplyRequestConstructorUploadFile);
    }
    if (BHTReplyNetworkMethodHasObjectShape(
            sessionClass,
            @selector(uploadTaskWithRequest:fromFile:completionHandler:),
            YES, 3)) {
        %init(BHTNativeReplyUploadFileCompletionHook);
        BHTMarkReplyRequestConstructorHookInstalled(
            BHTReplyRequestConstructorUploadFileCompletion);
    }

    Class operationClass =
        NSClassFromString(@"TNLURLSessionTaskOperation");
    SEL finalizer = NSSelectorFromString(
        @"_network_finalizeDidCompleteTask:URLSession:error:");
    if (BHTReplyNetworkMethodHasObjectShape(
            operationClass, finalizer, NO, 3)) {
        %init(BHTNativeReplyTNLCompletionHooks);
        BHTMarkReplyRequestCompletionHookInstalled(
            BHTReplyRequestCompletionHookPrivateFinalizer);
    } else {
        SEL delegateCompletion = NSSelectorFromString(
            @"URLSession:task:didCompleteWithError:");
        if (BHTReplyNetworkMethodHasObjectShape(
                operationClass, delegateCompletion, NO, 3)) {
            %init(BHTNativeReplyTNLDelegateCompletionHooks);
            BHTMarkReplyRequestCompletionHookInstalled(
                BHTReplyRequestCompletionHookURLSessionDelegate);
        }
    }
}
