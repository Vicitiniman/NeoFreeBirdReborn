#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
extern const void* const BHTWebSessionResponseContextKey;
// All calls are bound to one confirmed session. Preparing is asynchronous;
// there is no timer polling, main-thread wait, or credential-bearing native
// token. The retained web helper is restricted to first-party HTTPS.
void BHTPrepareWebSessionRequests(NSDictionary* session);
void BHTForgetWebSessionRequests(uint64_t userID);
NSURLRequest* BHTWebSessionRequestForSession(NSURLRequest* request, NSDictionary* session);
void BHTRefreshWebSessionCookies(NSDictionary* session,
    void (^completion)(NSDictionary* _Nullable updated));
void BHTResolveWebSessionIdentity(NSDictionary* session,
    void (^completion)(NSString* _Nullable screenName));
NS_ASSUME_NONNULL_END
