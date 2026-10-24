#import "Login/BHTWebSessionRequests.h"
#import "Login/BHTSecureWebSession.h"
#import "Login/BHTWebSessionSecurity.h"
#import "Core/BHTBundle.h"
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static char kBHTResponseContext;
const void* const BHTWebSessionResponseContextKey = &kBHTResponseContext;
// Public client identifiers shipped by X; neither is an account credential.
static NSString* const BHTReadBearer = @"Bearer AAAAAAAAAAAAAAAAAAAAAAj4AQAAAAAAPraK64zCZ9CSzdLesbE7LB%2Bw4uE%3DVJQREvQNCZJNiz3rHO7lOXlkVOQkzzdsgu6wWgcazdMUaGoUGm";

static NSCondition* BHTRequestCondition(void) {
    static NSCondition* lock; static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSCondition new]; }); return lock;
}
static NSMutableDictionary* BHTRequestTokens(void) {
    static NSMutableDictionary* values; static dispatch_once_t once;
    dispatch_once(&once, ^{ values = [NSMutableDictionary dictionary]; }); return values;
}
static NSMutableDictionary* BHTPendingTokenPaths(void) {
    static NSMutableDictionary* values; static dispatch_once_t once;
    dispatch_once(&once, ^{ values = [NSMutableDictionary dictionary]; }); return values;
}
static NSString* BHTTokenKey(NSDictionary* session, NSString* method, NSString* path) {
    return [NSString stringWithFormat:@"%@ %@ %@", session[@"userID"], method, path];
}

@interface BHTSessionRequestHelper : NSObject <WKNavigationDelegate>
@property(nonatomic, strong) WKWebView* webView;
@property(nonatomic, copy) NSDictionary* session;
@property(nonatomic) BOOL ready;
- (void)mintMethod:(NSString*)method path:(NSString*)path key:(NSString*)key;
@end
static BHTSessionRequestHelper* BHTCurrentRequestHelper;

@implementation BHTSessionRequestHelper
- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)action
 decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    handler(BHTWebSessionURLIsAllowed(action.request.URL) ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation {
    NSString* path = webView.URL.path;
    if ([path isEqualToString:@"/login"] || [path hasPrefix:@"/i/flow/login"]) {
        BHTSecureWebSessionNeedsSignIn([self.session[@"userID"] unsignedLongLongValue], self.session[@"auth"]);
        return;
    }
    NSURL* scriptURL = [[BHTBundle sharedBundle] pathForFile:@"BHTSessionTransaction.js"];
    NSString* script = scriptURL ? [NSString stringWithContentsOfURL:scriptURL encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!script.length) return;
    __weak typeof(self) weakSelf = self;
    [webView evaluateJavaScript:script completionHandler:^(__unused id value, NSError* error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || error) return;
        strongSelf.ready = YES;
        [BHTRequestCondition() lock];
        NSDictionary* pending = [BHTPendingTokenPaths() copy];
        [BHTRequestCondition() broadcast];
        [BHTRequestCondition() unlock];
        for (NSString* key in pending) {
            NSDictionary* job = pending[key];
            if ([job[@"userID"] isEqual:strongSelf.session[@"userID"]]) {
                [strongSelf mintMethod:job[@"method"] path:job[@"path"] key:key];
            }
        }
    }];
}
- (void)mintMethod:(NSString*)method path:(NSString*)path key:(NSString*)key {
    if (!self.ready) return;
    [BHTRequestCondition() lock];
    NSMutableDictionary* job = [BHTPendingTokenPaths()[key] mutableCopy];
    if (!job || [job[@"running"] boolValue]) { [BHTRequestCondition() unlock]; return; }
    job[@"running"] = @YES; BHTPendingTokenPaths()[key] = job;
    [BHTRequestCondition() unlock];
    __weak typeof(self) weakSelf = self;
    [self.webView callAsyncJavaScript:@"return await window.__bhtTransactionId(path, method);"
        arguments:@{@"path":path, @"method":method} inFrame:nil inContentWorld:WKContentWorld.pageWorld
        completionHandler:^(id value, NSError* error) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSDictionary* current = BHTSecureWebSessionCopyAccountSession([strongSelf.session[@"userID"] unsignedLongLongValue]);
            [BHTRequestCondition() lock];
            if (!error && BHTWebSessionTransactionValueIsValid(value) &&
                [current[@"auth"] isEqual:strongSelf.session[@"auth"]]) {
                BHTRequestTokens()[key] = @{@"value":value, @"auth":strongSelf.session[@"auth"], @"date":NSDate.date};
            }
            [BHTPendingTokenPaths() removeObjectForKey:key];
            [BHTRequestCondition() broadcast]; [BHTRequestCondition() unlock];
        }];
}
@end

