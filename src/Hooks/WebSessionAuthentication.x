//
//  WebSessionAuthentication.x
//  NeoFreeBird
//
//  Adds a user-confirmed web session at the final NSURLSession request
//  boundary. No global NSMutableURLRequest or setValue:/setURL: methods are
//  hooked.
//

#import "Login/BHTSecureWebSession.h"

#import <objc/runtime.h>

static const char* BHTWebSessionUnqualifiedType(const char* type) {
    while (type &&
           (*type == 'r' || *type == 'n' || *type == 'N' ||
            *type == 'o' || *type == 'O' || *type == 'R' ||
            *type == 'V')) {
        type++;
    }
    return type;
}

static BOOL BHTWebSessionTaskMethodHasObjectShape(
    SEL selector,
    unsigned int explicitArgumentCount) {
    Method method = class_getInstanceMethod(
        NSURLSession.class, selector);
    if (!method || method_getNumberOfArguments(method) !=
        explicitArgumentCount + 2) {
        return NO;
    }
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* result =
        BHTWebSessionUnqualifiedType(returnType);
    if (!result || *result != '@') return NO;
    for (unsigned int index = 0;
         index < explicitArgumentCount; index++) {
        char argumentType[16] = {0};
        method_getArgumentType(
            method, index + 2, argumentType,
            sizeof(argumentType));
        const char* argument =
            BHTWebSessionUnqualifiedType(argumentType);
        if (!argument || *argument != '@') return NO;
    }
    return YES;
}

%group BHTWebSessionDataRequestHook

%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request {
    NSURLRequest* authenticated = BHTSecureWebSessionAuthenticatedRequest(request);
    NSURLSessionDataTask* task = %orig(authenticated);
    BHTSecureWebSessionWatchTask(task, authenticated);
    return task;
}

%end

%end


%group BHTWebSessionDataRequestCompletionHook

%hook NSURLSession

- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request
                           completionHandler:(id)completionHandler {
    NSURLRequest* authenticated = BHTSecureWebSessionAuthenticatedRequest(request);
    NSURLSessionDataTask* task = %orig(authenticated, completionHandler);
    BHTSecureWebSessionWatchTask(task, authenticated);
    return task;
}

%end

%end


%group BHTWebSessionUploadDataHook

%hook NSURLSession

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromData:(NSData*)bodyData {
    NSURLRequest* authenticated = BHTSecureWebSessionAuthenticatedRequest(request);
    NSURLSessionUploadTask* task = %orig(authenticated, bodyData);
    BHTSecureWebSessionWatchTask(task, authenticated);
    return task;
}

%end

%end


%group BHTWebSessionUploadDataCompletionHook

%hook NSURLSession

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromData:(NSData*)bodyData
                               completionHandler:(id)completionHandler {
    NSURLRequest* authenticated = BHTSecureWebSessionAuthenticatedRequest(request);
    NSURLSessionUploadTask* task = %orig(authenticated, bodyData, completionHandler);
    BHTSecureWebSessionWatchTask(task, authenticated);
    return task;
}

%end

%end


%group BHTWebSessionUploadFileHook

%hook NSURLSession

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromFile:(NSURL*)fileURL {
    NSURLRequest* authenticated = BHTSecureWebSessionAuthenticatedRequest(request);
    NSURLSessionUploadTask* task = %orig(authenticated, fileURL);
    BHTSecureWebSessionWatchTask(task, authenticated);
    return task;
}

%end

%end


%group BHTWebSessionUploadFileCompletionHook

%hook NSURLSession

- (NSURLSessionUploadTask*)uploadTaskWithRequest:(NSURLRequest*)request
                                        fromFile:(NSURL*)fileURL
                               completionHandler:(id)completionHandler {
    NSURLRequest* authenticated = BHTSecureWebSessionAuthenticatedRequest(request);
    NSURLSessionUploadTask* task = %orig(authenticated, fileURL, completionHandler);
    BHTSecureWebSessionWatchTask(task, authenticated);
    return task;
}

%end

%end


%group BHTWebSessionDownloadRequestHook

%hook NSURLSession

- (NSURLSessionDownloadTask*)downloadTaskWithRequest:(NSURLRequest*)request {
    NSURLRequest* authenticated = BHTSecureWebSessionAuthenticatedRequest(request);
    NSURLSessionDownloadTask* task = %orig(authenticated);
    BHTSecureWebSessionWatchTask(task, authenticated);
    return task;
}

