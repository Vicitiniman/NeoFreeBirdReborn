#import "Login/BHTSecureWebSession.h"

#import "Core/BHTBundle.h"
#import "Login/BHTCompatibilityLogin.h"
#import "Login/BHTWebSessionSecurity.h"
#import "Login/BHTWebSessionVault.h"
#import "Login/BHTWebSessionRequests.h"

#import <Security/Security.h>
#import <WebKit/WebKit.h>
#import <objc/message.h>
#import <stdatomic.h>

static NSString* const BHTWebSessionTargetVersion = @"12.24.1";

typedef NS_ENUM(NSUInteger, BHTWebSessionEvent) {
    BHTWebSessionEventPresented = 0,
    BHTWebSessionEventConfirmationTapped,
    BHTWebSessionEventCookieSetComplete,
    BHTWebSessionEventCookieSetIncomplete,
    BHTWebSessionEventHandleDetected,
    BHTWebSessionEventHandleEntered,
    BHTWebSessionEventKeychainSaved,
    BHTWebSessionEventKeychainSaveFailed,
    BHTWebSessionEventAccountInstallStarted,
    BHTWebSessionEventAccountInstallFailed,
    BHTWebSessionEventRequestEligible,
    BHTWebSessionEventRequestAuthenticated,
    BHTWebSessionEventRevoked,
    BHTWebSessionEventRestored,
    BHTWebSessionEventRefreshSaved,
    BHTWebSessionEventKeychainRetry,
    BHTWebSessionEventCount,
};

static atomic_ulong BHTWebSessionCounters[BHTWebSessionEventCount];
static __weak UIViewController* BHTWebSessionPresentedController;
static UIViewController* BHTWebSessionActiveController(void);

static void BHTWebSessionRecord(BHTWebSessionEvent event) {
    if (event < BHTWebSessionEventCount) {
        atomic_fetch_add_explicit(
            &BHTWebSessionCounters[event], 1,
            memory_order_relaxed);
    }
}

static BHTWebSessionVault* BHTSharedSessionVault(void) {
    static BHTWebSessionVault* vault;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ vault = [BHTWebSessionVault new]; });
    return vault;
}

static NSString* BHTWebSessionLocalized(NSString* key) {
    return [[BHTBundle sharedBundle] localizedStringForKey:key];
}

static BOOL BHTWebSessionVersionIsSupported(void) {
    NSString* version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return [version isEqualToString:BHTWebSessionTargetVersion];
}

static NSDictionary<NSString*, id>*
BHTWebSessionCopySession(void) {
    NSArray* sessions = BHTSharedSessionVault().sessions;
    return [[sessions sortedArrayUsingComparator:^NSComparisonResult(NSDictionary* a, NSDictionary* b) {
        NSDate* first = a[@"lastUsed"] ?: NSDate.distantPast;
        NSDate* second = b[@"lastUsed"] ?: NSDate.distantPast;
        return [second compare:first];
    }] firstObject];
}

static BOOL BHTWebSessionSaveSession(NSDictionary* value) {
    return [BHTSharedSessionVault() saveSession:value];
}

BOOL BHTSecureWebSessionSignInIsAvailable(void) {
    return BHTWebSessionVersionIsSupported() &&
           NSClassFromString(@"WKWebView") != Nil &&
           BHTCompatibilityWebSessionAccountRuntimeIsAvailable();
}

BOOL BHTSecureWebSessionHasActiveSession(void) {
    for (NSDictionary* session in BHTSharedSessionVault().sessions) {
        if (![session[@"needsSignIn"] boolValue]) return YES;
    }
    return NO;
}

NSURLRequest* BHTSecureWebSessionAuthenticatedRequest(
    NSURLRequest* request) {
    if (![request isKindOfClass:NSURLRequest.class] ||
        !BHTWebSessionURLIsAllowed(request.URL)) {
        return request;
    }
    uint64_t owner = BHTWebSessionRequestOwner(request);
    if (!owner) return request;
    NSDictionary* session = BHTSecureWebSessionCopyAccountSession(owner);
    if (!session || [session[@"needsSignIn"] boolValue]) return request;
    BHTWebSessionRecord(BHTWebSessionEventRequestEligible);
    NSURLRequest* result = BHTWebSessionRequestForSession(request, session);
    if (result != request) BHTWebSessionRecord(BHTWebSessionEventRequestAuthenticated);
    return result;
}

BOOL BHTSecureWebSessionOwnsNativeAccount(id account) {
    if (!BHTWebSessionVersionIsSupported()) return NO;
    uint64_t userID = BHTWebSessionNativeAccountUserID(account);
    if (!userID) return NO;
    if ([BHTSharedSessionVault() isRemovedUserID:userID]) return NO;
    BOOL placeholder = BHTWebSessionAccountUsesPlaceholder(account);
    SEL tokenSelector = NSSelectorFromString(@"oAuthToken");
    id token = [account respondsToSelector:tokenSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(account, tokenSelector) : nil;
    if (![token isKindOfClass:NSString.class]) token = nil;
    if (!placeholder && [token length] > 0) return NO;
    NSDictionary* session = BHTSecureWebSessionCopyAccountSession(userID);
    if ([session[@"needsSignIn"] boolValue]) return NO;
    return session != nil ||
        (placeholder && BHTSharedSessionVault().readUnavailable);
}

NSDictionary* BHTSecureWebSessionCopyAccountSession(uint64_t userID) {
    return userID ? [BHTSharedSessionVault() sessionForUserID:userID] : nil;
}

void BHTSecureWebSessionRestoreSavedAccounts(void) {
    if (!BHTWebSessionVersionIsSupported()) return;
    [BHTSharedSessionVault() retryAfterUnlock];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSDictionary* session in BHTSharedSessionVault().sessions) {
            if ([session[@"needsSignIn"] boolValue]) continue;
            if (BHTCompatibilityRestoreWebSessionAccount(session[@"screenName"],
                [session[@"userID"] unsignedLongLongValue])) {
                BHTWebSessionRecord(BHTWebSessionEventRestored);
            }
        }
        if (BHTSharedSessionVault().readUnavailable) BHTWebSessionRecord(BHTWebSessionEventKeychainRetry);
        Class hostClass = NSClassFromString(@"T1HostViewController");
        SEL sharedSelector = NSSelectorFromString(@"sharedHostViewController");
        id host = [hostClass respondsToSelector:sharedSelector] ? ((id (*)(id, SEL))objc_msgSend)(hostClass, sharedSelector) : nil;
        SEL currentSelector = NSSelectorFromString(@"currentAccount");
        id account = [host respondsToSelector:currentSelector] ? ((id (*)(id, SEL))objc_msgSend)(host, currentSelector) : nil;
        if (account) BHTSecureWebSessionDidSelectAccount(account);
    });
}

