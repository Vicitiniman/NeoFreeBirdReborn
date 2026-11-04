#import "HookHelpers.h"
#import "Login/BHTSecureWebSession.h"
#import "Login/BHTWebSessionSecurity.h"

static char kBHTNativeWebAccount;
static char kBHTNativeWebRoot;
static char kBHTNativeWebState;

@interface BHTNativeWebSessionState : NSObject
@property(nonatomic, copy) NSDictionary* session;
@property(nonatomic, strong) NSURL* rootURL;
@property(nonatomic) BOOL ready;
@property(nonatomic, weak) WKWebView* pendingWebView;
@property(nonatomic, strong) NSURLRequest* pendingRequest;
@end
@implementation BHTNativeWebSessionState
@end

static NSDictionary* BHTSessionForNativeWebAccount(id account) {
    if (!BHTSecureWebSessionOwnsNativeAccount(account)) return nil;
    NSDictionary* session = BHTSecureWebSessionCopyAccountSession(BHTWebSessionNativeAccountUserID(account));
    return [session[@"needsSignIn"] boolValue] ? nil : session;
}

static id BHTConfigureNativeWebSession(id controller, id configuration) {
    if (![configuration isKindOfClass:WKWebViewConfiguration.class]) return configuration;
    uint64_t userID = [objc_getAssociatedObject(controller, &kBHTNativeWebAccount) unsignedLongLongValue];
    if (!userID) {
        SEL getter = NSSelectorFromString(@"account");
        id account = [controller respondsToSelector:getter] ? ((id (*)(id, SEL))objc_msgSend)(controller, getter) : nil;
        userID = [BHTSessionForNativeWebAccount(account)[@"userID"] unsignedLongLongValue];
    }
    NSDictionary* session = BHTSecureWebSessionCopyAccountSession(userID);
    if (!session || [session[@"needsSignIn"] boolValue]) return configuration;
    WKWebViewConfiguration* config = configuration;
    BHTNativeWebSessionState* existing = objc_getAssociatedObject(config.websiteDataStore, &kBHTNativeWebState);
    if ([existing.session[@"userID"] unsignedLongLongValue] == userID && [existing.session[@"auth"] isEqual:session[@"auth"]]) return config;
    WKWebsiteDataStore* store = WKWebsiteDataStore.nonPersistentDataStore;
    config.websiteDataStore = store;
    BHTNativeWebSessionState* state = [BHTNativeWebSessionState new];
    state.session = session; state.rootURL = objc_getAssociatedObject(controller, &kBHTNativeWebRoot);
    objc_setAssociatedObject(store, &kBHTNativeWebState, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSDictionary* pairs = @{@"auth_token":session[@"auth"], @"ct0":session[@"csrf"],
        @"twid":[NSString stringWithFormat:@"u=%@",session[@"userID"]]};
    dispatch_group_t group = dispatch_group_create();
    for (NSString* domain in @[@".x.com", @".twitter.com"]) {
        for (NSString* name in pairs) {
            NSHTTPCookie* cookie = [NSHTTPCookie cookieWithProperties:@{
                NSHTTPCookieName:name, NSHTTPCookieValue:pairs[name], NSHTTPCookieDomain:domain,
                NSHTTPCookiePath:@"/", NSHTTPCookieSecure:@"TRUE"}];
            if (!cookie) continue;
            dispatch_group_enter(group);
            [store.httpCookieStore setCookie:cookie completionHandler:^{ dispatch_group_leave(group); }];
        }
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        state.ready = YES;
        WKWebView* webView = state.pendingWebView;
        NSURLRequest* request = state.pendingRequest;
        state.pendingRequest = nil; state.pendingWebView = nil;
        if (webView && request) [webView loadRequest:request];
    });
    return config;
}

