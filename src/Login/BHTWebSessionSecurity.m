#import "Login/BHTWebSessionSecurity.h"

#include <errno.h>
#include <stdlib.h>
#include <limits.h>
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL BHTWebSessionHostMatchesDomain(
    NSString* host,
    NSString* domain) {
    return [host isEqualToString:domain] ||
           [host hasSuffix:[@"." stringByAppendingString:domain]];
}

BOOL BHTWebSessionURLIsAllowed(NSURL* URL) {
    if (![URL isKindOfClass:NSURL.class]) return NO;
    NSURLComponents* components =
        [NSURLComponents componentsWithURL:URL
                   resolvingAgainstBaseURL:NO];
    if (![[components.scheme lowercaseString] isEqualToString:@"https"] ||
        components.user.length > 0 || components.password.length > 0) {
        return NO;
    }
    NSNumber* port = components.port;
    if (port && port.unsignedIntegerValue != 443) return NO;
    NSString* host = components.host.lowercaseString ?: @"";
    return BHTWebSessionHostMatchesDomain(host, @"x.com") ||
           BHTWebSessionHostMatchesDomain(host, @"twitter.com");
}

BHTWebSignInAction BHTWebSignInActionForState(NSURL* URL, BOOL busy, BOOL hasSavedSession, BOOL signedInLanding) {
    if (busy) return BHTWebSignInActionUnavailable;
    if (hasSavedSession && !signedInLanding) return BHTWebSignInActionReconnect;
    return BHTWebSessionURLIsAllowed(URL) ? BHTWebSignInActionConfirm : BHTWebSignInActionUnavailable;
}

NSString* BHTWebSessionNormalizedHandle(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString* handle = [(NSString*)value
        stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([handle hasPrefix:@"@"]) {
        handle = [handle substringFromIndex:1];
    }
    if (handle.length == 0 || handle.length > 15) return nil;
    NSCharacterSet* allowed = [NSCharacterSet
        characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"];
    if ([[handle stringByTrimmingCharactersInSet:allowed] length] != 0) {
        return nil;
    }
    return handle;
}

uint64_t BHTWebSessionUserIDFromTWID(NSString* value) {
    if (![value isKindOfClass:NSString.class] ||
        value.length == 0 || value.length > 128) {
        return 0;
    }
    NSString* decoded = value.stringByRemovingPercentEncoding ?: value;
    if ([decoded hasPrefix:@"u="]) {
        decoded = [decoded substringFromIndex:2];
    }
    if (decoded.length == 0 || decoded.length > 20) return 0;
    NSCharacterSet* digits = NSCharacterSet.decimalDigitCharacterSet;
    if ([[decoded stringByTrimmingCharactersInSet:digits] length] != 0) {
        return 0;
    }
    errno = 0;
    char* end = NULL;
    unsigned long long result =
        strtoull(decoded.UTF8String, &end, 10);
    return errno == 0 && end && *end == '\0' && result > 0
               ? (uint64_t)result
               : 0;
}

BOOL BHTWebSessionCredentialValueIsValid(NSString* value) {
    if (![value isKindOfClass:NSString.class] ||
        value.length < 8 || value.length > 512) {
        return NO;
    }
    NSCharacterSet* allowed = [NSCharacterSet
        characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789%._~-+"];
    return [[value stringByTrimmingCharactersInSet:allowed] length] == 0;
}

BOOL BHTWebSessionTransactionValueIsValid(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] < 16 || [value length] > 512) return NO;
    NSCharacterSet* allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/_-="];
    return [[value stringByTrimmingCharactersInSet:allowed] length] == 0;
}

NSDictionary* BHTWebSessionValidatedSession(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary* candidate = value;
    NSString* handle = BHTWebSessionNormalizedHandle(candidate[@"screenName"]);
    id number = candidate[@"userID"];
    uint64_t userID = [number isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)number) != CFBooleanGetTypeID()
        ? [number unsignedLongLongValue] : 0;
    if (!handle || !userID || userID > LLONG_MAX || [number compare:@(userID)] != NSOrderedSame ||
        !BHTWebSessionCredentialValueIsValid(candidate[@"auth"]) ||
        !BHTWebSessionCredentialValueIsValid(candidate[@"csrf"])) return nil;
    NSMutableDictionary* session = [@{
        @"version": @2, @"screenName": handle, @"userID": @(userID),
        @"auth": [candidate[@"auth"] copy], @"csrf": [candidate[@"csrf"] copy],
    } mutableCopy];
    for (NSString* key in @[@"lastUsed", @"lastRefresh"]) {
        id timestamp = candidate[key];
        if ([timestamp isKindOfClass:NSDate.class]) session[key] = timestamp;
    }
    if ([candidate[@"needsSignIn"] isEqual:@YES]) session[@"needsSignIn"] = @YES;
    return [session copy];
}