void BHTSecureWebSessionDidSelectAccount(id account) {
    uint64_t userID = BHTWebSessionNativeAccountUserID(account);
    NSDictionary* session = BHTSecureWebSessionCopyAccountSession(userID);
    if (!session || !BHTSecureWebSessionOwnsNativeAccount(account)) return;
    NSMutableDictionary* selected = [session mutableCopy];
    selected[@"lastUsed"] = NSDate.date;
    [BHTSharedSessionVault() saveSession:selected];
    BHTPrepareWebSessionRequests(selected);
    NSDate* lastRefresh = session[@"lastRefresh"];
    if (!lastRefresh || [lastRefresh timeIntervalSinceNow] < -300) {
        BHTRefreshWebSessionCookies(selected, ^(NSDictionary* updated) {
            if (updated && [BHTSharedSessionVault() updateSession:updated ifAuthMatches:session[@"auth"]]) {
                BHTWebSessionRecord(BHTWebSessionEventRefreshSaved);
            }
        });
    }
}

BOOL BHTSecureWebSessionForgetAccount(id account) {
    uint64_t userID = BHTWebSessionNativeAccountUserID(account);
    if (!userID || !BHTSecureWebSessionCopyAccountSession(userID)) return YES;
    if (![BHTSharedSessionVault() removeUserID:userID]) return NO;
    BHTForgetWebSessionRequests(userID);
    BHTWebSessionRecord(BHTWebSessionEventRevoked);
    return YES;
}

void BHTSecureWebSessionObserveResponse(NSURLRequest* request, NSURLResponse* response) {
    if (![response isKindOfClass:NSHTTPURLResponse.class] || !BHTWebSessionURLIsAllowed(response.URL)) return;
    NSDictionary* context = objc_getAssociatedObject(request, BHTWebSessionResponseContextKey);
    if (!context) return;
    NSDictionary* current = BHTSecureWebSessionCopyAccountSession([context[@"userID"] unsignedLongLongValue]);
    if (![current[@"auth"] isEqual:context[@"auth"]]) return;
    NSDictionary* updated = BHTWebSessionUpdatedSessionFromResponse(current, (id)response);
    if (updated && [BHTSharedSessionVault() updateSession:updated ifAuthMatches:context[@"auth"]]) {
        BHTWebSessionRecord(BHTWebSessionEventRefreshSaved);
    }
    // A denied endpoint or a transport failure is not proof that the whole
    // account expired. Refresh only this account's cookies; never delete it.
    NSInteger code = [(NSHTTPURLResponse*)response statusCode];
    if (code == 401 || code == 403) {
        BHTRefreshWebSessionCookies(current, ^(NSDictionary* refreshed) {
            if (refreshed) [BHTSharedSessionVault() updateSession:refreshed ifAuthMatches:current[@"auth"]];
        });
    }
}

void BHTSecureWebSessionNeedsSignIn(uint64_t userID, NSString* expectedAuth) {
    NSDictionary* current = BHTSecureWebSessionCopyAccountSession(userID);
    if (![current[@"auth"] isEqual:expectedAuth]) return;
    NSMutableDictionary* updated = [current mutableCopy]; updated[@"needsSignIn"] = @YES;
    if (![BHTSharedSessionVault() updateSession:updated ifAuthMatches:expectedAuth]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (BHTWebSessionPresentedController || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
        Class hostClass = NSClassFromString(@"T1HostViewController");
        SEL shared = NSSelectorFromString(@"sharedHostViewController");
        id host = [hostClass respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(hostClass, shared) : nil;
        SEL selected = NSSelectorFromString(@"currentAccount");
        id account = [host respondsToSelector:selected] ? ((id (*)(id, SEL))objc_msgSend)(host, selected) : nil;
        UIViewController* source = BHTWebSessionActiveController();
        if (!source || BHTWebSessionNativeAccountUserID(account) != userID) return;
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_TITLE")
            message:BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_EXPIRED") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_CONTINUE") style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction* action) { BHTPresentSecureWebSessionSignIn(source, nil); }]];
        [source presentViewController:alert animated:YES completion:nil];
    });
}

