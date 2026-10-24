#pragma once

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

BOOL BHTSecureWebSessionSignInIsAvailable(void);
BOOL BHTSecureWebSessionHasActiveSession(void);

// Presents an explicit x.com-owned sign-in screen. NeoFreeBird never receives
// the password. Session cookies are read only after the user taps the native
// confirmation button.
void BHTPresentSecureWebSessionSignIn(
    UIViewController* _Nullable presenter,
    UIViewController* _Nullable addAccountController);

// Returns the original request unless a saved session exists and the request
// is HTTPS to an exact x.com/twitter.com host or one of their subdomains,
// and its non-secret OAuth marker identifies that specific saved account.
NSURLRequest* BHTSecureWebSessionAuthenticatedRequest(
    NSURLRequest* request);

// Used only to make the locally-created account shell pass X's account gate.
// The comparison uses the stable numeric account ID and its Keychain session.
BOOL BHTSecureWebSessionOwnsNativeAccount(id _Nullable account);

UIViewController* _Nullable BHTSecureWebSessionOnboardingController(void);
void BHTSecureWebSessionRestoreSavedAccounts(void);
void BHTSecureWebSessionDidSelectAccount(id _Nullable account);
BOOL BHTSecureWebSessionForgetAccount(id _Nullable account);

// Internal, account-scoped boundaries shared with the request coordinator.
// These values are never part of reports, defaults, logs, or native tokens.
NSDictionary* _Nullable BHTSecureWebSessionCopyAccountSession(uint64_t userID);
void BHTSecureWebSessionObserveResponse(NSURLRequest* request, NSURLResponse* _Nullable response);
void BHTSecureWebSessionWatchTask(NSURLSessionTask* task, NSURLRequest* request);
void BHTSecureWebSessionNeedsSignIn(uint64_t userID, NSString* expectedAuth);
BOOL BHTSecureWebSessionMayCompleteHandoff(UIViewController* source, id account);
void BHTSecureWebSessionSaveCookiesForAccount(uint64_t userID, NSString* expectedAuth, NSArray<NSHTTPCookie*>* cookies);

// Deletes the Keychain item, the matching WebKit/URL-loading cookies, and the
// locally-created X account shell when that private API is available.
void BHTRevokeSecureWebSession(
    void (^_Nullable completion)(BOOL accountShellRemoved));

// Fixed capabilities and counters only. No handles, IDs, URLs, cookie values,
// headers, Keychain data, or errors are included.
NSDictionary<NSString*, id>*
BHTSecureWebSessionDiagnosticSnapshot(void);

NS_ASSUME_NONNULL_END
