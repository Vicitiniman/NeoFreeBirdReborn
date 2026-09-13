// Tests the production login helpers with synthetic, non-account data.
static void testCompatibilityLogin(void) {
    NSString* domain = @"com.twitter.TFSTwitterAPICommand.error";
    NSString* key = @"TFSTwitterAPICommandError.apiErrorCode";
    NSError* missing = [NSError errorWithDomain:domain code:404
        userInfo:@{key: @239, @"TFSTwitterAPICommandError.message": @"Not exported"}];
    NSCAssert(BHTCompatibilityAPIErrorCode(missing) == 239,
              @"API reason and HTTP status must remain distinct");
    NSCAssert([BHTCompatibilityFailureCategory(missing, NO) isEqual:@"request_unavailable"],
              @"The reported 404 is not evidence of incorrect credentials");
    NSCAssert([BHTCompatibilityFailureCategory(
        [NSError errorWithDomain:domain code:410 userInfo:nil], NO)
        isEqual:@"request_unavailable"], @"410 must be classified separately");
    NSCAssert([BHTCompatibilityFailureCategory(
        [NSError errorWithDomain:domain code:429 userInfo:nil], NO)
        isEqual:@"rate_limited"], @"Do not suggest immediate retries after throttling");
    for (NSInteger status = 500; status <= 599; status++) {
        NSCAssert([BHTCompatibilityFailureCategory(
            [NSError errorWithDomain:domain code:status userInfo:nil], NO)
            isEqual:@"service_unavailable"], @"Server failures are not password rejections");
    }
    NSCAssert([BHTCompatibilityFailureCategory(
        [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil], NO)
        isEqual:@"network_failure"], @"Network failures remain distinct");
    NSCAssert([BHTCompatibilityFailureCategory(
        [NSError errorWithDomain:@"unrelated" code:404 userInfo:nil], NO)
        isEqual:@"authentication_rejected"], @"Only the audited domain uses HTTP codes");
    NSCAssert([BHTCompatibilityFailureCategory(nil, YES)
        isEqual:@"authentication_rejected_with_payload"], @"Preserve payload classification");
    NSCAssert(BHTCompatibilityAPIErrorCode(nil) == -1 &&
              BHTCompatibilityAPIErrorCode(@"not an error") == -1,
              @"Unknown failures must not be treated as API codes");
    for (id invalid in @[@"239", @YES, @-1, @100000, @2.5, NSNull.null, @[]]) {
        NSCAssert(BHTCompatibilityAPIErrorCode(
            [NSError errorWithDomain:domain code:403 userInfo:@{key: invalid}]) == -1,
            @"Only bounded integer API codes may leave the failure object");
    }
    NSCAssert(BHTCompatibilityAPIErrorCode(
        [NSError errorWithDomain:@"unrelated" code:403 userInfo:@{key:@239}]) == -1,
        @"Do not inspect unrelated error domains");
    NSCAssert(BHTCompatibilityAPIErrorCode(
        [NSError errorWithDomain:domain code:404 userInfo:nil]) == -1,
        @"Missing API reason remains unavailable");

    NSString* metrics = @"{ \"rf\": {\"test\": 1}, \"s\": \"synthetic-result\" }";
    NSCAssert([BHTCompatibilityValidatedMetrics(metrics) isEqual:metrics],
              @"Send the genuine result unchanged, preserving formatting");
    for (id invalid in @[@"", @"{}", @"[]", @"null", @"invalid", @"\"text\"", @"3", @{}, NSNull.null]) {
        NSCAssert(BHTCompatibilityValidatedMetrics(invalid) == nil,
                  @"Do not send malformed callback data as verification");
    }
    NSCAssert(BHTCompatibilityValidatedMetrics(nil) == nil, @"Missing metrics keep the nil fallback");
    NSString* oversized = [@"a" stringByPaddingToLength:65537 withString:@"a" startingAtIndex:0];
    NSCAssert(BHTCompatibilityValidatedMetrics(oversized) == nil, @"Bound the callback length");
    NSString* unicode = [@"\u00e9" stringByPaddingToLength:40000 withString:@"\u00e9" startingAtIndex:0];
    NSCAssert(BHTCompatibilityValidatedMetrics([NSString stringWithFormat:@"{\"s\":\"%@\"}", unicode]) == nil,
              @"Bound UTF-8 bytes as well as UTF-16 length");
    puts("PASS: compatibility verification validation, HTTP/API error separation, and bounded diagnostics");
}