static char kBHTWebSessionTaskWatcher;
@interface BHTWebSessionTaskWatcher : NSObject
@property(nonatomic, weak) NSURLSessionTask* task;
@property(nonatomic, strong) NSURLRequest* request;
@property(nonatomic) BOOL finished;
@end
@implementation BHTWebSessionTaskWatcher
- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object
                       change:(NSDictionary*)change context:(void*)context {
    if (context != &kBHTWebSessionTaskWatcher) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context]; return;
    }
    NSURLSessionTask* task = object;
    if (task.state != NSURLSessionTaskStateCompleted) return;
    @synchronized(self) { if (self.finished) return; self.finished = YES; }
    BHTWebSessionTaskWatcher* keepAlive = self;
    @try { [task removeObserver:self forKeyPath:@"state" context:&kBHTWebSessionTaskWatcher]; }
    @catch (__unused NSException* exception) {}
    BHTSecureWebSessionObserveResponse(self.request, task.response);
    objc_setAssociatedObject(task, &kBHTWebSessionTaskWatcher, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    (void)keepAlive;
}
@end

void BHTSecureWebSessionWatchTask(NSURLSessionTask* task, NSURLRequest* request) {
    if (!task || !objc_getAssociatedObject(request, BHTWebSessionResponseContextKey) ||
        objc_getAssociatedObject(task, &kBHTWebSessionTaskWatcher)) return;
    BHTWebSessionTaskWatcher* watcher = [BHTWebSessionTaskWatcher new];
    watcher.task = task; watcher.request = request;
    objc_setAssociatedObject(task, &kBHTWebSessionTaskWatcher, watcher, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { [task addObserver:watcher forKeyPath:@"state" options:NSKeyValueObservingOptionNew context:&kBHTWebSessionTaskWatcher]; }
    @catch (__unused NSException* exception) { objc_setAssociatedObject(task, &kBHTWebSessionTaskWatcher, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}

static BOOL BHTWebSessionCookieDomainIsAllowed(NSString* domain) {
    NSString* host = domain.lowercaseString ?: @"";
    while ([host hasPrefix:@"."]) {
        host = [host substringFromIndex:1];
    }
    return [host isEqualToString:@"x.com"] ||
           [host hasSuffix:@".x.com"] ||
           [host isEqualToString:@"twitter.com"] ||
           [host hasSuffix:@".twitter.com"];
}

static BOOL BHTWebSessionCookieIsAuthenticationCookie(
    NSHTTPCookie* cookie) {
    static NSSet<NSString*>* names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = [NSSet setWithArray:@[
            @"auth_token", @"ct0", @"twid"
        ]];
    });
    return [cookie isKindOfClass:NSHTTPCookie.class] &&
           [names containsObject:cookie.name.lowercaseString] &&
           BHTWebSessionCookieDomainIsAllowed(cookie.domain);
}

static NSString* BHTWebSessionCookieFamily(NSHTTPCookie* cookie) {
    NSString* domain = cookie.domain.lowercaseString ?: @"";
    while ([domain hasPrefix:@"."]) {
        domain = [domain substringFromIndex:1];
    }
    if ([domain isEqualToString:@"x.com"] ||
        [domain hasSuffix:@".x.com"]) {
        return @"x";
    }
    if ([domain isEqualToString:@"twitter.com"] ||
        [domain hasSuffix:@".twitter.com"]) {
        return @"twitter";
    }
    return nil;
}

static NSDictionary<NSString*, id>*
BHTWebSessionComponentsFromCookies(
    NSArray<NSHTTPCookie*>* cookies) {
    NSMutableDictionary* families = [@{
        @"x": [NSMutableDictionary dictionary],
        @"twitter": [NSMutableDictionary dictionary],
    } mutableCopy];
    for (NSHTTPCookie* cookie in cookies) {
        if (!BHTWebSessionCookieIsAuthenticationCookie(cookie)) {
            continue;
        }
        NSString* family = BHTWebSessionCookieFamily(cookie);
        if (family.length == 0) continue;
        NSMutableDictionary* values = families[family];
        if (!values) continue;
        NSString* name = cookie.name.lowercaseString;
        if ([name isEqualToString:@"auth_token"] &&
            BHTWebSessionCredentialValueIsValid(cookie.value)) {
            values[@"auth"] = cookie.value;
        } else if ([name isEqualToString:@"ct0"] &&
                   BHTWebSessionCredentialValueIsValid(cookie.value)) {
            values[@"csrf"] = cookie.value;
        } else if ([name isEqualToString:@"twid"]) {
            uint64_t userID =
                BHTWebSessionUserIDFromTWID(cookie.value);
            if (userID > 0) values[@"userID"] = @(userID);
        }
    }
    for (NSString* family in @[@"x", @"twitter"]) {
        NSDictionary* values = families[family];
        if ([values[@"auth"] length] > 0 &&
            [values[@"csrf"] length] > 0 &&
            [values[@"userID"] unsignedLongLongValue] > 0) {
            return [values copy];
        }
    }
    return nil;
}

void BHTSecureWebSessionSaveCookiesForAccount(uint64_t userID, NSString* expectedAuth, NSArray* cookies) {
    NSDictionary* values = BHTWebSessionComponentsFromCookies(cookies);
    if ([values[@"userID"] unsignedLongLongValue] != userID) return;
    NSDictionary* current = BHTSecureWebSessionCopyAccountSession(userID);
    if (![current[@"auth"] isEqual:expectedAuth]) return;
    NSMutableDictionary* updated = [current mutableCopy];
    updated[@"auth"] = values[@"auth"]; updated[@"csrf"] = values[@"csrf"];
    updated[@"lastRefresh"] = NSDate.date;
    if ([BHTSharedSessionVault() updateSession:updated ifAuthMatches:expectedAuth]) BHTWebSessionRecord(BHTWebSessionEventRefreshSaved);
}

static NSSet* BHTWebSessionCookieFamiliesForUser(NSArray* cookies, uint64_t userID, NSString* auth) {
    NSMutableSet* families = [NSMutableSet set];
    for (NSHTTPCookie* cookie in cookies) {
        BOOL matches = ([cookie.name isEqualToString:@"twid"] && BHTWebSessionUserIDFromTWID(cookie.value) == userID) ||
            ([cookie.name isEqualToString:@"auth_token"] && [cookie.value isEqual:auth]);
        if (matches && BHTWebSessionCookieIsAuthenticationCookie(cookie)) {
            NSString* family = BHTWebSessionCookieFamily(cookie);
            if (family) [families addObject:family];
        }
    }
    return families;
}

static void BHTWebSessionClearWebsiteData(uint64_t userID, NSString* auth, dispatch_block_t completion) {
    NSHTTPCookieStorage* shared = NSHTTPCookieStorage.sharedHTTPCookieStorage;
    NSSet* families = BHTWebSessionCookieFamiliesForUser(shared.cookies, userID, auth);
    for (NSHTTPCookie* cookie in shared.cookies) {
        if (BHTWebSessionCookieIsAuthenticationCookie(cookie) &&
            [families containsObject:BHTWebSessionCookieFamily(cookie)]) [shared deleteCookie:cookie];
    }
    WKWebsiteDataStore* store = WKWebsiteDataStore.defaultDataStore;
    [store.httpCookieStore getAllCookies:^(NSArray* cookies) {
        NSSet* matching = BHTWebSessionCookieFamiliesForUser(cookies, userID, auth);
        dispatch_group_t group = dispatch_group_create();
        for (NSHTTPCookie* cookie in cookies) {
            if (!BHTWebSessionCookieIsAuthenticationCookie(cookie) ||
                ![matching containsObject:BHTWebSessionCookieFamily(cookie)]) continue;
            dispatch_group_enter(group);
            [store.httpCookieStore deleteCookie:cookie completionHandler:^{ dispatch_group_leave(group); }];
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), completion ?: ^{});
    }];
}

