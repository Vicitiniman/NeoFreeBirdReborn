static NSUInteger countOccurrences(NSString* value, NSString* needle) {
    NSUInteger count = 0;
    NSRange remaining = NSMakeRange(0, value.length);
    while (remaining.length > 0) {
        NSRange match = [value rangeOfString:needle
                                    options:0 range:remaining];
        if (match.location == NSNotFound) break;
        count++;
        NSUInteger next = NSMaxRange(match);
        remaining = NSMakeRange(next, value.length - next);
    }
    return count;
}

static void testWebSessionSecurity(void) {
    NSCAssert(BHTWebSignInShouldIgnoreNavigationError([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]),
        @"Cancelling an old web load must not display a sign-in failure");
    for (NSString* domain in @[@"WebKitErrorDomain", @"WKErrorDomain"]) {
        NSCAssert(BHTWebSignInShouldIgnoreNavigationError([NSError errorWithDomain:domain code:102 userInfo:nil]),
            @"A WebKit frame-policy interruption is distinct from a failed page load");
    }
    for (NSNumber* code in @[@(NSURLErrorTimedOut), @(NSURLErrorNotConnectedToInternet),
        @(NSURLErrorServerCertificateUntrusted), @(NSURLErrorUnsupportedURL), @102]) {
        NSCAssert(!BHTWebSignInShouldIgnoreNavigationError([NSError errorWithDomain:NSURLErrorDomain code:code.integerValue userInfo:nil]),
            @"Do not hide genuine network, certificate, or unsupported-URL errors");
    }
    NSCAssert(!BHTWebSignInShouldIgnoreNavigationError([NSError errorWithDomain:@"OtherDomain" code:102 userInfo:nil]) &&
        !BHTWebSignInShouldIgnoreNavigationError([NSError errorWithDomain:@"OtherDomain" code:NSURLErrorCancelled userInfo:nil]) &&
        !BHTWebSignInShouldIgnoreNavigationError(nil), @"An error number alone cannot classify a navigation interruption");
    // On iPhone X can omit the desktop profile link or finish on a different
    // first-party route. A user must still be able to explicitly confirm.
    for (NSString* page in @[@"https://x.com/i/flow/login", @"https://x.com/", @"https://x.com/home", @"https://twitter.com/settings/account"]) {
        NSURL* URL = [NSURL URLWithString:page];
        NSCAssert(BHTWebSignInActionForState(URL, NO, NO, NO) == BHTWebSignInActionConfirm,
            @"Missing signed-in page detection must not disable manual confirmation on X");
        NSCAssert(BHTWebSignInActionForState(URL, YES, NO, YES) == BHTWebSignInActionUnavailable,
            @"A confirmation already in progress cannot be started twice");
        NSCAssert(BHTWebSignInActionForState(URL, NO, YES, NO) == BHTWebSignInActionReconnect,
            @"Keep the explicit saved-session retry action when connecting failed");
        NSCAssert(BHTWebSignInActionForState(URL, NO, YES, YES) == BHTWebSignInActionConfirm,
            @"A newly signed-in web account must take priority over the old retry");
    }
    for (NSString* page in @[@"about:blank", @"https://accounts.google.com/", @"https://appleid.apple.com/", @"https://x.com.evil.example/home", @"http://x.com/home"]) {
        NSCAssert(BHTWebSignInActionForState([NSURL URLWithString:page], NO, NO, YES) == BHTWebSignInActionUnavailable,
            @"A stale ready flag cannot enable cookie confirmation outside first-party HTTPS");
    }
    NSCAssert(BHTWebSignInActionForState(nil, NO, NO, NO) == BHTWebSignInActionUnavailable,
        @"Wait for a real X page instead of confirming a blank browser");
    NSCAssert(BHTWebSignInActionForState(nil, NO, YES, NO) == BHTWebSignInActionReconnect,
        @"A confirmed saved account can reconnect even if the new login page has not loaded");
    for (NSString* allowed in @[
             @"https://x.com/home",
             @"https://api.x.com/2/timeline",
             @"https://twitter.com/i/api/graphql/test",
             @"https://upload.twitter.com/1.1/media/upload.json",
             @"https://api.x.com:443/test",
         ]) {
        NSCAssert(BHTWebSessionURLIsAllowed(
            [NSURL URLWithString:allowed]),
            @"Expected an HTTPS first-party X URL");
    }
    for (NSString* blocked in @[
             @"http://x.com/home",
             @"https://x.com.evil.example/home",
             @"https://notx.com/home",
             @"https://twitter.com.evil.example/home",
             @"https://user@x.com/home",
             @"https://x.com:444/home",
             @"file:///tmp/x.com",
         ]) {
        NSCAssert(!BHTWebSessionURLIsAllowed(
            [NSURL URLWithString:blocked]),
            @"Credentials must fail closed outside first-party HTTPS");
    }

    NSCAssert([[BHTWebSessionNormalizedHandle(@" @DylanOlson6 ")
        lowercaseString] isEqualToString:@"dylanolson6"],
        @"Normalize a user-confirmed handle without changing its content");
    for (id invalid in @[
             @"", @"name-with-dash", @"sixteen_char_name", @"a/b",
             @"name.example", @123, NSNull.null
         ]) {
        NSCAssert(BHTWebSessionNormalizedHandle(invalid) == nil,
            @"Reject malformed account labels");
    }

    NSCAssert(BHTWebSessionUserIDFromTWID(@"u%3D123456789") ==
                  123456789,
              @"Decode X's percent-encoded twid cookie");
    NSCAssert(BHTWebSessionUserIDFromTWID(@"u=42") == 42,
              @"Accept X's decoded twid form");
    for (id invalid in @[
             @"", @"u%3D0", @"u%3D12x", @"-3",
             @"18446744073709551616", @123, NSNull.null
         ]) {
        NSCAssert(BHTWebSessionUserIDFromTWID(invalid) == 0,
            @"Reject malformed or overflowing user IDs");
    }

    NSCAssert(BHTWebSessionCredentialValueIsValid(
                  @"abcDEF1234567890._~-+%2B"),
              @"Accept bounded cookie-safe values");
    for (id invalid in @[
             @"short", @"abc;defgh", @"abc defgh", @"abc\r\ndefgh",
             @123, NSNull.null
         ]) {
        NSCAssert(!BHTWebSessionCredentialValueIsValid(invalid),
            @"Reject header delimiters and non-string credentials");
    }

    NSString* merged = BHTWebSessionCookieHeader(
        @"lang=en; auth_token=old; theme=dark; ct0=old; twid=u%3D4",
        @"newAuthValue123", @"newCsrfValue123", 99);
    NSCAssert([merged containsString:@"lang=en"] &&
              [merged containsString:@"theme=dark"],
              @"Preserve unrelated first-party cookies");
    NSCAssert(![merged containsString:@"=old"],
              @"Remove stale authentication cookie values");
    NSCAssert(countOccurrences(merged, @"auth_token=") == 1 &&
              countOccurrences(merged, @"ct0=") == 1 &&
              countOccurrences(merged, @"twid=") == 1,
              @"Emit exactly one value for each authentication cookie");
    NSCAssert([merged containsString:@"twid=u%3D99"],
              @"Encode the validated user ID in X's cookie form");
    puts("PASS: navigation interruption classification, mobile/manual sign-in confirmation, saved-session retries, and secure host, identifier, credential, and cookie validation");
}