NSString* BHTWebSessionAccountMarker(uint64_t userID) {
    return userID && userID <= LLONG_MAX
        ? [NSString stringWithFormat:@"%llu-neofreebird_web_session", (unsigned long long)userID] : @"";
}

uint64_t BHTWebSessionUserIDFromAccountMarker(NSString* marker) {
    NSString* suffix = @"-neofreebird_web_session";
    if (![marker isKindOfClass:NSString.class] || ![marker hasSuffix:suffix]) return 0;
    NSString* prefix = [marker substringToIndex:marker.length - suffix.length];
    uint64_t userID = BHTWebSessionUserIDFromTWID(prefix);
    return [BHTWebSessionAccountMarker(userID) isEqualToString:marker] ? userID : 0;
}

NSString* BHTWebSessionOAuthTokenFromRequest(NSURLRequest* request) {
    NSString* authorization = [request valueForHTTPHeaderField:@"Authorization"];
    if (authorization.length == 0 || authorization.length > 16384 ||
        [authorization rangeOfString:@"OAuth " options:NSAnchoredSearch | NSCaseInsensitiveSearch].location != 0) return nil;
    static NSRegularExpression* expression;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        expression = [NSRegularExpression regularExpressionWithPattern:
            @"(?:^|[,\\s])oauth_token\\s*=\\s*\"([^\"]+)\"" options:0 error:nil];
    });
    NSArray* matches = [expression matchesInString:authorization options:0
        range:NSMakeRange(0, authorization.length)];
    if (matches.count != 1) return nil;
    NSString* token = [authorization substringWithRange:[matches.firstObject rangeAtIndex:1]];
    return token.stringByRemovingPercentEncoding;
}

uint64_t BHTWebSessionRequestOwner(NSURLRequest* request) {
    if (!BHTWebSessionURLIsAllowed(request.URL)) return 0;
    // Never guess ownership from the currently selected account or from a
    // sole stored session. A stale request may belong to a removed account.
    return BHTWebSessionUserIDFromAccountMarker(BHTWebSessionOAuthTokenFromRequest(request));
}

uint64_t BHTWebSessionNativeAccountUserID(id account) {
    SEL selector = NSSelectorFromString(@"userID");
    Method method = class_getInstanceMethod([account class], selector);
    if (!method || ![account respondsToSelector:selector]) return 0;
    char type[16] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] == 'q' || type[0] == 'Q') {
        uint64_t result = ((uint64_t (*)(id, SEL))objc_msgSend)(account, selector);
        return result <= LLONG_MAX ? result : 0;
    }
    if (type[0] == '@') {
        id value = ((id (*)(id, SEL))objc_msgSend)(account, selector);
        return [value isKindOfClass:NSNumber.class] && [value longLongValue] > 0
            ? [value unsignedLongLongValue] : 0;
    }
    return 0;
}

BOOL BHTWebSessionAccountUsesPlaceholder(id account) {
    for (NSString* name in @[@"oAuthToken", @"oAuthTokenSecret"]) {
        SEL selector = NSSelectorFromString(name);
        if (![account respondsToSelector:selector]) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(account, selector);
        if ([value isKindOfClass:NSString.class] &&
            ([value isEqualToString:@"neofreebird_web_session"] ||
             BHTWebSessionUserIDFromAccountMarker(value))) return YES;
    }
    return NO;
}

BOOL BHTWebSessionRequestNeedsWebRoute(NSURLRequest* request) {
    if (!BHTWebSessionURLIsAllowed(request.URL)) return NO;
    NSString* method = request.HTTPMethod.uppercaseString ?: @"GET";
    if ([method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"]) return NO;
    NSString* operation = request.URL.lastPathComponent;
    static NSSet* operations;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        operations = [NSSet setWithArray:@[@"CreateTweet", @"CreateTweetWithUndo", @"DeleteTweet",
            @"FavoriteTweet", @"UnfavoriteTweet", @"CreateRetweet", @"DeleteRetweet",
            @"CreateBookmark", @"DeleteBookmark"]];
    });
    return [operations containsObject:operation];
}

