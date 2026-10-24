#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Pure validation helpers shared by the web sign-in screen and the request
// bridge. They never persist or log their inputs.
BOOL BHTWebSessionURLIsAllowed(NSURL* _Nullable URL);
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
NSString* BHTWebSessionCookieHeader(
    NSString* _Nullable existingHeader,
    NSString* authToken,
    NSString* csrfToken,
    uint64_t userID);

NS_ASSUME_NONNULL_END