static void BHTRevokeWebSessionForID(uint64_t userID, void (^completion)(BOOL)) {
    NSDictionary* session = BHTSecureWebSessionCopyAccountSession(userID);
    if (!session || ![BHTSharedSessionVault() removeUserID:userID]) {
        if (completion) completion(NO); return;
    }
    BHTForgetWebSessionRequests(userID);
    BOOL removed = BHTCompatibilityRemoveWebSessionAccountWithUserID(userID);
    BHTWebSessionRecord(BHTWebSessionEventRevoked);
    BHTWebSessionClearWebsiteData(userID, session[@"auth"], ^{ if (completion) completion(removed); });
}

void BHTRevokeSecureWebSession(
    void (^completion)(BOOL accountShellRemoved)) {
    BHTRevokeWebSessionForID([BHTWebSessionCopySession()[@"userID"] unsignedLongLongValue], completion);
}

static UIViewController* BHTWebSessionTopController(
    UIViewController* controller) {
    UIViewController* current = controller;
    while (current) {
        if (current.presentedViewController &&
            !current.presentedViewController.isBeingDismissed) {
            current = current.presentedViewController;
            continue;
        }
        if ([current isKindOfClass:UINavigationController.class]) {
            current = ((UINavigationController*)current)
                .visibleViewController;
            continue;
        }
        if ([current isKindOfClass:UITabBarController.class]) {
            current = ((UITabBarController*)current)
                .selectedViewController;
            continue;
        }
        break;
    }
    return current;
}

static UIViewController* BHTWebSessionActiveController(void) {
    for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState !=
            UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow* window in ((UIWindowScene*)scene).windows) {
            if (window.isKeyWindow && window.rootViewController) {
                return BHTWebSessionTopController(
                    window.rootViewController);
            }
        }
    }
    return nil;
}

static BOOL BHTWebSessionNavigationURLIsAllowed(NSURL* URL) {
    if (BHTWebSessionURLIsAllowed(URL)) return YES;
    NSURLComponents* components =
        [NSURLComponents componentsWithURL:URL
                   resolvingAgainstBaseURL:NO];
    if (![[components.scheme lowercaseString]
            isEqualToString:@"https"] ||
        components.user.length > 0 || components.password.length > 0 ||
        (components.port && components.port.unsignedIntegerValue != 443)) {
        return NO;
    }
    NSString* host = components.host.lowercaseString ?: @"";
    return [host isEqualToString:@"accounts.google.com"] ||
           [host isEqualToString:@"appleid.apple.com"];
}

@interface BHTSecureWebSessionViewController
    : UIViewController <WKNavigationDelegate, WKUIDelegate>
@property(nonatomic, strong) WKWebView* webView;
@property(nonatomic, strong) UILabel* statusLabel;
@property(nonatomic, strong) UIButton* useAccountButton;
@property(nonatomic, strong) UIActivityIndicatorView* activity;
@property(nonatomic, weak) UIViewController* addAccountController;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL rootSignIn;
@property(nonatomic) BOOL attemptedRestore;
@property(nonatomic) BOOL completed;
@property(nonatomic) BOOL pageReady;
@property(nonatomic) NSUInteger operationGeneration;
@property(nonatomic, copy) NSString* detectedHandle;
@property(nonatomic, copy) NSDictionary* savedConnection;
@property(nonatomic, strong) UIBarButtonItem* savedAccountsItem;
- (void)connectSavedSession:(NSDictionary*)session;
- (void)updateReadiness;
@end

static char kBHTSignInURLObservation;

