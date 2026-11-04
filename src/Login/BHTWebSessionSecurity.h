#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Pure validation helpers shared by the web sign-in screen and the request
// bridge. They never persist or log their inputs.
BOOL BHTWebSessionURLIsAllowed(NSURL* _Nullable URL);
typedef NS_ENUM(NSUInteger, BHTWebSignInAction) {
    BHTWebSignInActionUnavailable,
    BHTWebSignInActionConfirm,
    BHTWebSignInActionReconnect,
};
// Page-layout detection is a convenience, not permission to inspect cookies.
// Manual confirmation remains available on X; the existing confirmation path
// must still validate the session and its account before saving anything.
BHTWebSignInAction BHTWebSignInActionForState(NSURL* _Nullable URL,
    BOOL busy, BOOL hasSavedSession, BOOL signedInLanding);
// Only cancellation and WebKit's explicit frame-policy interruption qualify.
// A network, TLS, or unsupported-URL failure remains a real page-load problem.
BOOL BHTWebSignInShouldIgnoreNavigationError(NSError* _Nullable error);
NSString* _Nullable BHTWebSessionNormalizedHandle(id _Nullable value);
uint64_t BHTWebSessionUserIDFromTWID(NSString* _Nullable value);
BOOL BHTWebSessionCredentialValueIsValid(NSString* _Nullable value);
BOOL BHTWebSessionTransactionValueIsValid(id _Nullable value);
NSDictionary* _Nullable BHTWebSessionValidatedSession(id _Nullable value);
NSString* BHTWebSessionAccountMarker(uint64_t userID);
uint64_t BHTWebSessionUserIDFromAccountMarker(NSString* _Nullable marker);
NSString* _Nullable BHTWebSessionOAuthTokenFromRequest(NSURLRequest* request);
uint64_t BHTWebSessionRequestOwner(NSURLRequest* request);
uint64_t BHTWebSessionNativeAccountUserID(id _Nullable account);
BOOL BHTWebSessionAccountUsesPlaceholder(id _Nullable account);
BOOL BHTWebSessionRequestNeedsWebRoute(NSURLRequest* request);
NSURL* _Nullable BHTWebSessionWebEquivalentURL(NSURL* URL);
NSURLRequest* BHTWebSessionBuildAuthenticatedRequest(NSURLRequest* request, NSDictionary* session,
    NSString* _Nullable transaction);
NSDictionary* _Nullable BHTWebSessionUpdatedSessionFromResponse(
    NSDictionary* session, NSHTTPURLResponse* response);
// Returns the same-account session (including rotated cookies), an optional
// screenName, and identityMismatch. An unavailable identity endpoint leaves
// the visible profile link usable; an explicit different identity does not.
NSDictionary* BHTWebSessionIdentityFromResponse(NSDictionary* session,
    NSData* _Nullable data, NSHTTPURLResponse* _Nullable response);
NSString* BHTWebSessionCookieHeader(
    NSString* _Nullable existingHeader,
    NSString* authToken,
    NSString* csrfToken,
    uint64_t userID);

NS_ASSUME_NONNULL_END
