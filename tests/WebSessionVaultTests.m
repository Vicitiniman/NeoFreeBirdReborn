// Exercises production persistence and account routing using synthetic values
// and an in-memory backend. Never reads the machine's Keychain or any X data.
static NSDictionary* BHTSyntheticSession(uint64_t userID, NSString* handle) {
    return @{@"version":@2, @"userID":@(userID), @"screenName":handle,
        @"auth":[NSString stringWithFormat:@"synthetic_auth_%llu",(unsigned long long)userID],
        @"csrf":[NSString stringWithFormat:@"synthetic_csrf_%llu",(unsigned long long)userID]};
}

static NSMutableURLRequest* BHTSyntheticRequest(uint64_t userID, NSString* path) {
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:[@"https://api.x.com" stringByAppendingString:path]]];
    [request setValue:[NSString stringWithFormat:@"OAuth oauth_token=\"%@\", oauth_signature=\"synthetic\"",
        BHTWebSessionAccountMarker(userID)] forHTTPHeaderField:@"Authorization"];
    return request;
}

static void testWebSessionVault(void) {
    NSMutableDictionary* disk = [NSMutableDictionary dictionary];
    __block BOOL locked = NO;
    __block BOOL writable = YES;
    __block NSUInteger readCount = 0;
    BHTWebSessionVaultRead read = ^BHTWebSessionVaultReadStatus(NSArray** values) {
        readCount++;
        if (locked) return BHTWebSessionVaultReadUnavailable;
        *values = disk.allValues;
        return BHTWebSessionVaultReadComplete;
    };
    BHTWebSessionVaultWrite write = ^BOOL(NSDictionary* session) {
        if (!writable) return NO;
        disk[session[@"userID"]] = session; return YES;
    };
    BHTWebSessionVaultRemove remove = ^BOOL(uint64_t userID) {
        if (!writable) return NO;
        [disk removeObjectForKey:@(userID)]; return YES;
    };
    BHTWebSessionVault* vault = [[BHTWebSessionVault alloc] initWithRead:read write:write remove:remove];
    NSDictionary* first = BHTSyntheticSession(42, @"first_user");
    NSDictionary* second = BHTSyntheticSession(99, @"second_user");
    NSCAssert([vault saveSession:first] && [vault saveSession:second], @"Both confirmed sessions must save");
    NSCAssert(vault.sessions.count == 2, @"Adding another account must not replace the first");
    NSMutableDictionary* legacy = [first mutableCopy]; legacy[@"version"] = @1;
    NSCAssert([BHTWebSessionValidatedSession(legacy)[@"version"] isEqual:@2] &&
        [BHTWebSessionValidatedSession(legacy)[@"auth"] isEqual:first[@"auth"]], @"Migrate the old session schema without changing its credentials");

    // A force quit discards all in-process cache state; both durable records
    // must be usable by a newly constructed store without a web sign-in.
    vault = [[BHTWebSessionVault alloc] initWithRead:read write:write remove:remove];
    NSCAssert([[vault sessionForUserID:42][@"auth"] isEqual:first[@"auth"]] &&
              [[vault sessionForUserID:99][@"auth"] isEqual:second[@"auth"]], @"Restore both sessions after restart");

    // Reproduce the old intermittent logout: a cold Keychain read while
    // locked followed by a successful unlock must not cache an empty result.
    locked = YES;
    vault = [[BHTWebSessionVault alloc] initWithRead:read write:write remove:remove];
    NSCAssert(vault.sessions.count == 0 && vault.readUnavailable, @"A locked read is unavailable, not a confirmed logout");
    NSUInteger failedReads = readCount;
    [vault sessionForUserID:42]; [vault sessionForUserID:99];
    NSCAssert(readCount == failedReads, @"Do not hammer the locked Keychain on every account gate");
    locked = NO; [vault retryAfterUnlock];
    NSCAssert(vault.sessions.count == 2 && !vault.readUnavailable, @"Unlock retries the read and restores accounts");
    locked = YES; [vault retryAfterUnlock];
    NSCAssert([vault sessionForUserID:42] != nil, @"A temporary read failure must preserve a previously loaded session");
    locked = NO; [vault retryAfterUnlock];

    // A failed durable write cannot replace working in-memory credentials.
    NSMutableDictionary* renewed = [first mutableCopy]; renewed[@"auth"] = @"synthetic_new_auth_42";
    writable = NO;
    NSCAssert(![vault saveSession:renewed] && [[vault sessionForUserID:42][@"auth"] isEqual:first[@"auth"]],
        @"Keep the previous valid session if saving a replacement fails");
    writable = YES; NSCAssert([vault saveSession:renewed], @"Persist a renewed account session");
    NSMutableDictionary* stale = [first mutableCopy]; stale[@"csrf"] = @"synthetic_stale_csrf";
    NSCAssert(![vault updateSession:stale ifAuthMatches:first[@"auth"]], @"An old response must not overwrite a new login");
    NSCAssert([[vault sessionForUserID:99][@"auth"] isEqual:second[@"auth"]], @"Refreshing A must leave B unchanged");
    NSMutableDictionary* rotated = [renewed mutableCopy]; rotated[@"csrf"] = @"synthetic_rotated_csrf";
    NSCAssert([vault updateSession:rotated ifAuthMatches:renewed[@"auth"]], @"Persist same-account cookie rotations");
    vault = [[BHTWebSessionVault alloc] initWithRead:read write:write remove:remove];
    NSCAssert([[vault sessionForUserID:42][@"csrf"] isEqual:rotated[@"csrf"]], @"Rotated cookies survive a force quit");
    NSCAssert([vault removeUserID:42], @"Explicit logout removes only the chosen account");
    NSCAssert([vault isRemovedUserID:42], @"Explicit logout overrides a temporary locked-Keychain fallback");
    NSCAssert(![vault updateSession:rotated ifAuthMatches:renewed[@"auth"]], @"An in-flight response must not resurrect a logged-out account");
    vault = [[BHTWebSessionVault alloc] initWithRead:read write:write remove:remove];
    NSCAssert(![vault sessionForUserID:42] && [vault sessionForUserID:99], @"Logout stays effective across restart and preserves other accounts");

    for (id invalid in @[@{@"userID":@YES}, @{@"userID":@-1}, @{@"userID":@1.5}]) {
        NSMutableDictionary* malformed = [first mutableCopy]; [malformed addEntriesFromDictionary:invalid];
        NSCAssert(!BHTWebSessionValidatedSession(malformed), @"Reject invalid numeric identities");
    }

    NSURLRequest* requestA = BHTSyntheticRequest(42, @"/graphql/query/HomeTimeline");
    NSCAssert(BHTWebSessionRequestOwner(requestA) == 42, @"A request carries its own account ID");
    NSURLRequest* outgoing = BHTWebSessionBuildAuthenticatedRequest(requestA, first, nil);
    NSCAssert(outgoing != requestA && [[outgoing valueForHTTPHeaderField:@"Cookie"] containsString:first[@"auth"]],
        @"Attach only the requesting account's credentials");
    NSCAssert(BHTWebSessionBuildAuthenticatedRequest(requestA, second, nil) == requestA,
        @"Fail closed when a selected account or supplied session belongs to someone else");
    NSCAssert([requestA valueForHTTPHeaderField:@"Cookie"] == nil, @"Do not mutate a native request in place");
    NSCAssert(!outgoing.HTTPShouldHandleCookies, @"The shared cookie jar must not replace per-account credentials");
    NSMutableURLRequest* unsignedRequest = [requestA mutableCopy];
    [unsignedRequest setValue:nil forHTTPHeaderField:@"Authorization"];
    NSCAssert(BHTWebSessionRequestOwner(unsignedRequest) == 0 &&
        BHTWebSessionBuildAuthenticatedRequest(unsignedRequest, first, nil) == unsignedRequest,
        @"Public, unsigned requests do not inherit a signed-in account");
    [unsignedRequest setValue:@"OAuth oauth_token=\"42-real_native_token\"" forHTTPHeaderField:@"Authorization"];
    NSCAssert(BHTWebSessionRequestOwner(unsignedRequest) == 0, @"Working native OAuth accounts remain untouched");
    [unsignedRequest setValue:@"OAuth oauth_token=\"neofreebird_web_session\"" forHTTPHeaderField:@"Authorization"];
    NSCAssert(BHTWebSessionRequestOwner(unsignedRequest) == 0, @"Never guess the owner of an old, ambiguous queued request");
    [unsignedRequest setValue:@"OAuth oauth_token=\"42-neofreebird_web_session\", oauth_token=\"99-neofreebird_web_session\"" forHTTPHeaderField:@"Authorization"];
    NSCAssert(BHTWebSessionRequestOwner(unsignedRequest) == 0, @"Reject conflicting OAuth token fields");
    NSMutableURLRequest* external = [requestA mutableCopy]; external.URL = [NSURL URLWithString:@"https://x.com.evil.example/graphql/q/HomeTimeline"];
    NSCAssert(BHTWebSessionRequestOwner(external) == 0 && BHTWebSessionBuildAuthenticatedRequest(external, first, nil) == external,
        @"Never attach account cookies to an untrusted host");
    NSMutableURLRequest* writeRequest = BHTSyntheticRequest(42, @"/graphql/currentQuery/CreateTweet");
    writeRequest.HTTPMethod = @"POST";
    writeRequest.HTTPBody = [@"{\"synthetic\":true}" dataUsingEncoding:NSUTF8StringEncoding];
    [writeRequest setValue:@"native-version" forHTTPHeaderField:@"X-Twitter-Client-Version"];
    NSURLRequest* webWrite = BHTWebSessionBuildAuthenticatedRequest(writeRequest, first, @"synthetic_transaction");
    NSCAssert([webWrite.URL.absoluteString isEqual:@"https://x.com/i/api/graphql/currentQuery/CreateTweet"] &&
        [webWrite.HTTPBody isEqual:writeRequest.HTTPBody], @"Route a native write while preserving its body and current query ID");
    NSCAssert([[webWrite valueForHTTPHeaderField:@"x-client-transaction-id"] isEqual:@"synthetic_transaction"] &&
        ![webWrite valueForHTTPHeaderField:@"X-Twitter-Client-Version"], @"Use the prepared web transaction and remove conflicting native headers");
    NSCAssert(!BHTWebSessionTransactionValueIsValid(@"invalid\r\ntransaction") &&
        !BHTWebSessionTransactionValueIsValid(@"ERR:the-script-failed") && !BHTWebSessionTransactionValueIsValid(@42),
        @"Only bounded, header-safe transaction values can leave the web helper");
    NSMutableDictionary* expired = [first mutableCopy]; expired[@"needsSignIn"] = @YES;
    NSCAssert(BHTWebSessionBuildAuthenticatedRequest(requestA, expired, nil) == requestA,
        @"A confirmed sign-in-required session cannot keep authenticating requests");

    NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://api.x.com/test"]
        statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Set-Cookie":@"ct0=synthetic_new_csrf; Domain=.x.com; Path=/; Secure"}];
    NSDictionary* changed = BHTWebSessionUpdatedSessionFromResponse(first, response);
    NSCAssert([changed[@"csrf"] isEqual:@"synthetic_new_csrf"] && [changed[@"auth"] isEqual:first[@"auth"]],
        @"Capture server cookie changes without changing the owner or other credentials");
    NSHTTPURLResponse* denied = [[NSHTTPURLResponse alloc] initWithURL:response.URL statusCode:403 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    NSCAssert(!BHTWebSessionUpdatedSessionFromResponse(first, denied), @"A 403 by itself is not a logout or a credential replacement");
    NSHTTPURLResponse* wrongOwner = [[NSHTTPURLResponse alloc] initWithURL:response.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
        headerFields:@{@"Set-Cookie":@"twid=u%3D99; Domain=.x.com; Path=/; Secure"}];
    NSCAssert(!BHTWebSessionUpdatedSessionFromResponse(first, wrongOwner), @"Never adopt a response for another account");
    NSHTTPURLResponse* foreignCookie = [[NSHTTPURLResponse alloc] initWithURL:response.URL statusCode:200 HTTPVersion:@"HTTP/1.1"
        headerFields:@{@"Set-Cookie":@"ct0=synthetic_foreign_csrf; Domain=evil.example; Path=/; Secure"}];
    NSCAssert(!BHTWebSessionUpdatedSessionFromResponse(first, foreignCookie), @"Ignore cookies outside the response host's domain family");
    puts("PASS: per-account sessions, restart/unlock recovery, failed saves, cookie renewal, logout, request isolation, and native write routing");
}