@implementation BHTSecureWebSessionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_TITLE");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    if (!self.rootSignIn) self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc]
            initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                 target:self
                                 action:@selector(closeTapped)];
    if (BHTSharedSessionVault().sessions.count) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc]
                initWithTitle:BHTWebSessionLocalized(
                    @"SECURE_WEB_SIGN_IN_SAVED_ACCOUNTS")
                         style:UIBarButtonItemStylePlain
                        target:self
                        action:@selector(removeTapped)];
    }
    UIBarButtonItem* report = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
        target:self action:@selector(shareReport:)];
    report.accessibilityLabel = BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_REPORT");
    self.navigationItem.rightBarButtonItems = self.navigationItem.rightBarButtonItem
        ? @[self.navigationItem.rightBarButtonItem, report] : @[report];

    UILabel* privacy = [UILabel new];
    privacy.translatesAutoresizingMaskIntoConstraints = NO;
    privacy.text = BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_PRIVACY");
    privacy.font = [UIFont
        preferredFontForTextStyle:UIFontTextStyleFootnote];
    privacy.textColor = UIColor.secondaryLabelColor;
    privacy.adjustsFontForContentSizeCategory = YES;
    privacy.numberOfLines = 0;

    WKWebViewConfiguration* configuration =
        [WKWebViewConfiguration new];
    // Each new sign-in starts separately, so adding an account cannot silently
    // reuse or replace the account already open in another web view.
    configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
    self.webView = [[WKWebView alloc]
        initWithFrame:CGRectZero configuration:configuration];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;
    self.webView.allowsBackForwardNavigationGestures = YES;
    [self.webView addObserver:self forKeyPath:@"URL" options:NSKeyValueObservingOptionNew context:&kBHTSignInURLObservation];

    self.statusLabel = [UILabel new];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.text = BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_STATUS");
    self.statusLabel.font = [UIFont
        preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.adjustsFontForContentSizeCategory = YES;
    self.statusLabel.numberOfLines = 0;

    self.useAccountButton =
        [UIButton buttonWithType:UIButtonTypeSystem];
    self.useAccountButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.useAccountButton setTitle:BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_USE_ACCOUNT")
                            forState:UIControlStateNormal];
    self.useAccountButton.titleLabel.font = [UIFont
        preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.useAccountButton.backgroundColor = UIColor.systemBlueColor;
    [self.useAccountButton setTitleColor:UIColor.whiteColor
                               forState:UIControlStateNormal];
    self.useAccountButton.layer.cornerRadius = 12.0;
    [self.useAccountButton addTarget:self
                              action:@selector(useAccountTapped)
                    forControlEvents:UIControlEventTouchUpInside];

    self.activity = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activity.translatesAutoresizingMaskIntoConstraints = NO;
    self.activity.hidesWhenStopped = YES;

    [self.view addSubview:privacy];
    [self.view addSubview:self.webView];
    [self.view addSubview:self.statusLabel];
    [self.view addSubview:self.useAccountButton];
    [self.view addSubview:self.activity];
    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [privacy.topAnchor constraintEqualToAnchor:safe.topAnchor
                                          constant:10.0],
        [privacy.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor
                                              constant:14.0],
        [privacy.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor
                                               constant:-14.0],
        [self.webView.topAnchor constraintEqualToAnchor:privacy.bottomAnchor
                                               constant:10.0],
        [self.webView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.webView.bottomAnchor
                                                   constant:8.0],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor
                                                       constant:14.0],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.activity.leadingAnchor
                                                        constant:-8.0],
        [self.activity.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],
        [self.activity.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor
                                                     constant:-14.0],
        [self.useAccountButton.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor
                                                        constant:10.0],
        [self.useAccountButton.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor
                                                            constant:14.0],
        [self.useAccountButton.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor
                                                             constant:-14.0],
        [self.useAccountButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor
                                                           constant:-12.0],
        [self.useAccountButton.heightAnchor constraintEqualToConstant:48.0],
    ]];

    NSURL* URL = [NSURL URLWithString:@"https://x.com/i/flow/login"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:URL]];
    self.useAccountButton.enabled = NO;
}

- (void)dealloc {
    @try { [_webView removeObserver:self forKeyPath:@"URL" context:&kBHTSignInURLObservation]; }
    @catch (__unused NSException* exception) {}
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.rootSignIn || self.attemptedRestore) return;
    self.attemptedRestore = YES;
    NSDictionary* session = BHTWebSessionCopySession();
    if (session && ![session[@"needsSignIn"] boolValue]) {
        self.savedConnection = session;
        [self connectSavedSession:session];
    } else if (session) {
        self.statusLabel.text = BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_EXPIRED");
    }
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
    if (context != &kBHTSignInURLObservation) { [super observeValueForKeyPath:keyPath ofObject:object change:change context:context]; return; }
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateReadiness]; });
}

- (void)updateReadiness {
    if (self.busy || self.completed || !BHTWebSessionURLIsAllowed(self.webView.URL)) return;
    NSString* script = @"(() => { const a = document.querySelector('a[data-testid=\"AppTabBar_Profile_Link\"]'); if (!a) return null; const m = (a.getAttribute('href') || '').match(/^\\/([A-Za-z0-9_]{1,15})(?:\\/|$)/); return m ? m[1] : null; })()";
    __weak typeof(self) weakSelf = self;
    [self.webView evaluateJavaScript:script completionHandler:^(id value, __unused NSError* error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.busy || strongSelf.completed) return;
        strongSelf.detectedHandle = BHTWebSessionNormalizedHandle(value);
        NSString* path = strongSelf.webView.URL.path;
        strongSelf.pageReady = strongSelf.detectedHandle.length > 0 || [path isEqualToString:@"/home"];
        if (strongSelf.pageReady) {
            strongSelf.savedConnection = nil;
            strongSelf.useAccountButton.enabled = YES;
            strongSelf.statusLabel.text = BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_READY");
            NSString* title = strongSelf.detectedHandle.length ?
                [NSString stringWithFormat:BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_CONTINUE_AS"),strongSelf.detectedHandle] :
                BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_USE_ACCOUNT");
            [strongSelf.useAccountButton setTitle:title forState:UIControlStateNormal];
        } else if (!strongSelf.savedConnection) {
            strongSelf.useAccountButton.enabled = NO;
        }
    }];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed ||
        self.navigationController.isBeingDismissed) {
        BHTWebSessionPresentedController = nil;
    }
}