NSURL* BHTWebSessionWebEquivalentURL(NSURL* URL) {
    if (!BHTWebSessionURLIsAllowed(URL)) return nil;
    NSRange graphql = [URL.path rangeOfString:@"/graphql/"];
    if (graphql.location == NSNotFound) return nil;
    NSURLComponents* components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
    components.host = @"x.com";
    components.port = nil;
    components.path = [@"/i/api" stringByAppendingString:[URL.path substringFromIndex:graphql.location]];
    return components.URL;
}

NSURLRequest* BHTWebSessionBuildAuthenticatedRequest(NSURLRequest* request, NSDictionary* session, NSString* transaction) {
    uint64_t owner = BHTWebSessionUserIDFromAccountMarker(BHTWebSessionOAuthTokenFromRequest(request));
    if (!BHTWebSessionURLIsAllowed(request.URL) || !BHTWebSessionValidatedSession(session) ||
        !owner || owner != [session[@"userID"] unsignedLongLongValue] || [session[@"needsSignIn"] boolValue]) return request;
    NSMutableURLRequest* result = [request mutableCopy];
    BOOL webWrite = BHTWebSessionRequestNeedsWebRoute(request);
    if (webWrite) {
        NSURL* URL = BHTWebSessionWebEquivalentURL(request.URL);
        if (!URL) return request;
        result.URL = URL;
        for (NSString* name in @[@"X-Twitter-Client-DeviceID", @"X-Twitter-Client-Version", @"X-Twitter-Client",
            @"X-Twitter-API-Version", @"X-Client-UUID", @"X-B3-TraceId", @"Host"]) [result setValue:nil forHTTPHeaderField:name];
        if (BHTWebSessionTransactionValueIsValid(transaction)) [result setValue:transaction forHTTPHeaderField:@"x-client-transaction-id"];
    }
    // These public client identifiers are included in X's shipped clients.
    NSString* readBearer = @"Bearer AAAAAAAAAAAAAAAAAAAAAAj4AQAAAAAAPraK64zCZ9CSzdLesbE7LB%2Bw4uE%3DVJQREvQNCZJNiz3rHO7lOXlkVOQkzzdsgu6wWgcazdMUaGoUGm";
    NSString* writeBearer = @"Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA";
    result.HTTPShouldHandleCookies = NO;
    [result setValue:webWrite ? writeBearer : readBearer forHTTPHeaderField:@"Authorization"];
    [result setValue:session[@"csrf"] forHTTPHeaderField:@"x-csrf-token"];
    [result setValue:@"OAuth2Session" forHTTPHeaderField:@"x-twitter-auth-type"];
    [result setValue:@"yes" forHTTPHeaderField:@"x-twitter-active-user"];
    [result setValue:BHTWebSessionCookieHeader(nil, session[@"auth"], session[@"csrf"], owner) forHTTPHeaderField:@"Cookie"];
    return [result copy];
}

static BOOL BHTWebSessionCookieBelongsToResponse(NSHTTPCookie* cookie, NSHTTPURLResponse* response) {
    NSString* domain = cookie.domain.lowercaseString;
    while ([domain hasPrefix:@"."]) domain = [domain substringFromIndex:1];
    return (BHTWebSessionHostMatchesDomain(domain, @"x.com") || BHTWebSessionHostMatchesDomain(domain, @"twitter.com")) &&
        BHTWebSessionHostMatchesDomain(response.URL.host.lowercaseString, domain);
}

static BOOL BHTWebSessionResponseUserMismatch(NSDictionary* session, NSHTTPURLResponse* response) {
    NSArray* cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:response.allHeaderFields forURL:response.URL];
    for (NSHTTPCookie* cookie in cookies) {
        if (BHTWebSessionCookieBelongsToResponse(cookie, response) && [cookie.name isEqualToString:@"twid"] &&
            BHTWebSessionUserIDFromTWID(cookie.value) != [session[@"userID"] unsignedLongLongValue]) return YES;
    }
    return NO;
}