static void BHTStartRequestHelper(NSDictionary* session) {
    if (![NSThread isMainThread]) return;
    if ([BHTCurrentRequestHelper.session[@"userID"] isEqual:session[@"userID"]] &&
        [BHTCurrentRequestHelper.session[@"auth"] isEqual:session[@"auth"]]) return;
    [BHTCurrentRequestHelper.webView stopLoading];
    BHTCurrentRequestHelper.webView.navigationDelegate = nil;
    [BHTCurrentRequestHelper.webView removeFromSuperview];
    BHTSessionRequestHelper* helper = [BHTSessionRequestHelper new];
    helper.session = session;
    WKWebViewConfiguration* config = [WKWebViewConfiguration new];
    config.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
    config.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
    helper.webView = [[WKWebView alloc] initWithFrame:CGRectMake(-3000, 0, 390, 844) configuration:config];
    helper.webView.navigationDelegate = helper;
    helper.webView.userInteractionEnabled = NO;
    helper.webView.alpha = 0.01;
    if (@available(iOS 16.4, *)) helper.webView.inspectable = NO;
    BHTCurrentRequestHelper = helper;
    UIWindow* window = nil;
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow* candidate in ((UIWindowScene*)scene).windows) if (candidate.isKeyWindow) { window = candidate; break; }
    }
    [window addSubview:helper.webView];
    dispatch_group_t group = dispatch_group_create();
    NSDictionary* pairs = @{@"auth_token":session[@"auth"], @"ct0":session[@"csrf"],
        @"twid":[NSString stringWithFormat:@"u=%@",session[@"userID"]]};
    for (NSString* name in pairs) {
        NSHTTPCookie* cookie = [NSHTTPCookie cookieWithProperties:@{
            NSHTTPCookieName:name, NSHTTPCookieValue:pairs[name], NSHTTPCookieDomain:@".x.com",
            NSHTTPCookiePath:@"/", NSHTTPCookieSecure:@"TRUE"}];
        if (!cookie) continue;
        dispatch_group_enter(group);
        [config.websiteDataStore.httpCookieStore setCookie:cookie completionHandler:^{ dispatch_group_leave(group); }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (BHTCurrentRequestHelper != helper) return;
        [helper.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://x.com/settings/account"]]];
    });
}

void BHTPrepareWebSessionRequests(NSDictionary* session) {
    NSDictionary* validated = BHTWebSessionValidatedSession(session);
    if (!validated || [validated[@"needsSignIn"] boolValue]) return;
    dispatch_async(dispatch_get_main_queue(), ^{ BHTStartRequestHelper(validated); });
}

void BHTForgetWebSessionRequests(uint64_t userID) {
    NSString* prefix = [NSString stringWithFormat:@"%llu ",(unsigned long long)userID];
    [BHTRequestCondition() lock];
    for (NSString* key in [BHTRequestTokens().allKeys copy]) if ([key hasPrefix:prefix]) [BHTRequestTokens() removeObjectForKey:key];
    for (NSString* key in [BHTPendingTokenPaths().allKeys copy]) if ([key hasPrefix:prefix]) [BHTPendingTokenPaths() removeObjectForKey:key];
    [BHTRequestCondition() broadcast]; [BHTRequestCondition() unlock];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([BHTCurrentRequestHelper.session[@"userID"] unsignedLongLongValue] != userID) return;
        [BHTCurrentRequestHelper.webView stopLoading];
        BHTCurrentRequestHelper.webView.navigationDelegate = nil;
        [BHTCurrentRequestHelper.webView removeFromSuperview];
        BHTCurrentRequestHelper = nil;
    });
}