- (void)setBusy:(BOOL)busy message:(NSString*)message {
    self.busy = busy;
    self.webView.userInteractionEnabled = !busy;
    self.useAccountButton.enabled = !busy && (self.pageReady || self.savedConnection != nil);
    self.navigationItem.leftBarButtonItem.enabled = !busy;
    for (UIBarButtonItem* item in self.navigationItem.rightBarButtonItems) item.enabled = !busy;
    self.statusLabel.text = message ?: @"";
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    if (busy) [self.activity startAnimating];
    else [self.activity stopAnimating];
}

- (void)showErrorKey:(NSString*)key {
    [self setBusy:NO message:BHTWebSessionLocalized(key)];
    self.statusLabel.textColor = UIColor.systemRedColor;
}

- (void)closeTapped {
    if (self.busy) return;
    self.operationGeneration++;
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)shareReport:(UIBarButtonItem*)sender {
    BHTShareCompatibilitySignInReport(self, sender);
}

- (void)removeTapped {
    if (self.busy) return;
    UIAlertController* accounts = [UIAlertController alertControllerWithTitle:
        BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_SAVED_ACCOUNTS") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary* session in BHTSharedSessionVault().sessions) {
        NSString* title = [NSString stringWithFormat:@"@%@", session[@"screenName"]];
        [accounts addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction* action) {
            [weakSelf manageSavedSession:session];
        }]];
    }
    [accounts addAction:[UIAlertAction actionWithTitle:BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    accounts.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:accounts animated:YES completion:nil];
}