%group BHTNativeWebSessionControllerHooks
%hook T1WebViewController
- (id)initWithRootURL:(NSURL*)rootURL account:(id)account shouldAuthenticate:(BOOL)authenticate
 shouldPresentAsNativePage:(BOOL)native sourceStatus:(id)status scribeComponent:(id)component scribeParameters:(id)parameters {
    if (BHTWebSessionURLIsAllowed(rootURL) && BHTSessionForNativeWebAccount(account)) {
        return %orig(rootURL, account, NO, native, status, component, parameters);
    }
    return %orig;
}
- (void)_t1_sharedInitWithRootURL:(NSURL*)rootURL account:(id)account sourceStatus:(id)status
 scribeComponent:(id)component scribeParameters:(id)parameters {
    %orig;
    NSDictionary* session = BHTWebSessionURLIsAllowed(rootURL) ? BHTSessionForNativeWebAccount(account) : nil;
    if (session) {
        objc_setAssociatedObject(self, &kBHTNativeWebAccount, session[@"userID"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, &kBHTNativeWebRoot, rootURL, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
- (id)updateConfiguration:(id)configuration {
    id result = %orig;
    BHTConfigureNativeWebSession(self, result ?: configuration);
    return result;
}
%end
%end

%group BHTNativeWebSessionPreloadedHooks
%hook _TtC14T1TwitterSwift26PreloadedWebviewController
- (id)updateConfiguration:(id)configuration {
    id result = %orig;
    BHTConfigureNativeWebSession(self, result ?: configuration);
    return result;
}
%end
%end

%group BHTNativeWebSessionLoadHook
%hook WKWebView
- (WKNavigation*)loadRequest:(NSURLRequest*)request {
    BHTNativeWebSessionState* state = objc_getAssociatedObject(self.configuration.websiteDataStore, &kBHTNativeWebState);
    if (!state) return %orig;
    if (!state.ready) {
        state.pendingWebView = self; state.pendingRequest = request;
        return nil;
    }
    NSURL* target = nil;
    if (BHTWebSessionURLIsAllowed(request.URL) && [request.URL.path containsString:@"/account/authenticate_web_view"]) {
        NSURLComponents* parts = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem* item in parts.queryItems) {
            if (![item.name isEqualToString:@"redirect_url"] || !item.value.length) continue;
            NSURL* candidate = [NSURL URLWithString:item.value];
            if (BHTWebSessionURLIsAllowed(candidate)) target = candidate;
        }
        if (!target && BHTWebSessionURLIsAllowed(state.rootURL)) target = state.rootURL;
    }
    if (target) {
        NSMutableURLRequest* direct = [request mutableCopy]; direct.URL = target;
        direct.HTTPMethod = @"GET"; direct.HTTPBody = nil;
        [direct setValue:nil forHTTPHeaderField:@"Authorization"];
        return %orig(direct);
    }
    return %orig;
}
%end
%end

%group BHTNativeWebSessionCookieRefreshHook
%hook T1BaseWebViewController
- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation {
    %orig;
    BHTNativeWebSessionState* state = objc_getAssociatedObject(webView.configuration.websiteDataStore, &kBHTNativeWebState);
    if (!state || !BHTWebSessionURLIsAllowed(webView.URL)) return;
    NSDictionary* captured = state.session;
    [webView.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray* cookies) {
        BHTSecureWebSessionSaveCookiesForAccount([captured[@"userID"] unsignedLongLongValue], captured[@"auth"], cookies);
        NSDictionary* latest = BHTSecureWebSessionCopyAccountSession([captured[@"userID"] unsignedLongLongValue]);
        if (latest) state.session = latest;
    }];
}
%end
%end

%ctor {
    if (![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"12.24.1"]) return;
    Class controller = NSClassFromString(@"T1WebViewController");
    if (class_getInstanceMethod(controller, @selector(updateConfiguration:)) &&
        class_getInstanceMethod(controller, @selector(_t1_sharedInitWithRootURL:account:sourceStatus:scribeComponent:scribeParameters:)) &&
        class_getInstanceMethod(controller, @selector(initWithRootURL:account:shouldAuthenticate:shouldPresentAsNativePage:sourceStatus:scribeComponent:scribeParameters:))) {
        %init(BHTNativeWebSessionControllerHooks);
        %init(BHTNativeWebSessionLoadHook);
    }
    Class preloaded = NSClassFromString(@"_TtC14T1TwitterSwift26PreloadedWebviewController");
    if (class_getInstanceMethod(preloaded, @selector(updateConfiguration:))) %init(BHTNativeWebSessionPreloadedHooks);
    Class base = NSClassFromString(@"T1BaseWebViewController");
    if (class_getInstanceMethod(base, @selector(webView:didFinishNavigation:))) %init(BHTNativeWebSessionCookieRefreshHook);
}