static NSString* BHTTransactionForRequest(NSURLRequest* request, NSDictionary* session) {
    NSString* method = request.HTTPMethod.uppercaseString ?: @"POST";
    NSString* path = request.URL.path;
    NSString* key = BHTTokenKey(session, method, path);
    NSCondition* lock = BHTRequestCondition();
    [lock lock];
    NSDictionary* cached = BHTRequestTokens()[key];
    NSString* token = [cached[@"auth"] isEqual:session[@"auth"]] &&
        [cached[@"date"] timeIntervalSinceNow] > -90 ? cached[@"value"] : nil;
    [BHTRequestTokens() removeObjectForKey:key];
    if (BHTPendingTokenPaths().count < 32 && !BHTPendingTokenPaths()[key]) {
        BHTPendingTokenPaths()[key] = @{@"userID":session[@"userID"], @"method":method, @"path":path};
    }
    [lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{
        BHTStartRequestHelper(session);
        [BHTCurrentRequestHelper mintMethod:method path:path key:key];
    });
    // Request constructors sometimes run on the main thread. Never stop UI
    // scrolling or sign-in there; a cold background request may wait briefly
    // while WebKit prepares its first token. Consuming a token prewarms the next.
    if (!token && !NSThread.isMainThread) {
        [lock lock];
        NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (!BHTRequestTokens()[key] && [deadline timeIntervalSinceNow] > 0) [lock waitUntilDate:deadline];
        cached = BHTRequestTokens()[key];
        if ([cached[@"auth"] isEqual:session[@"auth"]]) token = cached[@"value"];
        [BHTRequestTokens() removeObjectForKey:key]; [lock unlock];
    }
    return token;
}