NSDictionary* BHTWebSessionUpdatedSessionFromResponse(NSDictionary* session, NSHTTPURLResponse* response) {
    if (![response isKindOfClass:NSHTTPURLResponse.class] ||
        !BHTWebSessionURLIsAllowed(response.URL) || !BHTWebSessionValidatedSession(session)) return nil;
    NSArray* cookies = [NSHTTPCookie cookiesWithResponseHeaderFields:response.allHeaderFields forURL:response.URL];
    if (BHTWebSessionResponseUserMismatch(session, response)) return nil;
    NSMutableDictionary* updated = [session mutableCopy];
    BOOL changed = NO;
    for (NSHTTPCookie* cookie in cookies) {
        if (!BHTWebSessionCookieBelongsToResponse(cookie, response)) continue;
        NSString* key = [cookie.name isEqualToString:@"ct0"] ? @"csrf" :
            ([cookie.name isEqualToString:@"auth_token"] ? @"auth" : nil);
        if (!key || !BHTWebSessionCredentialValueIsValid(cookie.value) ||
            (cookie.expiresDate && [cookie.expiresDate timeIntervalSinceNow] <= 0)) continue;
        if (![updated[key] isEqual:cookie.value]) { updated[key] = cookie.value; changed = YES; }
    }
    if (!changed) return nil;
    updated[@"lastRefresh"] = NSDate.date;
    return BHTWebSessionValidatedSession(updated);
}

NSDictionary* BHTWebSessionIdentityFromResponse(NSDictionary* session, NSData* data, NSHTTPURLResponse* response) {
    NSDictionary* validated = BHTWebSessionValidatedSession(session);
    if (!validated) return @{};
    BOOL allowed = [response isKindOfClass:NSHTTPURLResponse.class] && BHTWebSessionURLIsAllowed(response.URL);
    BOOL mismatch = allowed && BHTWebSessionResponseUserMismatch(validated, response);
    NSDictionary* updated = allowed && !mismatch ? BHTWebSessionUpdatedSessionFromResponse(validated, response) : nil;
    NSMutableDictionary* result = [@{@"session":updated ?: validated, @"identityMismatch":@(mismatch)} mutableCopy];
    if (allowed && !mismatch && response.statusCode == 200 && data.length > 0 && data.length <= 262144) {
        id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([value isKindOfClass:NSDictionary.class]) {
            id number = value[@"id"];
            id identity = value[@"id_str"] ?: ([number isKindOfClass:NSNumber.class] ? [number stringValue] : nil);
            uint64_t userID = BHTWebSessionUserIDFromTWID(identity);
            if (userID && userID != [validated[@"userID"] unsignedLongLongValue]) {
                result[@"identityMismatch"] = @YES;
                result[@"session"] = validated;
            } else if (userID) {
                NSString* handle = BHTWebSessionNormalizedHandle(value[@"screen_name"]);
                if (handle) result[@"screenName"] = handle;
            }
        }
    }
    return [result copy];
}

NSString* BHTWebSessionCookieHeader(
    NSString* existingHeader,
    NSString* authToken,
    NSString* csrfToken,
    uint64_t userID) {
    NSMutableArray<NSString*>* pieces = [NSMutableArray array];
    NSSet<NSString*>* replacedNames = [NSSet setWithArray:@[
        @"auth_token", @"ct0", @"twid"
    ]];
    if ([existingHeader isKindOfClass:NSString.class]) {
        for (NSString* rawPiece in
                 [existingHeader componentsSeparatedByString:@";"]) {
            NSString* piece = [rawPiece
                stringByTrimmingCharactersInSet:
                    NSCharacterSet.whitespaceAndNewlineCharacterSet];
            NSRange equals = [piece rangeOfString:@"="];
            if (equals.location == NSNotFound ||
                equals.location == 0) {
                continue;
            }
            NSString* name = [[piece substringToIndex:equals.location]
                lowercaseString];
            if (![replacedNames containsObject:name] &&
                piece.length <= 2048) {
                [pieces addObject:piece];
            }
        }
    }
    [pieces addObject:[@"auth_token=" stringByAppendingString:authToken]];
    [pieces addObject:[@"ct0=" stringByAppendingString:csrfToken]];
    [pieces addObject:[NSString
        stringWithFormat:@"twid=u%%3D%llu",
                         (unsigned long long)userID]];
    return [pieces componentsJoinedByString:@"; "];
}