- (void)manageSavedSession:(NSDictionary*)session {
    if (self.busy) return;
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_REMOVE_TITLE")
                         message:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_REMOVE_DETAIL")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction
        actionWithTitle:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_CANCEL")
                  style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    if (![session[@"needsSignIn"] boolValue]) {
        [alert addAction:[UIAlertAction actionWithTitle:BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_OPEN_SAVED")
            style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction* action) { [weakSelf connectSavedSession:session]; }]];
    }
    [alert addAction:[UIAlertAction
        actionWithTitle:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_REMOVE")
                  style:UIAlertActionStyleDestructive
                handler:^(__unused UIAlertAction* action) {
        BHTSecureWebSessionViewController* strongSelf = weakSelf;
        [strongSelf setBusy:YES message:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_REMOVING")];
        BHTRevokeWebSessionForID([session[@"userID"] unsignedLongLongValue], ^(BOOL removed) {
            strongSelf.savedConnection = nil;
            [strongSelf setBusy:NO message:BHTWebSessionLocalized(
                removed
                    ? @"SECURE_WEB_SIGN_IN_REMOVED"
                    : @"SECURE_WEB_SIGN_IN_REMOVED_ACCOUNT_REMAINS")];
            NSURL* URL = [NSURL URLWithString:
                @"https://x.com/i/flow/login"];
            [strongSelf.webView loadRequest:
                [NSURLRequest requestWithURL:URL]];
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)connectSavedSession:(NSDictionary*)session {
    self.savedConnection = session;
    NSUInteger generation = ++self.operationGeneration;
    BHTWebSessionRecord(BHTWebSessionEventAccountInstallStarted);
    [self setBusy:YES message:BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_CONNECTING")];
    [self.useAccountButton setTitle:BHTWebSessionLocalized(@"SECURE_WEB_SIGN_IN_RETRY_CONNECTION") forState:UIControlStateNormal];
    BHTPrepareWebSessionRequests(session);
    __weak typeof(self) weakSelf = self;
    BOOL started = BHTCompatibilityInstallWebSessionAccount(session[@"screenName"],
        [session[@"userID"] unsignedLongLongValue], self, self.addAccountController,
        ^(BOOL success, __unused NSString* failureCategory) {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf || generation != strongSelf.operationGeneration) return;
                if (success) { strongSelf.completed = YES; strongSelf.busy = NO; return; }
                BHTWebSessionRecord(BHTWebSessionEventAccountInstallFailed);
                [strongSelf showErrorKey:@"SECURE_WEB_SIGN_IN_ACCOUNT_ERROR"];
            });
        });
    if (!started) {
        BHTWebSessionRecord(BHTWebSessionEventAccountInstallFailed);
        [self showErrorKey:@"SECURE_WEB_SIGN_IN_ACCOUNT_ERROR"];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf.busy && !strongSelf.completed && strongSelf.operationGeneration == generation) {
            strongSelf.operationGeneration++;
            [strongSelf showErrorKey:@"SECURE_WEB_SIGN_IN_CONNECT_TIMEOUT"];
        }
    });
}

- (void)finishWithComponents:(NSDictionary*)components
              screenName:(NSString*)screenName {
    if (!components) {
        BHTWebSessionRecord(BHTWebSessionEventCookieSetIncomplete);
        [self showErrorKey:@"SECURE_WEB_SIGN_IN_NOT_READY"];
        return;
    }
    BHTWebSessionRecord(BHTWebSessionEventCookieSetComplete);
    NSString* handle = BHTWebSessionNormalizedHandle(screenName);
    if (handle.length == 0) {
        [self promptForHandleWithComponents:components];
        return;
    }

    NSDictionary* session = @{
        @"version": @2,
        @"auth": components[@"auth"],
        @"csrf": components[@"csrf"],
        @"screenName": handle,
        @"userID": components[@"userID"],
        @"lastUsed": NSDate.date,
    };
    if (!BHTWebSessionSaveSession(session)) {
        BHTWebSessionRecord(BHTWebSessionEventKeychainSaveFailed);
        [self showErrorKey:@"SECURE_WEB_SIGN_IN_KEYCHAIN_ERROR"];
        return;
    }
    BHTWebSessionRecord(BHTWebSessionEventKeychainSaved);
    // A failed native UI handoff must not erase a valid, durable sign-in.
    // It can be retried here or restored after a force quit.
    [self connectSavedSession:session];
}

- (void)promptForHandleWithComponents:(NSDictionary*)components {
    [self setBusy:NO message:BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_HANDLE_REQUIRED")];
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_HANDLE_TITLE")
                         message:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_HANDLE_DETAIL")
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField* field) {
        field.placeholder = @"@username";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.textContentType = UITextContentTypeUsername;
    }];
    [alert addAction:[UIAlertAction
        actionWithTitle:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_CANCEL")
                  style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction
        actionWithTitle:BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_CONTINUE")
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction* action) {
        BHTSecureWebSessionViewController* strongSelf = weakSelf;
        NSString* handle = BHTWebSessionNormalizedHandle(
            alert.textFields.firstObject.text);
        if (handle.length == 0) {
            [strongSelf showErrorKey:
                @"SECURE_WEB_SIGN_IN_HANDLE_INVALID"];
            return;
        }
        BHTWebSessionRecord(BHTWebSessionEventHandleEntered);
        [strongSelf finishWithComponents:components screenName:handle];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)useAccountTapped {
    if (self.busy) return;
    if (self.savedConnection && !self.pageReady) { [self connectSavedSession:self.savedConnection]; return; }
    NSUInteger generation = ++self.operationGeneration;
    BHTWebSessionRecord(BHTWebSessionEventConfirmationTapped);
    if (!BHTWebSessionURLIsAllowed(self.webView.URL)) {
        [self showErrorKey:@"SECURE_WEB_SIGN_IN_RETURN_TO_X"];
        return;
    }
    [self setBusy:YES message:BHTWebSessionLocalized(
        @"SECURE_WEB_SIGN_IN_CHECKING")];
    __weak typeof(self) weakSelf = self;
    [self.webView.configuration.websiteDataStore.httpCookieStore
        getAllCookies:^(NSArray<NSHTTPCookie*>* cookies) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BHTSecureWebSessionViewController* strongSelf = weakSelf;
            if (!strongSelf || strongSelf.operationGeneration != generation) return;
            NSDictionary* components = BHTWebSessionComponentsFromCookies(cookies);
            if (!components) {
                BHTWebSessionRecord(
                    BHTWebSessionEventCookieSetIncomplete);
                [strongSelf showErrorKey:
                    @"SECURE_WEB_SIGN_IN_NOT_READY"];
                return;
            }

            // Query only X's stable profile-navigation link. The script does
            // not read document text, forms, storage, or cookies.
            NSString* script =
                @"(() => { const a = document.querySelector('a[data-testid=\"AppTabBar_Profile_Link\"]'); if (!a) return null; const h = a.getAttribute('href') || ''; const m = h.match(/^\\/([A-Za-z0-9_]{1,15})(?:\\/|$)/); return m ? m[1] : null; })()";
            [strongSelf.webView evaluateJavaScript:script
                                 completionHandler:^(id result,
                                                     __unused NSError* error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString* handle =
                        BHTWebSessionNormalizedHandle(result);
                    if (handle.length > 0) {
                        BHTWebSessionRecord(
                            BHTWebSessionEventHandleDetected);
                    }
                    if (strongSelf.operationGeneration != generation) return;
                    // The numeric identity must match X's own session. A
                    // verified API result takes priority over the UI label;
                    // the visible profile link remains a resilient fallback.
                    BHTResolveWebSessionIdentity(components, ^(NSString* verified, NSDictionary* updated, BOOL mismatch) {
                        if (strongSelf.operationGeneration != generation) return;
                        if (mismatch) {
                            [strongSelf showErrorKey:@"SECURE_WEB_SIGN_IN_IDENTITY_CHANGED"];
                            return;
                        }
                        [strongSelf finishWithComponents:updated screenName:verified ?: handle];
                    });
                });
            }];
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 18 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf.busy && strongSelf.operationGeneration == generation) {
            strongSelf.operationGeneration++;
            [strongSelf showErrorKey:@"SECURE_WEB_SIGN_IN_CHECK_TIMEOUT"];
        }
    });
}

- (void)webView:(WKWebView*)webView
    didStartProvisionalNavigation:(WKNavigation*)navigation {
    if (!self.busy) {
        self.statusLabel.text = BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_LOADING");
    }
}

- (void)webView:(WKWebView*)webView
    didFinishNavigation:(WKNavigation*)navigation {
    if (!self.busy) {
        self.statusLabel.text = BHTWebSessionLocalized(
            @"SECURE_WEB_SIGN_IN_STATUS");
    }
    [self updateReadiness];
}

- (void)webView:(WKWebView*)webView
    didFailProvisionalNavigation:(WKNavigation*)navigation
                       withError:(NSError*)error {
    if (!self.busy && error.code != NSURLErrorCancelled) {
        [self showErrorKey:@"SECURE_WEB_SIGN_IN_LOAD_ERROR"];
    }
}

- (void)webView:(WKWebView*)webView
    decidePolicyForNavigationAction:(WKNavigationAction*)action
                    decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    if (BHTWebSessionNavigationURLIsAllowed(action.request.URL) ||
        (!action.targetFrame.isMainFrame && [action.request.URL.scheme isEqualToString:@"about"])) {
        handler(WKNavigationActionPolicyAllow);
    } else {
        handler(WKNavigationActionPolicyCancel);
        if (!self.busy) {
            [self showErrorKey:@"SECURE_WEB_SIGN_IN_BLOCKED_HOST"];
        }
    }
}