NSURLRequest* BHTWebSessionRequestForSession(NSURLRequest* request, NSDictionary* session) {
    if (!BHTWebSessionURLIsAllowed(request.URL) || !BHTWebSessionValidatedSession(session) ||
        [session[@"needsSignIn"] boolValue]) return request;
    NSString* transaction = nil;
    if (BHTWebSessionRequestNeedsWebRoute(request)) {
        NSURL* URL = BHTWebSessionWebEquivalentURL(request.URL);
        if (!URL) return request;
        NSMutableURLRequest* intent = [request mutableCopy]; intent.URL = URL;
        transaction = BHTTransactionForRequest(intent, session);
    }
    NSURLRequest* immutable = BHTWebSessionBuildAuthenticatedRequest(request, session, transaction);
    if (immutable == request) return request;
    objc_setAssociatedObject(immutable, BHTWebSessionResponseContextKey,
        @{@"userID":session[@"userID"], @"auth":session[@"auth"]}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return immutable;
}

@interface BHTSessionRefreshDelegate : NSObject <NSURLSessionTaskDelegate>
@property(nonatomic, copy) NSDictionary* session;
@end
@implementation BHTSessionRefreshDelegate
- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task
 willPerformHTTPRedirection:(NSHTTPURLResponse*)response newRequest:(NSURLRequest*)request
 completionHandler:(void (^)(NSURLRequest*))completion {
    NSDictionary* updated = BHTWebSessionUpdatedSessionFromResponse(self.session, response);
    if (updated) self.session = updated;
    if (!BHTWebSessionURLIsAllowed(request.URL)) { completion(nil); return; }
    NSMutableURLRequest* next = [request mutableCopy];
    next.HTTPShouldHandleCookies = NO;
    [next setValue:BHTWebSessionCookieHeader(nil, self.session[@"auth"], self.session[@"csrf"],
        [self.session[@"userID"] unsignedLongLongValue]) forHTTPHeaderField:@"Cookie"];
    completion(next);
}
@end

void BHTRefreshWebSessionCookies(NSDictionary* session, void (^completion)(NSDictionary*)) {
    if (!session) { if (completion) completion(nil); return; }
    static NSMutableDictionary* lastAttempt; static dispatch_once_t once;
    dispatch_once(&once, ^{ lastAttempt = [NSMutableDictionary dictionary]; });
    @synchronized(lastAttempt) {
        NSDate* last = lastAttempt[session[@"userID"]];
        if (last && [last timeIntervalSinceNow] > -30) { if (completion) completion(nil); return; }
        lastAttempt[session[@"userID"]] = NSDate.date;
    }
    BHTSessionRefreshDelegate* delegate = [BHTSessionRefreshDelegate new]; delegate.session = session;
    NSURLSessionConfiguration* config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPCookieStorage = nil; config.HTTPShouldSetCookies = NO; config.URLCache = nil;
    NSURLSession* connection = [NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:nil];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://x.com/"]];
    request.timeoutInterval = 12; request.HTTPShouldHandleCookies = NO;
    [request setValue:[@"auth_token=" stringByAppendingString:session[@"auth"]] forHTTPHeaderField:@"Cookie"];
    [[connection dataTaskWithRequest:request completionHandler:^(__unused NSData* data, NSURLResponse* response, NSError* error) {
        NSDictionary* updated = !error ? BHTWebSessionUpdatedSessionFromResponse(delegate.session, (id)response) : nil;
        if (!error && [response isKindOfClass:NSHTTPURLResponse.class] &&
            [(NSHTTPURLResponse*)response statusCode] >= 200 && [(NSHTTPURLResponse*)response statusCode] < 400) {
            NSMutableDictionary* refreshed = [(updated ?: delegate.session) mutableCopy];
            refreshed[@"lastRefresh"] = NSDate.date; updated = refreshed;
        }
        if (completion) completion(updated);
        [connection finishTasksAndInvalidate];
    }] resume];
}

void BHTResolveWebSessionIdentity(NSDictionary* session, void (^completion)(NSString*)) {
    NSURLSessionConfiguration* config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    config.HTTPCookieStorage = nil; config.HTTPShouldSetCookies = NO; config.URLCache = nil;
    BHTSessionRefreshDelegate* delegate = [BHTSessionRefreshDelegate new]; delegate.session = session;
    NSURLSession* connection = [NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:nil];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://x.com/i/api/1.1/account/verify_credentials.json?include_entities=false&skip_status=true"]];
    request.timeoutInterval = 12; request.HTTPShouldHandleCookies = NO;
    [request setValue:BHTReadBearer forHTTPHeaderField:@"Authorization"];
    [request setValue:session[@"csrf"] forHTTPHeaderField:@"x-csrf-token"];
    [request setValue:@"OAuth2Session" forHTTPHeaderField:@"x-twitter-auth-type"];
    [request setValue:BHTWebSessionCookieHeader(nil, session[@"auth"], session[@"csrf"],
        [session[@"userID"] unsignedLongLongValue]) forHTTPHeaderField:@"Cookie"];
    [[connection dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
        NSString* handle = nil;
        if (!error && data.length <= 262144 && [response isKindOfClass:NSHTTPURLResponse.class] &&
            [(NSHTTPURLResponse*)response statusCode] == 200 && BHTWebSessionURLIsAllowed(response.URL)) {
            id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([value isKindOfClass:NSDictionary.class]) {
                id uid = value[@"id_str"] ?: [value[@"id"] description];
                if (BHTWebSessionUserIDFromTWID(uid) == [session[@"userID"] unsignedLongLongValue]) {
                    handle = BHTWebSessionNormalizedHandle(value[@"screen_name"]);
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(handle); });
        [connection finishTasksAndInvalidate];
    }] resume];
}