%end

%end


%group BHTWebSessionDownloadRequestCompletionHook

%hook NSURLSession

- (NSURLSessionDownloadTask*)downloadTaskWithRequest:(NSURLRequest*)request
                               completionHandler:(id)completionHandler {
    NSURLRequest* authenticated = BHTSecureWebSessionAuthenticatedRequest(request);
    NSURLSessionDownloadTask* task = %orig(authenticated, completionHandler);
    BHTSecureWebSessionWatchTask(task, authenticated);
    return task;
}

%end

%end


%group BHTWebSessionDelegateRequestHooks
%hook NSURLSession
- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request delegate:(id)delegate {
    NSURLRequest* authenticated = BHTSecureWebSessionAuthenticatedRequest(request);
    NSURLSessionDataTask* task = %orig(authenticated, delegate);
    BHTSecureWebSessionWatchTask(task, authenticated); return task;
}
%end
%end

%group BHTWebSessionDelegateQueueRequestHooks
%hook NSURLSession
- (NSURLSessionDataTask*)dataTaskWithRequest:(NSURLRequest*)request delegate:(id)delegate delegateQueue:(id)queue {
    NSURLRequest* authenticated = BHTSecureWebSessionAuthenticatedRequest(request);
    NSURLSessionDataTask* task = %orig(authenticated, delegate, queue);
    BHTSecureWebSessionWatchTask(task, authenticated); return task;
}
%end
%end

%group BHTWebSessionStreamedRequestHooks
%hook NSURLSession
- (NSURLSessionUploadTask*)uploadTaskWithStreamedRequest:(NSURLRequest*)request {
    NSURLRequest* authenticated = BHTSecureWebSessionAuthenticatedRequest(request);
    NSURLSessionUploadTask* task = %orig(authenticated);
    BHTSecureWebSessionWatchTask(task, authenticated); return task;
}
%end
%end

%ctor {
    NSString* version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (![version isEqualToString:@"12.24.1"]) return;

    if (BHTWebSessionTaskMethodHasObjectShape(@selector(dataTaskWithRequest:delegate:), 2)) {
        %init(BHTWebSessionDelegateRequestHooks);
    }
    if (BHTWebSessionTaskMethodHasObjectShape(@selector(dataTaskWithRequest:delegate:delegateQueue:), 3)) {
        %init(BHTWebSessionDelegateQueueRequestHooks);
    }
    if (BHTWebSessionTaskMethodHasObjectShape(@selector(uploadTaskWithStreamedRequest:), 1)) {
        %init(BHTWebSessionStreamedRequestHooks);
    }

    if (BHTWebSessionTaskMethodHasObjectShape(
            @selector(dataTaskWithRequest:), 1)) {
        %init(BHTWebSessionDataRequestHook);
    }
    if (BHTWebSessionTaskMethodHasObjectShape(
            @selector(dataTaskWithRequest:completionHandler:), 2)) {
        %init(BHTWebSessionDataRequestCompletionHook);
    }
    if (BHTWebSessionTaskMethodHasObjectShape(
            @selector(uploadTaskWithRequest:fromData:), 2)) {
        %init(BHTWebSessionUploadDataHook);
    }
    if (BHTWebSessionTaskMethodHasObjectShape(
            @selector(uploadTaskWithRequest:fromData:completionHandler:),
            3)) {
        %init(BHTWebSessionUploadDataCompletionHook);
    }
    if (BHTWebSessionTaskMethodHasObjectShape(
            @selector(uploadTaskWithRequest:fromFile:), 2)) {
        %init(BHTWebSessionUploadFileHook);
    }
    if (BHTWebSessionTaskMethodHasObjectShape(
            @selector(uploadTaskWithRequest:fromFile:completionHandler:),
            3)) {
        %init(BHTWebSessionUploadFileCompletionHook);
    }
    if (BHTWebSessionTaskMethodHasObjectShape(
            @selector(downloadTaskWithRequest:), 1)) {
        %init(BHTWebSessionDownloadRequestHook);
    }
    if (BHTWebSessionTaskMethodHasObjectShape(
            @selector(downloadTaskWithRequest:completionHandler:), 2)) {
        %init(BHTWebSessionDownloadRequestCompletionHook);
    }
}