- (WKWebView*)webView:(WKWebView*)webView createWebViewWithConfiguration:(WKWebViewConfiguration*)configuration
 forNavigationAction:(WKNavigationAction*)action windowFeatures:(WKWindowFeatures*)features {
    if (!action.targetFrame && BHTWebSessionNavigationURLIsAllowed(action.request.URL)) {
        [webView loadRequest:action.request];
    }
    return nil;
}

@end

BOOL BHTSecureWebSessionMayCompleteHandoff(UIViewController* source, id account) {
    if (![source isKindOfClass:BHTSecureWebSessionViewController.class]) return YES;
    BHTSecureWebSessionViewController* controller = (id)source;
    return controller.busy && !controller.completed &&
        [controller.savedConnection[@"userID"] unsignedLongLongValue] == BHTWebSessionNativeAccountUserID(account);
}

UIViewController* BHTSecureWebSessionOnboardingController(void) {
    if (!BHTSecureWebSessionSignInIsAvailable()) return nil;
    BHTSecureWebSessionViewController* controller = [BHTSecureWebSessionViewController new];
    controller.rootSignIn = YES;
    UINavigationController* navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    BHTWebSessionPresentedController = navigation;
    BHTWebSessionRecord(BHTWebSessionEventPresented);
    return navigation;
}

__attribute__((constructor)) static void BHTInstallWebSessionUnlockRecovery(void) {
    if (!BHTWebSessionVersionIsSupported()) return;
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationProtectedDataDidBecomeAvailable
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification* notification) {
            BHTSecureWebSessionRestoreSavedAccounts();
        }];
}

static void BHTPresentSecureWebSessionBrowser(
    UIViewController* source,
    UIViewController* addAccountController) {
    if (BHTWebSessionPresentedController) return;
    BHTSecureWebSessionViewController* controller =
        [BHTSecureWebSessionViewController new];
    controller.addAccountController = addAccountController;
    UINavigationController* navigation =
        [[UINavigationController alloc]
            initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    navigation.preferredContentSize = CGSizeMake(620.0, 760.0);
    BHTWebSessionPresentedController = navigation;
    BHTWebSessionRecord(BHTWebSessionEventPresented);
    [source presentViewController:navigation
                        animated:YES completion:nil];
}

void BHTPresentSecureWebSessionSignIn(
    UIViewController* presenter,
    UIViewController* addAccountController) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController* source = BHTWebSessionTopController(presenter) ?:
            BHTWebSessionActiveController();
        if (!source || BHTWebSessionPresentedController) return;
        if (!BHTSecureWebSessionSignInIsAvailable()) {
            UIAlertController* unavailable = [UIAlertController
                alertControllerWithTitle:BHTWebSessionLocalized(
                    @"SECURE_WEB_SIGN_IN_TITLE")
                                 message:BHTWebSessionLocalized(
                    @"SECURE_WEB_SIGN_IN_UNAVAILABLE")
                          preferredStyle:UIAlertControllerStyleAlert];
            [unavailable addAction:[UIAlertAction
                actionWithTitle:BHTWebSessionLocalized(
                    @"COMPATIBILITY_SIGN_IN_OK")
                          style:UIAlertActionStyleCancel handler:nil]];
            [source presentViewController:unavailable
                                 animated:YES completion:nil];
            return;
        }
        BHTPresentSecureWebSessionBrowser(
            source, addAccountController);
    });
}

NSDictionary<NSString*, id>*
BHTSecureWebSessionDiagnosticSnapshot(void) {
    NSArray<NSString*>* names = @[
        @"presented",
        @"confirmationTapped",
        @"cookieSetComplete",
        @"cookieSetIncomplete",
        @"handleDetected",
        @"handleEntered",
        @"keychainSaved",
        @"keychainSaveFailed",
        @"accountInstallStarted",
        @"accountInstallFailed",
        @"requestEligible",
        @"requestAuthenticated",
        @"revoked",
        @"restored",
        @"refreshSaved",
        @"keychainRetry",
    ];
    NSMutableDictionary* counters =
        [NSMutableDictionary dictionaryWithCapacity:names.count];
    [names enumerateObjectsUsingBlock:^(
        NSString* name, NSUInteger index, __unused BOOL* stop) {
        counters[name] = @(atomic_load_explicit(
            &BHTWebSessionCounters[index], memory_order_relaxed));
    }];
    return @{
        @"available": @(BHTSecureWebSessionSignInIsAvailable()),
        @"activeSessionPresent":
            @(BHTSecureWebSessionHasActiveSession()),
        @"passwordReadByTweak": @NO,
        @"cookieReadRequiresUserConfirmation": @YES,
        @"sessionStoredInDeviceOnlyKeychain": @YES,
        @"sessionStoredInUserDefaults": @NO,
        @"sessionStoredInPlaintextFile": @NO,
        @"credentialLoggingIncluded": @NO,
        @"requestHostPolicy": @"https_exact_domain_or_subdomain",
        @"requestDomains": @[@"x.com", @"twitter.com"],
        @"requestMutationLayer": @"NSURLSession_task_constructors",
        @"globalMutableRequestHooksIncluded": @NO,
        @"hiddenGestureEntryIncluded": @NO,
        @"nativeAccountUsesSessionSecrets": @NO,
        @"perAccountSessionStorage": @YES,
        @"requestRequiresAccountMarker": @YES,
        @"temporaryKeychainErrorsAreRetryable": @YES,
        @"savedAccountRestorationIncluded": @YES,
        @"freshSignInUsesEphemeralStore": @YES,
        @"revocationClearsKeychainAndWebData": @YES,
        @"counters": [counters copy],
    };
}
