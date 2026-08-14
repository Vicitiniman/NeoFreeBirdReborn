#import "Reply/BHTDetailedReplyDiagnostics.h"

#import "Core/BHTSettings.h"

#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <stdint.h>
#import <stdlib.h>

static const NSTimeInterval BHTDetailedReplyArmLifetime = 10.0 * 60.0;
static const NSTimeInterval BHTDetailedReplyCollectionLifetime = 90.0;
static const NSTimeInterval BHTDetailedReplyExportLifetime = 10.0 * 60.0;
static const NSUInteger BHTDetailedReplyResponseLimit = 256 * 1024;
static const NSUInteger BHTDetailedReplyMaximumDepth = 8;
static const NSUInteger BHTDetailedReplyMaximumDictionaryKeys = 32;
static const NSUInteger BHTDetailedReplyMaximumArrayElements = 16;
static const NSUInteger BHTDetailedReplyMaximumStringLength = 2048;
static const NSUInteger BHTDetailedWriteRequestLimit = 128 * 1024;
static const NSUInteger BHTDetailedWriteMaximumSchemaDepth = 8;
static const NSUInteger BHTDetailedWriteMaximumSchemaKeys = 64;
static const NSUInteger BHTDetailedWriteMaximumArraySamples = 4;

typedef NS_ENUM(NSUInteger, BHTDetailedWriteKind) {
    BHTDetailedWriteKindUnknown = 0,
    BHTDetailedWriteKindStandalone,
    BHTDetailedWriteKindReply,
};

@interface BHTDetailedWriteTaskTag : NSObject
@property(nonatomic, copy) NSString* writeKind;
@property(nonatomic) NSUInteger captureEpoch;
@property(nonatomic) NSTimeInterval startedAt;
@end

@implementation BHTDetailedWriteTaskTag
@end

static BOOL BHTDetailedReplyArmed;
static NSTimeInterval BHTDetailedReplyArmedAt;
static NSTimeInterval BHTDetailedReplyCaptureStartedAt;
static NSUInteger BHTDetailedReplySessionGeneration;
static NSString* BHTDetailedReplyCaptureState = @"idle";
static NSDictionary* BHTDetailedReplyCapture;
static NSUInteger BHTDetailedReplyRedactionCount;
static NSUInteger BHTDetailedReplyTruncationCount;
static BOOL BHTDetailedReplyResponseAccessorsObserved;
static NSUInteger BHTDetailedReplyCaptureEpoch;
static atomic_bool BHTDetailedWriteNetworkCaptureOpen;
static atomic_uint BHTDetailedWritePendingCompositionKind;
static atomic_bool BHTDetailedApplicationBindingHookAvailable;
static char BHTDetailedWriteTaskTagKey;
static __weak id BHTDetailedReplyComposerAccount;
static __weak id BHTDetailedCompatibilityAccount;
static __weak id BHTDetailedActiveCompositionAccount;
static NSDictionary* BHTDetailedPendingApplicationToken;

static NSObject* BHTDetailedReplyLock(void) {
    static NSObject* lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static NSTimeInterval BHTDetailedReplyNow(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

static void BHTDetailedReplySetPreference(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults
        setBool:enabled
         forKey:@"detailed_reply_diagnostics"];
}

static void BHTDetailedReplyExpireCaptureLocked(void) {
    BHTDetailedReplyCaptureEpoch++;
    BHTDetailedReplyArmed = NO;
    BHTDetailedReplyArmedAt = 0;
    BHTDetailedReplySessionGeneration = 0;
    BHTDetailedReplyCaptureStartedAt = 0;
    BHTDetailedReplyCapture = nil;
    BHTDetailedReplyRedactionCount = 0;
    BHTDetailedReplyTruncationCount = 0;
    BHTDetailedReplyResponseAccessorsObserved = NO;
    BHTDetailedReplyComposerAccount = nil;
    BHTDetailedActiveCompositionAccount = nil;
    BHTDetailedPendingApplicationToken = nil;
    atomic_store_explicit(
        &BHTDetailedWriteNetworkCaptureOpen, false,
        memory_order_release);
    atomic_store_explicit(
        &BHTDetailedWritePendingCompositionKind,
        BHTDetailedWriteKindUnknown, memory_order_release);
    BHTDetailedReplyCaptureState = @"captureExpiredAndCleared";
    BHTDetailedReplySetPreference(NO);
}

static void BHTDetailedReplyScheduleArmExpiryLocked(void) {
    NSUInteger expectedEpoch = BHTDetailedReplyCaptureEpoch;
    NSTimeInterval expectedArmedAt = BHTDetailedReplyArmedAt;
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(BHTDetailedReplyArmLifetime * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            @synchronized(BHTDetailedReplyLock()) {
                if (expectedEpoch != BHTDetailedReplyCaptureEpoch ||
                    expectedArmedAt <= 0 ||
                    expectedArmedAt != BHTDetailedReplyArmedAt ||
                    !BHTDetailedReplyArmed) {
                    return;
                }
                BHTDetailedReplyArmed = NO;
                atomic_store_explicit(
                    &BHTDetailedWriteNetworkCaptureOpen, false,
                    memory_order_release);
                atomic_store_explicit(
                    &BHTDetailedWritePendingCompositionKind,
                    BHTDetailedWriteKindUnknown, memory_order_release);
                BHTDetailedActiveCompositionAccount = nil;
                BHTDetailedPendingApplicationToken = nil;
                BHTDetailedReplyCaptureState = @"armExpired";
                BHTDetailedReplySetPreference(NO);
            }
        });
}

static void BHTDetailedReplyScheduleExpiryLocked(void) {
    NSUInteger expectedEpoch = BHTDetailedReplyCaptureEpoch;
    NSTimeInterval expectedStartedAt = BHTDetailedReplyCaptureStartedAt;
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            (int64_t)(BHTDetailedReplyExportLifetime * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            @synchronized(BHTDetailedReplyLock()) {
                if (expectedEpoch != BHTDetailedReplyCaptureEpoch ||
                    expectedStartedAt <= 0 ||
                    expectedStartedAt !=
                        BHTDetailedReplyCaptureStartedAt) {
                    return;
                }
                BHTDetailedReplyExpireCaptureLocked();
            }
        });
}

static void BHTDetailedReplyPruneLocked(void) {
    NSTimeInterval now = BHTDetailedReplyNow();
    if (BHTDetailedReplyArmed &&
        now - BHTDetailedReplyArmedAt > BHTDetailedReplyArmLifetime) {
        BHTDetailedReplyArmed = NO;
        atomic_store_explicit(
            &BHTDetailedWriteNetworkCaptureOpen, false,
            memory_order_release);
        atomic_store_explicit(
            &BHTDetailedWritePendingCompositionKind,
            BHTDetailedWriteKindUnknown, memory_order_release);
        BHTDetailedActiveCompositionAccount = nil;
        BHTDetailedPendingApplicationToken = nil;
        BHTDetailedReplyCaptureState = @"armExpired";
        BHTDetailedReplySetPreference(NO);
    }
    NSTimeInterval captureAge =
        BHTDetailedReplyCaptureStartedAt > 0
            ? now - BHTDetailedReplyCaptureStartedAt
            : 0;
    if (captureAge > BHTDetailedReplyExportLifetime) {
        // Personal reply data is retained only long enough for the tester to
        // return to Debug settings and explicitly share the detailed report.
        BHTDetailedReplyExpireCaptureLocked();
    } else if (BHTDetailedReplySessionGeneration != 0 &&
               captureAge > BHTDetailedReplyCollectionLifetime) {
        // Stop accepting late callbacks after 90 seconds, while allowing the
        // completed one-shot report to be exported for up to ten minutes.
        BHTDetailedReplySessionGeneration = 0;
        if (BHTDetailedReplyCapture) {
            BHTDetailedReplyCaptureState =
                @"captureCollectionClosedAwaitingExport";
        } else {
            BHTDetailedReplyCaptureEpoch++;
            BHTDetailedReplyCaptureStartedAt = 0;
            BHTDetailedReplyRedactionCount = 0;
            BHTDetailedReplyTruncationCount = 0;
            BHTDetailedReplyResponseAccessorsObserved = NO;
            BHTDetailedReplyCaptureState = @"captureExpiredWithoutData";
        }
    }
}

static BOOL BHTDetailedReplyMethodReturnsObjectWithNoArguments(
    Class cls,
    SEL selector) {
    if (!cls || !selector) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* type = returnType;
    while (type &&
           (*type == 'r' || *type == 'n' || *type == 'N' ||
            *type == 'o' || *type == 'O' || *type == 'R' ||
            *type == 'V')) {
        type++;
    }
    return type && type[0] == '@' && type[1] == '\0';
}

static NSString* BHTDetailedReplyNormalizedKey(NSString* key) {
    if (![key isKindOfClass:NSString.class]) return @"";
    NSMutableString* normalized = [NSMutableString string];
    NSString* lowercase = key.lowercaseString;
    NSCharacterSet* allowed = NSCharacterSet.alphanumericCharacterSet;
    for (NSUInteger index = 0; index < lowercase.length; index++) {
        unichar character = [lowercase characterAtIndex:index];
        if ([allowed characterIsMember:character]) {
            [normalized appendFormat:@"%C", character];
        }
    }
    return normalized;
}

static BOOL BHTDetailedReplyShouldRedactKey(NSString* key) {
    NSString* normalized = BHTDetailedReplyNormalizedKey(key);
    if (normalized.length == 0) return NO;
    NSArray<NSString*>* denied = @[
        @"authorization", @"cookie", @"setcookie", @"password",
        @"passwd", @"secret", @"clientsecret", @"accesstoken",
        @"refreshtoken", @"oauthtoken", @"bearertoken",
        @"guesttoken", @"knowndevicetoken", @"xcsrftoken",
        @"csrftoken", @"authtoken", @"token", @"header",
        @"attestation", @"ct0"
    ];
    for (NSString* fragment in denied) {
        if ([normalized containsString:fragment]) return YES;
    }
    return NO;
}

static NSString* BHTDetailedReplyScrubString(
    NSString* value,
    NSUInteger* redactions,
    NSUInteger* truncations) {
    if (![value isKindOfClass:NSString.class]) return @"";
    NSMutableString* result = [value mutableCopy];
    static NSArray<NSRegularExpression*>* patterns;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray* compiled = [NSMutableArray array];
        NSArray* sources = @[
            @"(?i)\\bBearer\\s+[^\\s,;]+",
            @"(?i)\\b(auth[_-]?token|access[_-]?token|refresh[_-]?token|oauth[_-]?token|guest[_-]?token|token|ct0|password|passwd|client[_-]?secret)\\s*[:=]\\s*[^\\s,;&]+",
            @"(?i)\\b(authorization|cookie|set-cookie)\\s*[:=]\\s*[^\\r\\n]+"
        ];
        for (NSString* source in sources) {
            NSRegularExpression* expression =
                [NSRegularExpression regularExpressionWithPattern:source
                                                          options:0
                                                            error:nil];
            if (expression) [compiled addObject:expression];
        }
        patterns = [compiled copy];
    });
    for (NSRegularExpression* expression in patterns) {
        NSUInteger matches = [expression
            numberOfMatchesInString:result
                            options:0
                              range:NSMakeRange(0, result.length)];
        if (matches > 0) {
            [expression replaceMatchesInString:result
                                       options:0
                                         range:NSMakeRange(0, result.length)
                                  withTemplate:@"<redacted credential>"];
            if (redactions) *redactions += matches;
        }
    }
    if (result.length > BHTDetailedReplyMaximumStringLength) {
        [result deleteCharactersInRange:NSMakeRange(
            BHTDetailedReplyMaximumStringLength,
            result.length - BHTDetailedReplyMaximumStringLength)];
        [result appendString:@"...<truncated>"];
        if (truncations) (*truncations)++;
    }
    return [result copy];
}

static BOOL BHTDetailedReplyDescriptionDeniedForClassName(
    NSString* className) {
    NSString* lowercase = className.lowercaseString;
    for (NSString* fragment in
         @[@"account", @"credential", @"token", @"cookie", @"session",
           @"urlrequest", @"urlresponse"]) {
        if ([lowercase containsString:fragment]) return YES;
    }
    return NO;
}

static id BHTDetailedReplySanitizedObject(
    id value,
    NSUInteger depth,
    NSUInteger* redactions,
    NSUInteger* truncations);
static NSString* BHTDetailedWriteSafeSchemaKey(id rawKey);

static NSDictionary* BHTDetailedReplySanitizedError(
    NSError* error,
    NSUInteger depth,
    NSUInteger* redactions,
    NSUInteger* truncations) {
    NSMutableDictionary* result = [@{
        @"class": NSStringFromClass(error.class) ?: @"NSError",
        @"domain": BHTDetailedReplyScrubString(
            error.domain ?: @"", redactions, truncations),
        @"code": @(error.code),
        @"localizedDescription": BHTDetailedReplyScrubString(
            error.localizedDescription ?: @"", redactions, truncations),
    } mutableCopy];
    if (error.localizedFailureReason.length > 0) {
        result[@"localizedFailureReason"] = BHTDetailedReplyScrubString(
            error.localizedFailureReason, redactions, truncations);
    }
    if (error.localizedRecoverySuggestion.length > 0) {
        result[@"localizedRecoverySuggestion"] = BHTDetailedReplyScrubString(
            error.localizedRecoverySuggestion, redactions, truncations);
    }
    id userInfo = BHTDetailedReplySanitizedObject(
        error.userInfo, depth + 1, redactions, truncations);
    if (userInfo) result[@"userInfo"] = userInfo;
    return [result copy];
}

static id BHTDetailedReplySanitizedObject(
    id value,
    NSUInteger depth,
    NSUInteger* redactions,
    NSUInteger* truncations) {
    if (!value || value == NSNull.null) return NSNull.null;
    if (depth > BHTDetailedReplyMaximumDepth) {
        if (truncations) (*truncations)++;
        return @"<maximum depth reached>";
    }
    if ([value isKindOfClass:NSString.class]) {
        return BHTDetailedReplyScrubString(
            value, redactions, truncations);
    }
    if ([value isKindOfClass:NSNumber.class]) {
        double numericValue = [(NSNumber*)value doubleValue];
        if (isfinite(numericValue)) return value;
        if (truncations) (*truncations)++;
        return @"<non-finite number omitted>";
    }
    if ([value isKindOfClass:NSError.class]) {
        return BHTDetailedReplySanitizedError(
            value, depth, redactions, truncations);
    }
    if ([value isKindOfClass:NSURL.class]) {
        if (redactions) (*redactions)++;
        return @"<redacted URL>";
    }
    if ([value isKindOfClass:NSData.class]) {
        return @{
            @"class": @"NSData",
            @"byteCount": @([(NSData*)value length]),
            @"contentsRetained": @NO,
        };
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary* dictionary = value;
        NSArray* keys = [dictionary.allKeys
            sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
                return [BHTDetailedWriteSafeSchemaKey(left)
                    compare:BHTDetailedWriteSafeSchemaKey(right)
                   options:NSCaseInsensitiveSearch];
            }];
        NSMutableDictionary* result = [NSMutableDictionary dictionary];
        NSUInteger count = MIN(
            keys.count, BHTDetailedReplyMaximumDictionaryKeys);
        for (NSUInteger index = 0; index < count; index++) {
            id rawKey = keys[index];
            NSString* key = [rawKey isKindOfClass:NSString.class]
                ? rawKey
                : [rawKey description];
            key = BHTDetailedReplyScrubString(
                key ?: @"<key>", redactions, truncations);
            if (BHTDetailedReplyShouldRedactKey(key)) {
                result[key] = @"<redacted credential value>";
                if (redactions) (*redactions)++;
                continue;
            }
            result[key] = BHTDetailedReplySanitizedObject(
                dictionary[rawKey], depth + 1,
                redactions, truncations) ?: NSNull.null;
        }
        if (keys.count > count) {
            result[@"<truncatedKeys>"] = @(keys.count - count);
            if (truncations) (*truncations)++;
        }
        return [result copy];
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSArray* array = value;
        NSUInteger count = MIN(
            array.count, BHTDetailedReplyMaximumArrayElements);
        NSMutableArray* result = [NSMutableArray arrayWithCapacity:count];
        for (NSUInteger index = 0; index < count; index++) {
            [result addObject:BHTDetailedReplySanitizedObject(
                array[index], depth + 1,
                redactions, truncations) ?: NSNull.null];
        }
        if (array.count > count) {
            [result addObject:@{
                @"truncatedElements": @(array.count - count)
            }];
            if (truncations) (*truncations)++;
        }
        return [result copy];
    }

    NSString* className = NSStringFromClass([value class]) ?: @"unknown";
    NSMutableDictionary* result = [@{ @"class": className } mutableCopy];
    if (BHTDetailedReplyDescriptionDeniedForClassName(className)) {
        result[@"description"] = @"<omitted for credential safety>";
        if (redactions) (*redactions)++;
        return [result copy];
    }
    @try {
        result[@"description"] = BHTDetailedReplyScrubString(
            [value description] ?: @"", redactions, truncations);
        if ([value respondsToSelector:@selector(debugDescription)]) {
            result[@"debugDescription"] = BHTDetailedReplyScrubString(
                [value debugDescription] ?: @"",
                redactions, truncations);
        }
    } @catch (__unused NSException* exception) {
        result[@"description"] = @"<description raised an exception>";
    }
    return [result copy];
}

static NSDictionary* BHTDetailedReplyObjectSummary(
    id value,
    NSUInteger* redactions,
    NSUInteger* truncations) {
    if (!value) return @{ @"present": @NO };
    return @{
        @"present": @YES,
        @"value": BHTDetailedReplySanitizedObject(
            value, 0, redactions, truncations) ?: NSNull.null,
    };
}

static NSData* BHTDetailedReplyResponseData(
    id response,
    BOOL* accessorsObserved) {
    if (accessorsObserved) *accessorsObserved = NO;
    if (!response) return nil;
    SEL infoSelector = NSSelectorFromString(@"info");
    if (!BHTDetailedReplyMethodReturnsObjectWithNoArguments(
            [response class], infoSelector)) {
        return nil;
    }
    @try {
        id info = ((id (*)(id, SEL))objc_msgSend)(
            response, infoSelector);
        SEL dataSelector = NSSelectorFromString(@"data");
        if (!info ||
            !BHTDetailedReplyMethodReturnsObjectWithNoArguments(
                [info class], dataSelector)) {
            return nil;
        }
        if (accessorsObserved) *accessorsObserved = YES;
        id data = ((id (*)(id, SEL))objc_msgSend)(
            info, dataSelector);
        return [data isKindOfClass:NSData.class] ? data : nil;
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

static uint64_t BHTDetailedWriteFNV1a64(NSString* value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) {
        return 0;
    }
    NSData* data = [value dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t* bytes = data.bytes;
    uint64_t hash = UINT64_C(14695981039346656037);
    for (NSUInteger index = 0; index < data.length; index++) {
        hash ^= bytes[index];
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

static NSString* BHTDetailedWriteFingerprint(NSString* value) {
    uint64_t hash = BHTDetailedWriteFNV1a64(value);
    if (hash == 0) return nil;
    return [NSString stringWithFormat:@"fnv1a64:%016llx",
                                      (unsigned long long)hash];
}

static NSSet<NSString*>* BHTDetailedWriteAllowedSchemaKeys(void) {
    static NSSet<NSString*>* keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // These are fixed GraphQL/CreateTweet structure names, never values.
        // Every other dictionary key collapses to one non-reversible label.
        keys = [NSSet setWithArray:@[
            @"tweet_text", @"tweetText", @"dark_request", @"media",
            @"media_entities", @"media_id", @"tagged_users",
            @"possibly_sensitive", @"semantic_annotation_ids",
            @"disallowed_reply_options", @"reply",
            @"in_reply_to_tweet_id", @"inReplyToTweetId",
            @"exclude_reply_user_ids", @"excludeReplyUserIds",
            @"attachment_url", @"card_uri",
            @"conversation_control", @"community_id",
            @"data", @"errors", @"create_tweet",
            @"createTweet", @"create_tweet_with_undo",
            @"tweet_results", @"tweetResults", @"result",
            @"rest_id", @"legacy", @"core", @"user_results",
            @"edit_control", @"message", @"code", @"extensions",
            @"name", @"kind", @"source", @"path", @"__typename",
        ]];
    });
    return keys;
}

static NSString* BHTDetailedWriteCountBucket(NSUInteger count) {
    if (count == 0) return @"zero";
    if (count == 1) return @"one";
    if (count <= 4) return @"twoToFour";
    if (count <= 16) return @"fiveToSixteen";
    if (count <= 64) return @"seventeenToSixtyFour";
    return @"overSixtyFour";
}

static NSString* BHTDetailedWriteValueType(id value) {
    if (!value || value == NSNull.null) return @"null";
    if ([value isKindOfClass:NSString.class]) return @"string";
    if ([value isKindOfClass:NSNumber.class]) {
        return CFGetTypeID((__bridge CFTypeRef)value) ==
                       CFBooleanGetTypeID()
            ? @"boolean"
            : @"number";
    }
    if ([value isKindOfClass:NSDictionary.class]) return @"object";
    if ([value isKindOfClass:NSArray.class]) return @"array";
    return @"other";
}

static NSString* BHTDetailedWriteSafeSchemaKey(id rawKey) {
    if (![rawKey isKindOfClass:NSString.class]) {
        return @"<nonStringField>";
    }
    NSString* key = rawKey;
    if ([BHTDetailedWriteAllowedSchemaKeys() containsObject:key]) {
        return key;
    }
    return @"<opaqueField>";
}

static id BHTDetailedWriteSchemaForValue(
    id value,
    NSUInteger depth,
    NSMutableArray<NSString*>* fieldPaths,
    NSString* pathPrefix,
    NSUInteger* truncations) {
    if (depth > BHTDetailedWriteMaximumSchemaDepth) {
        if (truncations) (*truncations)++;
        return @{ @"type": @"depthLimit" };
    }
    NSString* type = BHTDetailedWriteValueType(value);
    if ([type isEqualToString:@"null"]) {
        return @{ @"type": @"null" };
    }
    if ([type isEqualToString:@"string"]) {
        return @{
            @"type": @"string",
            @"contentsRetained": @NO,
        };
    }
    if ([type isEqualToString:@"boolean"]) {
        return @{
            @"type": @"boolean",
            @"valueRetained": @NO,
        };
    }
    if ([type isEqualToString:@"number"]) {
        return @{ @"type": @"number", @"valueRetained": @NO };
    }
    if ([type isEqualToString:@"array"]) {
        NSArray* array = value;
        NSMutableOrderedSet<NSString*>* elementTypes =
            [NSMutableOrderedSet orderedSet];
        NSMutableArray* samples = [NSMutableArray array];
        NSUInteger sampleCount = MIN(
            array.count, BHTDetailedWriteMaximumArraySamples);
        for (NSUInteger index = 0; index < sampleCount; index++) {
            id item = array[index];
            [elementTypes addObject:BHTDetailedWriteValueType(item)];
            if (samples.count < 2 &&
                ([item isKindOfClass:NSDictionary.class] ||
                 [item isKindOfClass:NSArray.class])) {
                [samples addObject:BHTDetailedWriteSchemaForValue(
                    item, depth + 1, fieldPaths,
                    [pathPrefix stringByAppendingString:@"[]"],
                    truncations)];
            }
        }
        if (array.count > sampleCount && truncations) {
            (*truncations)++;
        }
        NSMutableDictionary* result = [@{
            @"type": @"array",
            @"countBucket": BHTDetailedWriteCountBucket(array.count),
            @"elementTypes": elementTypes.array ?: @[],
            @"valuesRetained": @NO,
        } mutableCopy];
        if (samples.count > 0) {
            result[@"sampleSchemas"] = [samples copy];
        }
        return [result copy];
    }
    if ([type isEqualToString:@"object"]) {
        NSDictionary* dictionary = value;
        NSArray* keys = [dictionary.allKeys
            sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
                return [[left description]
                    compare:[right description]
                   options:NSCaseInsensitiveSearch];
            }];
        NSUInteger count = MIN(
            keys.count, BHTDetailedWriteMaximumSchemaKeys);
        NSMutableDictionary* fields =
            [NSMutableDictionary dictionaryWithCapacity:count];
        for (NSUInteger index = 0; index < count; index++) {
            id rawKey = keys[index];
            NSString* safeKey = BHTDetailedWriteSafeSchemaKey(rawKey);
            NSString* path = pathPrefix.length > 0
                ? [NSString stringWithFormat:@"%@.%@", pathPrefix, safeKey]
                : safeKey;
            if (fieldPaths.count < 256) {
                [fieldPaths addObject:path];
            } else if (truncations) {
                (*truncations)++;
            }
            id fieldSchema = BHTDetailedWriteSchemaForValue(
                dictionary[rawKey], depth + 1, fieldPaths, path,
                truncations);
            if (!fields[safeKey]) {
                fields[safeKey] = fieldSchema;
            } else {
                fields[@"<duplicateSanitizedField>"] = fieldSchema;
            }
        }
        if (keys.count > count && truncations) {
            (*truncations)++;
        }
        return @{
            @"type": @"object",
            @"fieldCountBucket":
                BHTDetailedWriteCountBucket(keys.count),
            @"fields": [fields copy],
            @"valuesRetained": @NO,
        };
    }
    return @{
        @"type": @"other",
        @"class": NSStringFromClass([value class]) ?: @"unknown",
        @"descriptionRetained": @NO,
    };
}

static NSString* BHTDetailedWriteFormDecode(NSString* value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString* plusDecoded = [value stringByReplacingOccurrencesOfString:@"+"
                                                              withString:@" "];
    return plusDecoded.stringByRemovingPercentEncoding;
}

static NSDictionary* BHTDetailedWriteEnvelopeFromData(
    NSData* data,
    NSString** state,
    NSUInteger* truncations) {
    if (state) *state = @"bodyUnavailable";
    if (![data isKindOfClass:NSData.class] || data.length == 0) {
        return nil;
    }
    if (data.length > BHTDetailedWriteRequestLimit) {
        if (state) *state = @"overLimitOmitted";
        if (truncations) (*truncations)++;
        return nil;
    }
    id JSON = [NSJSONSerialization JSONObjectWithData:data
                                              options:0
                                                error:nil];
    if ([JSON isKindOfClass:NSDictionary.class]) {
        if (state) *state = @"jsonParsedToSchema";
        return JSON;
    }

    NSString* form = [[NSString alloc] initWithData:data
                                            encoding:NSUTF8StringEncoding];
    if (form.length == 0) {
        if (state) *state = @"unsupportedEncodingOmitted";
        return nil;
    }
    NSMutableDictionary* envelope = [NSMutableDictionary dictionary];
    for (NSString* pair in [form componentsSeparatedByString:@"&"]) {
        NSRange equals = [pair rangeOfString:@"="];
        NSString* encodedKey = equals.location == NSNotFound
            ? pair
            : [pair substringToIndex:equals.location];
        NSString* key = BHTDetailedWriteFormDecode(encodedKey);
        if (![key isEqualToString:@"variables"] &&
            ![key isEqualToString:@"features"] &&
            ![key isEqualToString:@"queryId"]) {
            continue;
        }
        NSString* encodedValue = equals.location == NSNotFound
            ? @""
            : [pair substringFromIndex:equals.location + 1];
        NSString* decodedValue = BHTDetailedWriteFormDecode(encodedValue);
        if ([key isEqualToString:@"queryId"]) {
            envelope[key] = decodedValue ?: @"";
            continue;
        }
        NSData* nestedData =
            [decodedValue dataUsingEncoding:NSUTF8StringEncoding];
        id nestedJSON = nestedData
            ? [NSJSONSerialization JSONObjectWithData:nestedData
                                               options:0
                                                 error:nil]
            : nil;
        envelope[key] = nestedJSON ?: NSNull.null;
    }
    if (envelope.count > 0) {
        if (state) *state = @"formGraphQLFieldsParsedToSchema";
        return [envelope copy];
    }
    if (state) *state = @"nonGraphQLBodyOmitted";
    return nil;
}

static BOOL BHTDetailedWriteEvidenceValueIsPresent(id value) {
    if (!value || value == NSNull.null) return NO;
    if ([value isKindOfClass:NSString.class]) {
        return [(NSString*)value length] > 0;
    }
    if ([value isKindOfClass:NSArray.class]) {
        return [(NSArray*)value count] > 0;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        return [(NSDictionary*)value count] > 0;
    }
    if ([value isKindOfClass:NSNumber.class]) {
        return [(NSNumber*)value doubleValue] != 0;
    }
    return YES;
}

static BOOL BHTDetailedWriteReplyEvidence(
    id value,
    NSUInteger depth,
    NSMutableArray<NSString*>* evidence,
    NSString* prefix) {
    if (depth > BHTDetailedWriteMaximumSchemaDepth) return NO;
    BOOL found = NO;
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary* dictionary = value;
        for (id rawKey in dictionary) {
            NSString* safeKey = BHTDetailedWriteSafeSchemaKey(rawKey);
            NSString* normalized =
                BHTDetailedReplyNormalizedKey(safeKey);
            NSString* path = prefix.length > 0
                ? [NSString stringWithFormat:@"%@.%@", prefix, safeKey]
                : safeKey;
            id child = dictionary[rawKey];
            BOOL replyField =
                [normalized isEqualToString:@"reply"] ||
                [normalized isEqualToString:@"inreplytotweetid"] ||
                [normalized isEqualToString:@"excludereplyuserids"];
            if (replyField &&
                BHTDetailedWriteEvidenceValueIsPresent(child)) {
                found = YES;
                if (evidence.count < 16) [evidence addObject:path];
            }
            found = BHTDetailedWriteReplyEvidence(
                        child, depth + 1, evidence, path) ||
                    found;
        }
    } else if ([value isKindOfClass:NSArray.class]) {
        NSArray* array = value;
        NSUInteger count = MIN(
            array.count, BHTDetailedWriteMaximumArraySamples);
        for (NSUInteger index = 0; index < count; index++) {
            found = BHTDetailedWriteReplyEvidence(
                        array[index], depth + 1, evidence,
                        [prefix stringByAppendingString:@"[]"]) ||
                    found;
        }
    }
    return found;
}

static NSDictionary* BHTDetailedWriteFeatureShape(id features) {
    if (![features isKindOfClass:NSDictionary.class]) {
        return @{
            @"present": @(features != nil && features != NSNull.null),
            @"state": @"notAnObject",
        };
    }
    NSDictionary* dictionary = features;
    NSArray* keys = [dictionary.allKeys
        sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
            return [BHTDetailedWriteSafeSchemaKey(left)
                compare:BHTDetailedWriteSafeSchemaKey(right)
               options:NSCaseInsensitiveSearch];
        }];
    NSUInteger count = MIN(
        keys.count, BHTDetailedWriteMaximumSchemaKeys);
    NSMutableDictionary* flags = [NSMutableDictionary dictionary];
    NSUInteger opaqueTrueCount = 0;
    NSUInteger opaqueFalseCount = 0;
    NSUInteger opaqueNonBooleanCount = 0;
    for (NSUInteger index = 0; index < count; index++) {
        id rawKey = keys[index];
        NSString* key = BHTDetailedWriteSafeSchemaKey(rawKey);
        id value = dictionary[rawKey];
        NSString* type = BHTDetailedWriteValueType(value);
        BOOL opaqueKey = [key isEqualToString:@"<opaqueField>"] ||
            [key isEqualToString:@"<nonStringField>"];
        if (opaqueKey) {
            if ([type isEqualToString:@"boolean"]) {
                if ([(NSNumber*)value boolValue]) {
                    opaqueTrueCount++;
                } else {
                    opaqueFalseCount++;
                }
            } else {
                opaqueNonBooleanCount++;
            }
            continue;
        }
        if ([type isEqualToString:@"boolean"]) {
            flags[key] = @([(NSNumber*)value boolValue]);
        } else {
            flags[key] = [NSString stringWithFormat:@"nonBoolean:%@", type];
        }
    }
    return @{
        @"present": @YES,
        @"state": @"keysAndBooleanValuesOnly",
        @"countBucket": BHTDetailedWriteCountBucket(keys.count),
        @"flags": [flags copy],
        @"opaqueTrueCountBucket":
            BHTDetailedWriteCountBucket(opaqueTrueCount),
        @"opaqueFalseCountBucket":
            BHTDetailedWriteCountBucket(opaqueFalseCount),
        @"opaqueNonBooleanCountBucket":
            BHTDetailedWriteCountBucket(opaqueNonBooleanCount),
        @"truncated": @(keys.count > count),
    };
}

static NSDictionary* BHTDetailedWriteAccountContext(
    BHTDetailedWriteKind kind,
    id active) {
    id replyAccount = nil;
    id compatibilityAccount = nil;
    @synchronized(BHTDetailedReplyLock()) {
        replyAccount = BHTDetailedReplyComposerAccount;
        compatibilityAccount = BHTDetailedCompatibilityAccount;
    }
    BOOL replyComparisonAvailable =
        kind == BHTDetailedWriteKindReply && active && replyAccount;
    BOOL compatibilityComparisonAvailable =
        active && compatibilityAccount;
    return @{
        @"activeCompositionAccountAvailable": @(active != nil),
        @"replyComposerAccountAvailable": @(replyAccount != nil),
        @"compositionAccountMatchesReplyComposerAccount":
            replyComparisonAvailable
                ? @((__bridge void*)active == (__bridge void*)replyAccount)
                : NSNull.null,
        @"recentCompatibilityAccountAvailable":
            @(compatibilityAccount != nil),
        @"compositionAccountMatchesMostRecentCompatibilityAccount":
            compatibilityComparisonAvailable
                ? @((__bridge void*)active ==
                    (__bridge void*)compatibilityAccount)
                : NSNull.null,
        @"comparisonMethod": @"processLocalObjectIdentityOnly",
        @"capturedAtCompositionUISendSeam": @YES,
        @"privateUIQueriedFromNetworkCallback": @NO,
        @"accountPropertiesRead": @NO,
        @"accountObjectsRetained": @NO,
        @"requestIdentityBound": @NO,
    };
}

static BOOL BHTDetailedWriteURLIsEligible(
    NSURL* URL,
    NSString** operation,
    NSString** queryFingerprint,
    NSString** hostCategory) {
    if (![URL isKindOfClass:NSURL.class] ||
        ![URL.scheme.lowercaseString isEqualToString:@"https"]) {
        return NO;
    }
    NSString* host = URL.host.lowercaseString;
    NSString* category = nil;
    if ([host isEqualToString:@"api.twitter.com"] ||
        [host isEqualToString:@"api.x.com"]) {
        category = @"api";
    } else if ([host isEqualToString:@"twitter.com"] ||
               [host isEqualToString:@"www.twitter.com"] ||
               [host isEqualToString:@"x.com"] ||
               [host isEqualToString:@"www.x.com"]) {
        category = @"web";
    } else {
        return NO;
    }
    NSArray<NSString*>* components = URL.pathComponents;
    NSString* operationValue = URL.lastPathComponent;
    if (![operationValue isEqualToString:@"CreateTweet"] &&
        ![operationValue isEqualToString:@"CreateTweetWithUndo"]) {
        return NO;
    }
    NSString* persistedID = components.count >= 2
        ? components[components.count - 2]
        : nil;
    if ([persistedID isEqualToString:@"graphql"] ||
        [persistedID isEqualToString:@"/"]) {
        persistedID = nil;
    }
    if (operation) {
        *operation = [operationValue isEqualToString:@"CreateTweet"]
            ? @"createTweet"
            : @"createTweetWithUndo";
    }
    if (queryFingerprint) {
        *queryFingerprint = BHTDetailedWriteFingerprint(persistedID);
    }
    if (hostCategory) *hostCategory = category;
    return YES;
}

BOOL BHTDetailedReplyDiagnosticsRequestIsEligible(NSURLRequest* request) {
    if (!atomic_load_explicit(
            &BHTDetailedWriteNetworkCaptureOpen, memory_order_acquire)) {
        return NO;
    }
    if (![request isKindOfClass:NSURLRequest.class] ||
        ![request.HTTPMethod.uppercaseString isEqualToString:@"POST"] ||
        !BHTDetailedWriteURLIsEligible(
            request.URL, NULL, NULL, NULL)) {
        return NO;
    }
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        return BHTDetailedReplyArmed &&
            atomic_load_explicit(
                &BHTDetailedWriteNetworkCaptureOpen,
                memory_order_acquire);
    }
}

static NSDictionary* BHTDetailedWriteRequestSummary(
    NSURLRequest* request,
    NSData* requestBody,
    NSString* constructorCategory,
    NSUInteger replySessionGeneration,
    BHTDetailedWriteKind compositionKindHint,
    id activeCompositionAccount,
    BHTDetailedWriteKind* kind,
    NSUInteger* truncations) {
    if (kind) *kind = BHTDetailedWriteKindUnknown;
    NSString* operation = nil;
    NSString* queryFingerprint = nil;
    NSString* hostCategory = nil;
    if (![request isKindOfClass:NSURLRequest.class] ||
        ![request.HTTPMethod.uppercaseString isEqualToString:@"POST"] ||
        !BHTDetailedWriteURLIsEligible(
            request.URL, &operation, &queryFingerprint, &hostCategory)) {
        return nil;
    }

    NSString* bodyState = nil;
    NSDictionary* envelope = BHTDetailedWriteEnvelopeFromData(
        requestBody, &bodyState, truncations);
    id variables = envelope[@"variables"];
    id features = envelope[@"features"];
    NSMutableArray<NSString*>* fieldPaths = [NSMutableArray array];
    id variableSchema = variables
        ? BHTDetailedWriteSchemaForValue(
              variables, 0, fieldPaths, @"variables", truncations)
        : @{ @"type": @"absent" };
    NSMutableArray<NSString*>* replyEvidence = [NSMutableArray array];
    BOOL bodyShowsReply = BHTDetailedWriteReplyEvidence(
        variables, 0, replyEvidence, @"variables");

    BOOL hintAvailable =
        compositionKindHint != BHTDetailedWriteKindUnknown;
    BOOL hintBodyConflict =
        hintAvailable && envelope &&
        ((compositionKindHint == BHTDetailedWriteKindReply) !=
         bodyShowsReply);
    BOOL activeReplySession = replySessionGeneration > 0;
    BOOL activeReplyBodyConflict =
        activeReplySession && envelope && !bodyShowsReply;
    BHTDetailedWriteKind resolvedKind = BHTDetailedWriteKindUnknown;
    NSString* classificationSource = @"unclassified";
    if (activeReplySession) {
        // The active reply session is authoritative. A stale process-global
        // hint or conflicting body shape is reported and invalidates the
        // comparison; neither is allowed to reclassify this request.
        resolvedKind = BHTDetailedWriteKindReply;
        classificationSource = bodyShowsReply
            ? @"nativeReplyWindowAndVariableShape"
            : @"nativeReplyWindowOnly";
    } else if (envelope) {
        resolvedKind = bodyShowsReply
            ? BHTDetailedWriteKindReply
            : BHTDetailedWriteKindStandalone;
        classificationSource = @"variableShape";
    } else if (hintAvailable) {
        resolvedKind = compositionKindHint;
        classificationSource = @"compositionIsReplyABIOnly";
    }
    if (kind) *kind = resolvedKind;

    NSString* bodyQueryID = [envelope[@"queryId"]
        isKindOfClass:NSString.class]
        ? envelope[@"queryId"]
        : nil;
    if (!queryFingerprint) {
        queryFingerprint = BHTDetailedWriteFingerprint(bodyQueryID);
    }
    [fieldPaths sortUsingSelector:@selector(compare:)];
    [replyEvidence sortUsingSelector:@selector(compare:)];
    return @{
        @"operation": operation ?: @"unknown",
        @"taskConstructor": constructorCategory ?: @"unknown",
        @"hostCategory": hostCategory ?: @"unknown",
        @"bodyState": bodyState ?: @"unknown",
        @"bodyBytesRetained": @NO,
        @"queryFingerprint": queryFingerprint ?: NSNull.null,
        @"queryFingerprintAlgorithm": @"fnv1a64",
        @"rawQueryIDRetained": @NO,
        @"variableSchema": variableSchema,
        @"variableFieldPaths": [fieldPaths copy],
        @"featureShape": BHTDetailedWriteFeatureShape(features),
        @"replyEvidencePaths": [replyEvidence copy],
        @"replyEvidencePresent": @(bodyShowsReply),
        @"classificationSource": classificationSource,
        @"nativeReplyWindowCorrelated":
            @(replySessionGeneration > 0),
        @"compositionIsReplyHintAvailable":
            @(hintAvailable),
        @"compositionHintAgreesWithVariableShape":
            hintAvailable && envelope
                ? @((compositionKindHint == BHTDetailedWriteKindReply) ==
                    bodyShowsReply)
                : NSNull.null,
        @"compositionHintConflictsWithVariableShape":
            @(hintBodyConflict),
        @"activeReplyWindowConflictsWithVariableShape":
            @(activeReplyBodyConflict),
        @"accountContext":
            BHTDetailedWriteAccountContext(
                resolvedKind, activeCompositionAccount),
        @"capturesTextOrIdentifierValues": @NO,
        @"capturesHeadersCookiesOrTokens": @NO,
    };
}

static NSArray<NSString*>* BHTDetailedWriteSortedStringArray(id value) {
    if (![value isKindOfClass:NSArray.class]) return @[];
    NSMutableSet<NSString*>* strings = [NSMutableSet set];
    for (id item in (NSArray*)value) {
        if ([item isKindOfClass:NSString.class]) [strings addObject:item];
    }
    return [[strings allObjects]
        sortedArrayUsingSelector:@selector(compare:)];
}

static NSDictionary* BHTDetailedWriteArrayComparison(
    NSArray<NSString*>* standalone,
    NSArray<NSString*>* reply) {
    NSSet* standaloneSet = [NSSet setWithArray:
        BHTDetailedWriteSortedStringArray(standalone)];
    NSSet* replySet = [NSSet setWithArray:
        BHTDetailedWriteSortedStringArray(reply)];
    NSMutableSet* common = [standaloneSet mutableCopy];
    [common intersectSet:replySet];
    NSMutableSet* standaloneOnly = [standaloneSet mutableCopy];
    [standaloneOnly minusSet:replySet];
    NSMutableSet* replyOnly = [replySet mutableCopy];
    [replyOnly minusSet:standaloneSet];
    return @{
        @"common": [[common allObjects]
            sortedArrayUsingSelector:@selector(compare:)],
        @"standaloneOnly": [[standaloneOnly allObjects]
            sortedArrayUsingSelector:@selector(compare:)],
        @"replyOnly": [[replyOnly allObjects]
            sortedArrayUsingSelector:@selector(compare:)],
    };
}

static NSDictionary* BHTDetailedWriteFeatureComparison(
    NSDictionary* standaloneRequest,
    NSDictionary* replyRequest) {
    NSDictionary* standaloneShape =
        [standaloneRequest[@"featureShape"] isKindOfClass:NSDictionary.class]
        ? standaloneRequest[@"featureShape"]
        : @{};
    NSDictionary* replyShape =
        [replyRequest[@"featureShape"] isKindOfClass:NSDictionary.class]
        ? replyRequest[@"featureShape"]
        : @{};
    NSDictionary* standaloneFlags =
        [standaloneShape[@"flags"] isKindOfClass:NSDictionary.class]
        ? standaloneShape[@"flags"]
        : @{};
    NSDictionary* replyFlags =
        [replyShape[@"flags"] isKindOfClass:NSDictionary.class]
        ? replyShape[@"flags"]
        : @{};
    NSDictionary* keyComparison = BHTDetailedWriteArrayComparison(
        standaloneFlags.allKeys, replyFlags.allKeys);
    NSMutableArray* differentBooleanValues = [NSMutableArray array];
    for (NSString* key in keyComparison[@"common"]) {
        if (![standaloneFlags[key] isEqual:replyFlags[key]]) {
            [differentBooleanValues addObject:key];
        }
    }
    return @{
        @"keys": keyComparison,
        @"keysWithDifferentBooleanShape":
            [differentBooleanValues copy],
        @"opaqueBooleanCountBucketsMatch": @(
            [standaloneShape[@"opaqueTrueCountBucket"]
                isEqual:replyShape[@"opaqueTrueCountBucket"]] &&
            [standaloneShape[@"opaqueFalseCountBucket"]
                isEqual:replyShape[@"opaqueFalseCountBucket"]] &&
            [standaloneShape[@"opaqueNonBooleanCountBucket"]
                isEqual:replyShape[@"opaqueNonBooleanCountBucket"]]),
    };
}

static BOOL BHTDetailedWriteBodySchemaIsUsable(NSDictionary* request) {
    NSString* state = [request[@"bodyState"] isKindOfClass:NSString.class]
        ? request[@"bodyState"]
        : nil;
    return [state isEqualToString:@"jsonParsedToSchema"] ||
        [state isEqualToString:@"formGraphQLFieldsParsedToSchema"];
}

static BOOL BHTDetailedWriteFlagIsTrue(
    NSDictionary* dictionary,
    NSString* key) {
    id value = dictionary[key];
    return [value isKindOfClass:NSNumber.class] &&
        [(NSNumber*)value boolValue];
}

static void BHTDetailedWriteRebuildComparisonLocked(void) {
    if (![BHTDetailedReplyCapture isKindOfClass:NSDictionary.class]) return;
    NSMutableDictionary* capture =
        [BHTDetailedReplyCapture mutableCopy];
    NSDictionary* attempts = [capture[@"attempts"]
        isKindOfClass:NSDictionary.class]
        ? capture[@"attempts"]
        : @{};
    NSDictionary* standalone = [attempts[@"standalone"]
        isKindOfClass:NSDictionary.class]
        ? attempts[@"standalone"]
        : nil;
    NSDictionary* reply = [attempts[@"reply"]
        isKindOfClass:NSDictionary.class]
        ? attempts[@"reply"]
        : nil;
    if (!standalone || !reply) {
        capture[@"comparison"] = @{
            @"complete": @NO,
            @"waitingFor": standalone ? @"reply" : @"standalone",
            @"validForRequestShapeComparison": @NO,
            @"validForReplyAuthorizationDiagnosis": @NO,
            @"standaloneApplicationOutcomeObserved": @NO,
            @"standaloneSuccessMustBeConfirmedByTester": @YES,
            @"inconclusiveReasons": @[
                standalone
                    ? @"replyNotCapturedYet"
                    : @"standaloneMustBeCapturedFirst",
                @"standaloneApplicationOutcomeRequiresTesterConfirmation",
            ],
        };
        BHTDetailedReplyCapture = [capture copy];
        return;
    }
    NSDictionary* standaloneRequest = [standalone[@"request"]
        isKindOfClass:NSDictionary.class]
        ? standalone[@"request"]
        : @{};
    NSDictionary* replyRequest = [reply[@"request"]
        isKindOfClass:NSDictionary.class]
        ? reply[@"request"]
        : @{};
    id standaloneFingerprint = standaloneRequest[@"queryFingerprint"];
    id replyFingerprint = replyRequest[@"queryFingerprint"];
    BOOL fingerprintsAvailable =
        [standaloneFingerprint isKindOfClass:NSString.class] &&
        [replyFingerprint isKindOfClass:NSString.class];
    NSDictionary* standaloneNetwork = [standalone[@"network"]
        isKindOfClass:NSDictionary.class]
        ? standalone[@"network"]
        : @{};
    NSDictionary* replyNetwork = [reply[@"network"]
        isKindOfClass:NSDictionary.class]
        ? reply[@"network"]
        : @{};
    NSString* standaloneHTTP = [standaloneNetwork[@"httpClass"]
        isKindOfClass:NSString.class]
        ? standaloneNetwork[@"httpClass"]
        : nil;
    NSString* replyHTTP = [replyNetwork[@"httpClass"]
        isKindOfClass:NSString.class]
        ? replyNetwork[@"httpClass"]
        : nil;
    BOOL standaloneBodyUsable =
        BHTDetailedWriteBodySchemaIsUsable(standaloneRequest);
    BOOL replyBodyUsable =
        BHTDetailedWriteBodySchemaIsUsable(replyRequest);
    BOOL standaloneHasReplyEvidence =
        BHTDetailedWriteFlagIsTrue(
            standaloneRequest, @"replyEvidencePresent");
    BOOL replyHasReplyEvidence =
        BHTDetailedWriteFlagIsTrue(
            replyRequest, @"replyEvidencePresent");
    BOOL classificationConflict =
        BHTDetailedWriteFlagIsTrue(
            standaloneRequest,
            @"compositionHintConflictsWithVariableShape") ||
        BHTDetailedWriteFlagIsTrue(
            standaloneRequest,
            @"activeReplyWindowConflictsWithVariableShape") ||
        BHTDetailedWriteFlagIsTrue(
            replyRequest,
            @"compositionHintConflictsWithVariableShape") ||
        BHTDetailedWriteFlagIsTrue(
            replyRequest,
            @"activeReplyWindowConflictsWithVariableShape");
    NSDictionary* replyAccount = [replyRequest[@"accountContext"]
        isKindOfClass:NSDictionary.class]
        ? replyRequest[@"accountContext"]
        : @{};
    id replyAccountMatch =
        replyAccount[@"compositionAccountMatchesReplyComposerAccount"];
    BOOL replyAccountMatchAvailable =
        [replyAccountMatch isKindOfClass:NSNumber.class];
    BOOL replyAccountMatches =
        replyAccountMatchAvailable &&
        [(NSNumber*)replyAccountMatch boolValue];
    NSDictionary* standaloneApplication =
        [standalone[@"applicationResponse"] isKindOfClass:NSDictionary.class]
        ? standalone[@"applicationResponse"]
        : @{};
    NSDictionary* replyApplication =
        [reply[@"applicationResponse"] isKindOfClass:NSDictionary.class]
        ? reply[@"applicationResponse"]
        : @{};
    BOOL standaloneApplicationObserved =
        [standaloneApplication[@"state"]
            isEqualToString:@"decodedResponseCaptured"];
    BOOL replyApplicationObserved =
        [replyApplication[@"state"]
            isEqualToString:@"decodedResponseCaptured"];
    BOOL standaloneApplicationBound =
        BHTDetailedWriteFlagIsTrue(
            standalone,
            @"applicationOutcomeBoundByOriginalRequestIdentity");
    BOOL replyApplicationBound =
        BHTDetailedWriteFlagIsTrue(
            reply,
            @"applicationOutcomeBoundByOriginalRequestIdentity");
    BOOL standaloneGraphQLErrors =
        BHTDetailedWriteFlagIsTrue(
            standaloneApplication, @"graphqlErrorsPresent");
    BOOL standaloneGraphQLData =
        BHTDetailedWriteFlagIsTrue(
            standaloneApplication, @"graphqlDataPresent");
    BOOL standaloneGraphQLSuccessShape =
        standaloneApplicationObserved && standaloneApplicationBound &&
        !standaloneGraphQLErrors && standaloneGraphQLData;
    BOOL requestShapeValid =
        standaloneBodyUsable && replyBodyUsable &&
        !standaloneHasReplyEvidence && replyHasReplyEvidence &&
        !classificationConflict;
    NSMutableArray<NSString*>* inconclusiveReasons =
        [NSMutableArray array];
    if (!standaloneBodyUsable) {
        [inconclusiveReasons addObject:
            @"standaloneBodySchemaUnavailable"];
    }
    if (!replyBodyUsable) {
        [inconclusiveReasons addObject:
            @"replyBodySchemaUnavailable"];
    }
    if (standaloneHasReplyEvidence) {
        [inconclusiveReasons addObject:
            @"standaloneUnexpectedlyContainsReplyEvidence"];
    }
    if (!replyHasReplyEvidence) {
        [inconclusiveReasons addObject:
            @"replyHasNoNonemptyReplyEvidence"];
    }
    if (classificationConflict) {
        [inconclusiveReasons addObject:
            @"compositionOrReplyWindowConflictsWithBodyShape"];
    }
    if (!replyAccountMatchAvailable) {
        [inconclusiveReasons addObject:
            @"replyAccountComparisonUnavailable"];
    } else if (!replyAccountMatches) {
        [inconclusiveReasons addObject:
            @"replyCompositionAccountMismatch"];
    }
    if (!replyApplicationObserved) {
        [inconclusiveReasons addObject:
            @"replyApplicationOutcomeUnavailable"];
    }
    if (!standaloneApplicationObserved) {
        [inconclusiveReasons addObject:
            @"standaloneApplicationOutcomeUnavailable"];
    } else if (!standaloneApplicationBound) {
        [inconclusiveReasons addObject:
            @"standaloneApplicationBindingUnavailable"];
    } else if (!standaloneGraphQLSuccessShape) {
        [inconclusiveReasons addObject:
            @"standaloneApplicationWasNotSuccessShaped"];
    }
    if (replyApplicationObserved && !replyApplicationBound) {
        [inconclusiveReasons addObject:
            @"replyApplicationBindingUnavailable"];
    }
    capture[@"comparison"] = @{
        @"complete": @YES,
        @"requiredOrderFollowed": @YES,
        @"validForRequestShapeComparison": @(requestShapeValid),
        @"validForReplyAuthorizationDiagnosis":
            @(requestShapeValid && replyAccountMatches &&
              standaloneGraphQLSuccessShape &&
              replyApplicationObserved && replyApplicationBound),
        @"standaloneApplicationOutcomeObserved":
            @(standaloneApplicationObserved),
        @"replyApplicationOutcomeObserved":
            @(replyApplicationObserved),
        @"standaloneApplicationBoundByOriginalRequestIdentity":
            @(standaloneApplicationBound),
        @"replyApplicationBoundByOriginalRequestIdentity":
            @(replyApplicationBound),
        @"standaloneGraphQLSuccessShape":
            @(standaloneGraphQLSuccessShape),
        @"standaloneSuccessMustBeConfirmedByTester":
            @(!standaloneGraphQLSuccessShape),
        @"inconclusiveReasons": [inconclusiveReasons copy],
        @"queryFingerprintMatch": fingerprintsAvailable
            ? @([standaloneFingerprint isEqual:replyFingerprint])
            : NSNull.null,
        @"variableFieldPaths": BHTDetailedWriteArrayComparison(
            standaloneRequest[@"variableFieldPaths"],
            replyRequest[@"variableFieldPaths"]),
        @"features": BHTDetailedWriteFeatureComparison(
            standaloneRequest, replyRequest),
        @"replyEvidencePresent": @{
            @"standalone":
                standaloneRequest[@"replyEvidencePresent"] ?: NSNull.null,
            @"reply":
                replyRequest[@"replyEvidencePresent"] ?: NSNull.null,
        },
        @"classificationSources": @{
            @"standalone":
                standaloneRequest[@"classificationSource"] ?: @"unknown",
            @"reply":
                replyRequest[@"classificationSource"] ?: @"unknown",
        },
        @"transportHTTPClassMatch": standaloneHTTP && replyHTTP
            ? @([standaloneHTTP isEqualToString:replyHTTP])
            : NSNull.null,
        @"rawValuesCompared": @NO,
    };
    BHTDetailedReplyCapture = [capture copy];
}

static NSString* BHTDetailedWriteHTTPClass(NSURLResponse* response) {
    if (!response) return @"none";
    if (![response isKindOfClass:NSHTTPURLResponse.class]) {
        return @"nonHTTP";
    }
    switch (((NSHTTPURLResponse*)response).statusCode / 100) {
        case 1: return @"informational1xx";
        case 2: return @"success2xx";
        case 3: return @"redirect3xx";
        case 4: return @"clientFailure4xx";
        case 5: return @"serverFailure5xx";
        default: return @"nonHTTP";
    }
}

static NSString* BHTDetailedWriteTransportErrorCategory(NSError* error) {
    if (!error) return @"none";
    if (![error isKindOfClass:NSError.class] ||
        ![error.domain isEqualToString:NSURLErrorDomain]) {
        return @"nonURLError";
    }
    switch (error.code) {
        case NSURLErrorCancelled: return @"cancelled";
        case NSURLErrorTimedOut: return @"timedOut";
        case NSURLErrorNotConnectedToInternet:
        case NSURLErrorCannotConnectToHost:
        case NSURLErrorNetworkConnectionLost:
            return @"offlineOrConnectivity";
        case NSURLErrorCannotFindHost:
        case NSURLErrorDNSLookupFailed:
            return @"dns";
        case NSURLErrorSecureConnectionFailed:
        case NSURLErrorServerCertificateHasBadDate:
        case NSURLErrorServerCertificateUntrusted:
        case NSURLErrorServerCertificateHasUnknownRoot:
        case NSURLErrorServerCertificateNotYetValid:
        case NSURLErrorClientCertificateRejected:
        case NSURLErrorClientCertificateRequired:
            return @"tlsOrTrust";
        default: return @"transportOther";
    }
}

static NSString* BHTDetailedWriteDurationBucket(NSTimeInterval elapsed) {
    if (elapsed < 0.25) return @"under250ms";
    if (elapsed < 1.0) return @"250msTo999ms";
    if (elapsed < 3.0) return @"1sTo2.999s";
    if (elapsed < 10.0) return @"3sTo9.999s";
    return @"10sOrMore";
}

BOOL BHTDetailedReplyDiagnosticsNetworkCaptureMayBeActive(void) {
    return atomic_load_explicit(
        &BHTDetailedWriteNetworkCaptureOpen, memory_order_acquire);
}

void BHTDetailedReplyDiagnosticsNoteReplyAccount(id account) {
    if (!BHTDetailedReplyDiagnosticsNetworkCaptureMayBeActive()) return;
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyComposerAccount = account;
    }
}

void BHTDetailedReplyDiagnosticsNoteCompatibilityAccount(id account) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedCompatibilityAccount = account;
    }
}

void BHTDetailedReplyDiagnosticsNoteCompositionContext(
    BOOL isReply,
    id activeAccount) {
    if (!BHTDetailedReplyDiagnosticsNetworkCaptureMayBeActive()) return;
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        if (!BHTDetailedReplyArmed) return;
        BHTDetailedActiveCompositionAccount = activeAccount;
        BHTDetailedPendingApplicationToken = @{
            @"captureEpoch": @(BHTDetailedReplyCaptureEpoch),
            @"writeKind": isReply ? @"reply" : @"standalone",
        };
        atomic_store_explicit(
            &BHTDetailedWritePendingCompositionKind,
            isReply ? BHTDetailedWriteKindReply
                    : BHTDetailedWriteKindStandalone,
            memory_order_release);
    }
}

NSDictionary*
BHTDetailedReplyDiagnosticsApplicationTokenForRequestURL(NSURL* requestURL) {
    if (!BHTDetailedReplyDiagnosticsNetworkCaptureMayBeActive() ||
        !BHTDetailedWriteURLIsEligible(requestURL, NULL, NULL, NULL)) {
        return nil;
    }
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        if (!BHTDetailedReplyArmed ||
            ![BHTDetailedPendingApplicationToken
                isKindOfClass:NSDictionary.class]) {
            return nil;
        }
        NSNumber* epoch = BHTDetailedPendingApplicationToken[@"captureEpoch"];
        NSString* writeKind =
            BHTDetailedPendingApplicationToken[@"writeKind"];
        if (![epoch isKindOfClass:NSNumber.class] ||
            epoch.unsignedIntegerValue != BHTDetailedReplyCaptureEpoch ||
            (![writeKind isEqualToString:@"standalone"] &&
             ![writeKind isEqualToString:@"reply"])) {
            return nil;
        }
        return [BHTDetailedPendingApplicationToken copy];
    }
}

void BHTDetailedReplyDiagnosticsSetApplicationBindingHookAvailable(
    BOOL available) {
    atomic_store_explicit(
        &BHTDetailedApplicationBindingHookAvailable, available,
        memory_order_release);
}

void BHTDetailedReplyDiagnosticsCaptureRequest(
    NSURLRequest* request,
    NSData* requestBody,
    NSURLSessionTask* task,
    NSString* constructorCategory,
    NSUInteger replySessionGeneration) {
    if (!BHTDetailedReplyDiagnosticsRequestIsEligible(request) ||
        ![task isKindOfClass:NSURLSessionTask.class]) {
        return;
    }
    if ([objc_getAssociatedObject(task, &BHTDetailedWriteTaskTagKey)
            isKindOfClass:BHTDetailedWriteTaskTag.class]) {
        return;
    }
    unsigned int pendingKind = BHTDetailedWriteKindUnknown;
    id activeCompositionAccount = nil;
    @synchronized(BHTDetailedReplyLock()) {
        // Consume the composition context only after the body-blind exact
        // CreateTweet gate. Keeping the exchange and weak-account snapshot
        // under one lock prevents a late clear from erasing a newer send.
        pendingKind = atomic_exchange_explicit(
            &BHTDetailedWritePendingCompositionKind,
            BHTDetailedWriteKindUnknown, memory_order_acq_rel);
        if (pendingKind > BHTDetailedWriteKindUnknown &&
            pendingKind <= BHTDetailedWriteKindReply) {
            activeCompositionAccount =
                BHTDetailedActiveCompositionAccount;
            BHTDetailedActiveCompositionAccount = nil;
        }
    }
    BHTDetailedWriteKind compositionKindHint =
        pendingKind <= BHTDetailedWriteKindReply
            ? (BHTDetailedWriteKind)pendingKind
            : BHTDetailedWriteKindUnknown;
    BHTDetailedWriteKind kind = BHTDetailedWriteKindUnknown;
    NSUInteger truncations = 0;
    NSDictionary* requestSummary = BHTDetailedWriteRequestSummary(
        request, requestBody, constructorCategory,
        replySessionGeneration, compositionKindHint,
        activeCompositionAccount, &kind,
        &truncations);
    if (!requestSummary || kind == BHTDetailedWriteKindUnknown) return;
    NSString* kindName = kind == BHTDetailedWriteKindReply
        ? @"reply"
        : @"standalone";

    NSUInteger acceptedEpoch = 0;
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        if (!BHTDetailedReplyArmed) return;
        NSMutableDictionary* capture =
            [BHTDetailedReplyCapture mutableCopy] ?:
                [NSMutableDictionary dictionary];
        NSMutableDictionary* attempts =
            [capture[@"attempts"] mutableCopy] ?:
                [NSMutableDictionary dictionary];
        if (attempts[kindName]) return;

        if (BHTDetailedReplyCaptureStartedAt <= 0) {
            BHTDetailedReplyCaptureStartedAt = BHTDetailedReplyNow();
            BHTDetailedReplyScheduleExpiryLocked();
        }
        if (kind == BHTDetailedWriteKindReply &&
            !attempts[@"standalone"]) {
            capture[@"protocol"] = @{
                @"requiredOrder": @"standaloneThenReply",
                @"state": @"replyObservedBeforeStandalone",
                @"pairRejected": @YES,
                @"mustRearmAndStartWithStandalone": @YES,
                @"standaloneVisibilityCanOnlyBeConfirmedByTester": @YES,
            };
            capture[@"comparison"] = @{
                @"complete": @NO,
                @"validForRequestShapeComparison": @NO,
                @"validForReplyAuthorizationDiagnosis": @NO,
                @"inconclusiveReasons": @[
                    @"requiredStandaloneFirstProtocolWasNotFollowed",
                    @"standaloneApplicationOutcomeRequiresTesterConfirmation",
                ],
            };
            BHTDetailedReplyCapture = [capture copy];
            BHTDetailedReplyTruncationCount += truncations;
            BHTDetailedReplyArmed = NO;
            atomic_store_explicit(
                &BHTDetailedWriteNetworkCaptureOpen, false,
                memory_order_release);
            BHTDetailedReplySetPreference(NO);
            BHTDetailedReplyCaptureState =
                @"protocolRejectedReplyBeforeStandalone";
            return;
        }
        if (kind == BHTDetailedWriteKindReply &&
            atomic_load_explicit(
                &BHTDetailedApplicationBindingHookAvailable,
                memory_order_acquire)) {
            NSDictionary* standaloneAttempt =
                [attempts[@"standalone"] isKindOfClass:NSDictionary.class]
                ? attempts[@"standalone"]
                : nil;
            NSDictionary* standaloneApplication =
                [standaloneAttempt[@"applicationResponse"]
                    isKindOfClass:NSDictionary.class]
                ? standaloneAttempt[@"applicationResponse"]
                : nil;
            BOOL standaloneApplicationReady =
                [standaloneApplication[@"state"]
                    isEqualToString:@"decodedResponseCaptured"] &&
                BHTDetailedWriteFlagIsTrue(
                    standaloneAttempt,
                    @"applicationOutcomeBoundByOriginalRequestIdentity");
            if (!standaloneApplicationReady) {
                capture[@"protocol"] = @{
                    @"requiredOrder": @"standaloneThenReply",
                    @"state": @"replyObservedBeforeStandaloneApplicationOutcome",
                    @"pairRejected": @YES,
                    @"mustRearmWaitForVisibleStandaloneThenReply": @YES,
                };
                capture[@"comparison"] = @{
                    @"complete": @NO,
                    @"validForRequestShapeComparison": @NO,
                    @"validForReplyAuthorizationDiagnosis": @NO,
                    @"inconclusiveReasons": @[
                        @"replyArrivedBeforeBoundStandaloneApplicationOutcome",
                    ],
                };
                BHTDetailedReplyCapture = [capture copy];
                BHTDetailedReplyTruncationCount += truncations;
                BHTDetailedReplyArmed = NO;
                atomic_store_explicit(
                    &BHTDetailedWriteNetworkCaptureOpen, false,
                    memory_order_release);
                BHTDetailedReplySetPreference(NO);
                BHTDetailedReplyCaptureState =
                    @"protocolRejectedReplyBeforeStandaloneApplicationOutcome";
                return;
            }
        }
        if (kind == BHTDetailedWriteKindReply &&
            replySessionGeneration > 0) {
            BHTDetailedReplySessionGeneration =
                replySessionGeneration;
        }
        attempts[kindName] = @{
            @"writeKind": kindName,
            @"request": requestSummary,
            @"network": @{ @"state": @"awaitingCompletion" },
            @"applicationResponse": @{
                @"state": kind == BHTDetailedWriteKindReply
                    ? @"awaitingEligibleDecoderCheckpoint"
                    : @"awaitingOriginalRequestBoundDecoderCheckpoint",
            },
        };
        capture[@"attempts"] = [attempts copy];
        capture[@"protocol"] = @{
            @"requiredOrder": @"standaloneThenReply",
            @"state": kind == BHTDetailedWriteKindStandalone
                ? @"standaloneCapturedAwaitingTesterConfirmationAndReply"
                : @"pairCaptured",
            @"standaloneVisibilityCanOnlyBeConfirmedByTester": @YES,
            @"standaloneVisibilityConfirmedByCode": @NO,
        };
        BHTDetailedReplyCapture = [capture copy];
        BHTDetailedReplyTruncationCount += truncations;
        acceptedEpoch = BHTDetailedReplyCaptureEpoch;

        BOOL completePair = attempts[@"standalone"] && attempts[@"reply"];
        if (completePair) {
            BHTDetailedReplyArmed = NO;
            BHTDetailedReplySetPreference(NO);
            atomic_store_explicit(
                &BHTDetailedWriteNetworkCaptureOpen, false,
                memory_order_release);
            BHTDetailedReplyCaptureState =
                @"pairedRequestsCapturedAwaitingCallbacks";
        } else {
            BHTDetailedReplyCaptureState =
                @"standaloneCapturedAwaitingTesterConfirmationAndReply";
        }
        BHTDetailedWriteRebuildComparisonLocked();
    }

    BHTDetailedWriteTaskTag* tag = [BHTDetailedWriteTaskTag new];
    tag.writeKind = kindName;
    tag.captureEpoch = acceptedEpoch;
    tag.startedAt = BHTDetailedReplyNow();
    objc_setAssociatedObject(
        task, &BHTDetailedWriteTaskTagKey, tag,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void BHTDetailedReplyDiagnosticsCompleteRequest(
    NSURLSessionTask* task,
    NSError* error) {
    if (![task isKindOfClass:NSURLSessionTask.class]) return;
    BHTDetailedWriteTaskTag* tag = objc_getAssociatedObject(
        task, &BHTDetailedWriteTaskTagKey);
    if (![tag isKindOfClass:BHTDetailedWriteTaskTag.class]) return;
    objc_setAssociatedObject(
        task, &BHTDetailedWriteTaskTagKey, nil,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSDictionary* network = @{
        @"state": @"completed",
        @"httpClass": BHTDetailedWriteHTTPClass(task.response),
        @"transportErrorCategory":
            BHTDetailedWriteTransportErrorCategory(error),
        @"durationBucket": BHTDetailedWriteDurationBucket(
            MAX(0.0, BHTDetailedReplyNow() - tag.startedAt)),
        @"responseContentsRead": @NO,
        @"rawErrorRead": @NO,
    };
    @synchronized(BHTDetailedReplyLock()) {
        if (tag.captureEpoch != BHTDetailedReplyCaptureEpoch ||
            !BHTDetailedReplyCapture) {
            return;
        }
        NSMutableDictionary* capture =
            [BHTDetailedReplyCapture mutableCopy];
        NSMutableDictionary* attempts =
            [capture[@"attempts"] mutableCopy];
        NSMutableDictionary* attempt =
            [attempts[tag.writeKind] mutableCopy];
        if (!attempt) return;
        attempt[@"network"] = network;
        attempts[tag.writeKind] = [attempt copy];
        capture[@"attempts"] = [attempts copy];
        BHTDetailedReplyCapture = [capture copy];
        BHTDetailedWriteRebuildComparisonLocked();
        BHTDetailedReplyCaptureState =
            [tag.writeKind isEqualToString:@"reply"]
                ? @"replyTransportCaptured"
                : @"standaloneTransportCaptured";
    }
}

void BHTArmDetailedReplyDiagnostics(void) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyCaptureEpoch++;
        BHTDetailedReplyArmed = YES;
        BHTDetailedReplyArmedAt = BHTDetailedReplyNow();
        BHTDetailedReplyCaptureStartedAt = 0;
        BHTDetailedReplySessionGeneration = 0;
        BHTDetailedReplyCapture = nil;
        BHTDetailedReplyRedactionCount = 0;
        BHTDetailedReplyTruncationCount = 0;
        BHTDetailedReplyResponseAccessorsObserved = NO;
        BHTDetailedReplyComposerAccount = nil;
        BHTDetailedActiveCompositionAccount = nil;
        BHTDetailedPendingApplicationToken = nil;
        atomic_store_explicit(
            &BHTDetailedWritePendingCompositionKind,
            BHTDetailedWriteKindUnknown, memory_order_release);
        atomic_store_explicit(
            &BHTDetailedWriteNetworkCaptureOpen, true,
            memory_order_release);
        BHTDetailedReplyCaptureState =
            @"armedForStandaloneAndReplyCreateTweet";
        BHTDetailedReplySetPreference(YES);
        BHTDetailedReplyScheduleArmExpiryLocked();
    }
}

void BHTDisarmDetailedReplyDiagnostics(void) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyArmed = NO;
        atomic_store_explicit(
            &BHTDetailedWriteNetworkCaptureOpen, false,
            memory_order_release);
        atomic_store_explicit(
            &BHTDetailedWritePendingCompositionKind,
            BHTDetailedWriteKindUnknown, memory_order_release);
        BHTDetailedActiveCompositionAccount = nil;
        BHTDetailedPendingApplicationToken = nil;
        if (!BHTDetailedReplyCapture) {
            BHTDetailedReplyCaptureState = @"disarmed";
        }
        BHTDetailedReplySetPreference(NO);
    }
}

BOOL BHTDetailedReplyDiagnosticsIsArmed(void) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        // A persisted ON value from a previous process must never re-arm this
        // invasive diagnostic without a fresh in-app confirmation.
        if (!BHTDetailedReplyArmed &&
            [BHTSettings boolForKey:@"detailed_reply_diagnostics"]) {
            BHTDetailedReplySetPreference(NO);
        }
        return BHTDetailedReplyArmed;
    }
}

BOOL BHTDetailedReplyDiagnosticsHasCapture(void) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        NSDictionary* attempts = [BHTDetailedReplyCapture[@"attempts"]
            isKindOfClass:NSDictionary.class]
            ? BHTDetailedReplyCapture[@"attempts"]
            : nil;
        return attempts[@"standalone"] != nil &&
            attempts[@"reply"] != nil;
    }
}

void BHTClearDetailedReplyDiagnostics(void) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyCaptureEpoch++;
        BHTDetailedReplyArmed = NO;
        BHTDetailedReplyArmedAt = 0;
        BHTDetailedReplyCaptureStartedAt = 0;
        BHTDetailedReplySessionGeneration = 0;
        BHTDetailedReplyCapture = nil;
        BHTDetailedReplyRedactionCount = 0;
        BHTDetailedReplyTruncationCount = 0;
        BHTDetailedReplyResponseAccessorsObserved = NO;
        BHTDetailedReplyComposerAccount = nil;
        BHTDetailedActiveCompositionAccount = nil;
        BHTDetailedPendingApplicationToken = nil;
        atomic_store_explicit(
            &BHTDetailedWriteNetworkCaptureOpen, false,
            memory_order_release);
        atomic_store_explicit(
            &BHTDetailedWritePendingCompositionKind,
            BHTDetailedWriteKindUnknown, memory_order_release);
        BHTDetailedReplyCaptureState = @"cleared";
        BHTDetailedReplySetPreference(NO);
    }
}

static NSString* BHTDetailedWriteServerStringCategory(NSString* value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) {
        return @"absent";
    }
    NSString* normalized = value.lowercaseString;
    if ([normalized containsString:@"authoriz"] ||
        [normalized containsString:@"permission"] ||
        [normalized containsString:@"not permitted"] ||
        [normalized containsString:@"forbidden"]) {
        return @"authorizationOrPermission";
    }
    if ([normalized containsString:@"rate"] &&
        [normalized containsString:@"limit"]) {
        return @"rateLimit";
    }
    if ([normalized containsString:@"duplicate"] ||
        ([normalized containsString:@"already"] &&
         [normalized containsString:@"post"])) {
        return @"duplicate";
    }
    if ([normalized containsString:@"spam"] ||
        [normalized containsString:@"automated"]) {
        return @"antiAbuse";
    }
    if ([normalized containsString:@"suspend"] ||
        [normalized containsString:@"lock"] ||
        [normalized containsString:@"restrict"]) {
        return @"accountRestriction";
    }
    if ([normalized containsString:@"not found"] ||
        [normalized containsString:@"missing"]) {
        return @"notFound";
    }
    if ([normalized containsString:@"valid"] ||
        [normalized containsString:@"invalid"] ||
        [normalized containsString:@"malformed"]) {
        return @"validation";
    }
    if ([normalized containsString:@"client"]) return @"client";
    if ([normalized containsString:@"server"] ||
        [normalized containsString:@"internal"]) {
        return @"server";
    }
    return @"other";
}

static NSDictionary* BHTDetailedWriteSafeObjectSummary(id value) {
    if (!value) return @{ @"present": @NO };
    NSMutableDictionary* summary = [@{
        @"present": @YES,
        @"class": NSStringFromClass([value class]) ?: @"unknown",
        @"descriptionRetained": @NO,
        @"userInfoRetained": @NO,
    } mutableCopy];
    if ([value isKindOfClass:NSError.class]) {
        NSError* error = value;
        summary[@"domainFingerprint"] =
            BHTDetailedWriteFingerprint(error.domain) ?: NSNull.null;
        summary[@"code"] = @(error.code);
        summary[@"descriptionCategory"] =
            BHTDetailedWriteServerStringCategory(
                error.localizedDescription);
    } else if ([value isKindOfClass:NSArray.class]) {
        summary[@"countBucket"] =
            BHTDetailedWriteCountBucket([(NSArray*)value count]);
    } else if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableArray* safeKeys = [NSMutableArray array];
        for (id key in [(NSDictionary*)value allKeys]) {
            if (safeKeys.count >= 32) break;
            [safeKeys addObject:BHTDetailedWriteSafeSchemaKey(key)];
        }
        [safeKeys sortUsingSelector:@selector(compare:)];
        summary[@"fieldNamesOnly"] = [safeKeys copy];
    }
    return [summary copy];
}

static id BHTDetailedWriteGraphQLErrorCode(NSDictionary* error) {
    id code = error[@"code"];
    NSDictionary* extensions = [error[@"extensions"]
        isKindOfClass:NSDictionary.class]
        ? error[@"extensions"]
        : nil;
    if (!code) code = extensions[@"code"];
    return [code isKindOfClass:NSNumber.class]
        ? code
        : NSNull.null;
}

static NSString* BHTDetailedWriteGraphQLPathCategory(id path) {
    if (![path isKindOfClass:NSArray.class]) return @"unavailable";
    for (id component in (NSArray*)path) {
        if (![component isKindOfClass:NSString.class]) continue;
        NSString* normalized =
            BHTDetailedReplyNormalizedKey(component);
        if ([normalized isEqualToString:@"createtweet"] ||
            [normalized isEqualToString:@"createtweetwithundo"]) {
            return @"createTweet";
        }
    }
    return @"other";
}

static NSArray<NSDictionary*>* BHTDetailedWriteServerErrorSummaries(
    id JSON,
    NSUInteger* truncations) {
    if (![JSON isKindOfClass:NSDictionary.class]) return @[];
    id errorsValue = ((NSDictionary*)JSON)[@"errors"];
    if (![errorsValue isKindOfClass:NSArray.class]) return @[];
    NSArray* errors = errorsValue;
    NSUInteger count = MIN(errors.count, (NSUInteger)8);
    NSMutableArray* summaries = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) {
        NSDictionary* error = [errors[index]
            isKindOfClass:NSDictionary.class]
            ? errors[index]
            : nil;
        if (!error) {
            [summaries addObject:@{ @"state": @"nonObjectError" }];
            continue;
        }
        NSDictionary* extensions = [error[@"extensions"]
            isKindOfClass:NSDictionary.class]
            ? error[@"extensions"]
            : @{};
        NSString* message = [error[@"message"]
            isKindOfClass:NSString.class]
            ? error[@"message"]
            : nil;
        NSString* name = [extensions[@"name"]
            isKindOfClass:NSString.class]
            ? extensions[@"name"]
            : ([error[@"name"] isKindOfClass:NSString.class]
                   ? error[@"name"]
                   : nil);
        NSString* kind = [extensions[@"kind"]
            isKindOfClass:NSString.class]
            ? extensions[@"kind"]
            : nil;
        NSString* source = [extensions[@"source"]
            isKindOfClass:NSString.class]
            ? extensions[@"source"]
            : nil;
        [summaries addObject:@{
            @"numericCode": BHTDetailedWriteGraphQLErrorCode(error),
            @"messageCategory":
                BHTDetailedWriteServerStringCategory(message),
            @"messageRetained": @NO,
            @"nameCategory":
                BHTDetailedWriteServerStringCategory(name),
            @"kindCategory":
                BHTDetailedWriteServerStringCategory(kind),
            @"sourceCategory":
                BHTDetailedWriteServerStringCategory(source),
            @"pathCategory":
                BHTDetailedWriteGraphQLPathCategory(error[@"path"]),
            @"extensionFieldNamesOnly": ({
                NSMutableArray* keys = [NSMutableArray array];
                for (id key in extensions.allKeys) {
                    if (keys.count >= 32) break;
                    [keys addObject:BHTDetailedWriteSafeSchemaKey(key)];
                }
                [keys sortUsingSelector:@selector(compare:)];
                [keys copy];
            }),
        }];
    }
    if (errors.count > count && truncations) (*truncations)++;
    return [summaries copy];
}

static NSDictionary* BHTDetailedWriteDecodedApplication(
    id response,
    id model,
    id parseError,
    id APIErrors,
    NSString* bindingMethod,
    NSUInteger* truncations,
    BOOL* responseAccessorsObserved) {
    BOOL accessorsObserved = NO;
    NSData* data = BHTDetailedReplyResponseData(
        response, &accessorsObserved);
    NSMutableDictionary* application = [NSMutableDictionary dictionary];
    application[@"state"] = @"decodedResponseCaptured";
    application[@"bindingMethod"] = bindingMethod ?: @"unknown";
    application[@"modelClass"] = model
        ? (NSStringFromClass([model class]) ?: @"unknown")
        : @"absent";
    application[@"parseError"] =
        BHTDetailedWriteSafeObjectSummary(parseError);
    application[@"apiErrors"] =
        BHTDetailedWriteSafeObjectSummary(APIErrors);
    application[@"responseLimitBytes"] =
        @(BHTDetailedReplyResponseLimit);
    application[@"responseTextAndIdentifiersRetained"] = @NO;

    if (!data) {
        application[@"responseJSONState"] = @"infoDataUnavailable";
    } else if (data.length > BHTDetailedReplyResponseLimit) {
        application[@"responseJSONState"] = @"overLimitOmitted";
        if (truncations) (*truncations)++;
    } else {
        id JSON = [NSJSONSerialization JSONObjectWithData:data
                                                  options:0
                                                    error:nil];
        if (JSON) {
            NSMutableArray* responsePaths = [NSMutableArray array];
            application[@"responseJSONState"] =
                @"parsedToValueFreeSchema";
            application[@"responseSchema"] =
                BHTDetailedWriteSchemaForValue(
                    JSON, 0, responsePaths, @"response",
                    truncations);
            NSArray* serverErrors =
                BHTDetailedWriteServerErrorSummaries(JSON, truncations);
            application[@"serverErrors"] = serverErrors;
            application[@"graphqlErrorsPresent"] =
                @(serverErrors.count > 0);
            id dataValue = [JSON isKindOfClass:NSDictionary.class]
                ? ((NSDictionary*)JSON)[@"data"]
                : nil;
            application[@"graphqlDataPresent"] =
                @(dataValue != nil && dataValue != NSNull.null);
        } else {
            application[@"responseJSONState"] = @"nonJSONOmitted";
        }
    }
    if (responseAccessorsObserved) {
        *responseAccessorsObserved = accessorsObserved;
    }
    return [application copy];
}

static BOOL BHTDetailedWriteValidateApplicationToken(
    NSDictionary* token,
    NSUInteger* captureEpoch,
    NSString** writeKind) {
    if (![token isKindOfClass:NSDictionary.class]) return NO;
    NSNumber* epoch = token[@"captureEpoch"];
    NSString* kind = token[@"writeKind"];
    if (![epoch isKindOfClass:NSNumber.class] ||
        (![kind isEqualToString:@"standalone"] &&
         ![kind isEqualToString:@"reply"])) {
        return NO;
    }
    if (captureEpoch) *captureEpoch = epoch.unsignedIntegerValue;
    if (writeKind) *writeKind = kind;
    return YES;
}

void BHTDetailedReplyDiagnosticsCaptureBoundDecodedResponse(
    NSDictionary* applicationToken,
    id response,
    id model,
    id parseError,
    id APIErrors) {
    NSUInteger tokenEpoch = 0;
    NSString* writeKind = nil;
    if (!response ||
        !BHTDetailedWriteValidateApplicationToken(
            applicationToken, &tokenEpoch, &writeKind)) {
        return;
    }
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        NSDictionary* attempt =
            [BHTDetailedReplyCapture[@"attempts"][writeKind]
                isKindOfClass:NSDictionary.class]
            ? BHTDetailedReplyCapture[@"attempts"][writeKind]
            : nil;
        if (tokenEpoch != BHTDetailedReplyCaptureEpoch || !attempt) return;
    }

    NSUInteger truncations = 0;
    BOOL responseAccessorsObserved = NO;
    NSDictionary* application = BHTDetailedWriteDecodedApplication(
        response, model, parseError, APIErrors,
        @"originalTFSRequestObjectIdentity", &truncations,
        &responseAccessorsObserved);

    @synchronized(BHTDetailedReplyLock()) {
        if (tokenEpoch != BHTDetailedReplyCaptureEpoch ||
            !BHTDetailedReplyCapture) {
            return;
        }
        NSMutableDictionary* capture =
            [BHTDetailedReplyCapture mutableCopy];
        NSMutableDictionary* attempts =
            [capture[@"attempts"] mutableCopy];
        NSMutableDictionary* attempt = [attempts[writeKind] mutableCopy];
        if (!attempt) return;
        attempt[@"applicationResponse"] = application;
        attempt[@"applicationOutcomeBoundByOriginalRequestIdentity"] = @YES;
        attempts[writeKind] = [attempt copy];
        capture[@"attempts"] = [attempts copy];
        BHTDetailedReplyCapture = [capture copy];
        BHTDetailedReplyTruncationCount += truncations;
        BHTDetailedReplyResponseAccessorsObserved =
            BHTDetailedReplyResponseAccessorsObserved ||
            responseAccessorsObserved;
        if ([BHTDetailedPendingApplicationToken isEqual:applicationToken]) {
            BHTDetailedPendingApplicationToken = nil;
        }
        BHTDetailedReplyCaptureState = [writeKind isEqualToString:@"reply"]
            ? @"replyDecodedResponseCaptured"
            : @"standaloneDecodedResponseCaptured";
        BHTDetailedWriteRebuildComparisonLocked();
    }
}

void BHTDetailedReplyDiagnosticsCaptureDecodedResponse(
    NSUInteger sessionGeneration,
    id response,
    id model,
    id parseError,
    id APIErrors) {
    if (sessionGeneration == 0 || !response) return;

    BOOL accepted = NO;
    NSUInteger acceptedEpoch = 0;
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        NSDictionary* attempts = [BHTDetailedReplyCapture[@"attempts"]
            isKindOfClass:NSDictionary.class]
            ? BHTDetailedReplyCapture[@"attempts"]
            : nil;
        if (BHTDetailedReplyArmed && !attempts[@"reply"]) {
            BHTDetailedReplySessionGeneration = sessionGeneration;
            if (BHTDetailedReplyCaptureStartedAt <= 0) {
                BHTDetailedReplyCaptureStartedAt =
                    BHTDetailedReplyNow();
                BHTDetailedReplyScheduleExpiryLocked();
            }
            BHTDetailedReplyCaptureState = @"capturingDecodedResponse";
            NSMutableDictionary* capture =
                [BHTDetailedReplyCapture mutableCopy] ?:
                    [NSMutableDictionary dictionary];
            NSMutableDictionary* mutableAttempts =
                [attempts mutableCopy] ?:
                    [NSMutableDictionary dictionary];
            mutableAttempts[@"reply"] = @{
                @"writeKind": @"reply",
                @"request": @{
                    @"state": @"networkRequestCheckpointNotObserved",
                    @"nativeReplyWindowCorrelated": @YES,
                    @"capturesTextOrIdentifierValues": @NO,
                },
                @"network": @{ @"state": @"notObserved" },
                @"applicationResponse": @{
                    @"state": @"decoderCapturePending",
                },
            };
            capture[@"attempts"] = [mutableAttempts copy];
            BHTDetailedReplyCapture = [capture copy];
            accepted = YES;
        } else if (BHTDetailedReplySessionGeneration ==
                       sessionGeneration &&
                   attempts[@"reply"]) {
            accepted = YES;
        }
        if (accepted) acceptedEpoch = BHTDetailedReplyCaptureEpoch;
    }
    if (!accepted) return;

    NSUInteger truncations = 0;
    BOOL responseAccessorsObserved = NO;
    NSMutableDictionary* application =
        [BHTDetailedWriteDecodedApplication(
            response, model, parseError, APIErrors,
            @"legacyReplyWorkflowWindow", &truncations,
            &responseAccessorsObserved) mutableCopy];
    application[@"replyAttemptToken"] = @(acceptedEpoch);
    application[@"sessionGeneration"] = @(sessionGeneration);

    @synchronized(BHTDetailedReplyLock()) {
        if (BHTDetailedReplyCaptureEpoch != acceptedEpoch ||
            BHTDetailedReplySessionGeneration != sessionGeneration) {
            return;
        }
        NSMutableDictionary* capture =
            [BHTDetailedReplyCapture mutableCopy];
        NSMutableDictionary* attempts =
            [capture[@"attempts"] mutableCopy];
        NSMutableDictionary* replyAttempt =
            [attempts[@"reply"] mutableCopy];
        if (!replyAttempt) return;
        replyAttempt[@"applicationResponse"] = [application copy];
        attempts[@"reply"] = [replyAttempt copy];
        capture[@"attempts"] = [attempts copy];
        BHTDetailedReplyCapture = [capture copy];
        BHTDetailedReplyTruncationCount += truncations;
        BHTDetailedReplyResponseAccessorsObserved =
            BHTDetailedReplyResponseAccessorsObserved ||
            responseAccessorsObserved;
        BHTDetailedReplyCaptureState = @"decodedResponseCaptured";
        BHTDetailedWriteRebuildComparisonLocked();
    }
}

static NSDictionary* BHTDetailedWritePreparedApplication(
    BOOL observationComplete,
    id effectiveModel,
    id effectiveParseError,
    id effectiveOperationError,
    id effectiveAPIErrors,
    id finalModel,
    id finalParseError,
    id finalOperationError,
    id finalAPIErrors,
    NSString* bindingMethod) {
    return @{
        @"observationComplete": @(observationComplete),
        @"bindingMethod": bindingMethod ?: @"unknown",
        @"effectiveModelClass": effectiveModel
            ? (NSStringFromClass([effectiveModel class]) ?: @"unknown")
            : @"absent",
        @"effectiveParseError":
            BHTDetailedWriteSafeObjectSummary(effectiveParseError),
        @"effectiveOperationError":
            BHTDetailedWriteSafeObjectSummary(effectiveOperationError),
        @"effectiveAPIErrors":
            BHTDetailedWriteSafeObjectSummary(effectiveAPIErrors),
        @"finalModelClass": finalModel
            ? (NSStringFromClass([finalModel class]) ?: @"unknown")
            : @"absent",
        @"finalParseError":
            BHTDetailedWriteSafeObjectSummary(finalParseError),
        @"finalOperationError":
            BHTDetailedWriteSafeObjectSummary(finalOperationError),
        @"finalAPIErrors":
            BHTDetailedWriteSafeObjectSummary(finalAPIErrors),
        @"descriptionsAndUserInfoRetained": @NO,
    };
}

void BHTDetailedReplyDiagnosticsCaptureBoundPreparedResponse(
    NSDictionary* applicationToken,
    BOOL observationComplete,
    id effectiveModel,
    id effectiveParseError,
    id effectiveOperationError,
    id effectiveAPIErrors,
    id finalModel,
    id finalParseError,
    id finalOperationError,
    id finalAPIErrors) {
    NSUInteger tokenEpoch = 0;
    NSString* writeKind = nil;
    if (!BHTDetailedWriteValidateApplicationToken(
            applicationToken, &tokenEpoch, &writeKind)) {
        return;
    }
    NSDictionary* prepared = BHTDetailedWritePreparedApplication(
        observationComplete, effectiveModel, effectiveParseError,
        effectiveOperationError, effectiveAPIErrors, finalModel,
        finalParseError, finalOperationError, finalAPIErrors,
        @"originalTFSRequestObjectIdentity");
    @synchronized(BHTDetailedReplyLock()) {
        if (tokenEpoch != BHTDetailedReplyCaptureEpoch ||
            !BHTDetailedReplyCapture) {
            return;
        }
        NSMutableDictionary* capture =
            [BHTDetailedReplyCapture mutableCopy];
        NSMutableDictionary* attempts =
            [capture[@"attempts"] mutableCopy];
        NSMutableDictionary* attempt = [attempts[writeKind] mutableCopy];
        if (!attempt) return;
        attempt[@"prepared"] = prepared;
        attempt[@"applicationOutcomeBoundByOriginalRequestIdentity"] = @YES;
        attempts[writeKind] = [attempt copy];
        capture[@"attempts"] = [attempts copy];
        BHTDetailedReplyCapture = [capture copy];
        BHTDetailedReplyCaptureState = [writeKind isEqualToString:@"reply"]
            ? @"replyPreparedResponseCaptured"
            : @"standalonePreparedResponseCaptured";
        BHTDetailedWriteRebuildComparisonLocked();
    }
}

void BHTDetailedReplyDiagnosticsCapturePreparedResponse(
    NSUInteger sessionGeneration,
    BOOL observationComplete,
    id effectiveModel,
    id effectiveParseError,
    id effectiveOperationError,
    id effectiveAPIErrors,
    id finalModel,
    id finalParseError,
    id finalOperationError,
    id finalAPIErrors) {
    if (sessionGeneration == 0) return;
    NSUInteger acceptedEpoch = 0;
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        if (BHTDetailedReplySessionGeneration != sessionGeneration ||
            !BHTDetailedReplyCapture) {
            return;
        }
        acceptedEpoch = BHTDetailedReplyCaptureEpoch;
    }

    NSDictionary* prepared = BHTDetailedWritePreparedApplication(
        observationComplete, effectiveModel, effectiveParseError,
        effectiveOperationError, effectiveAPIErrors, finalModel,
        finalParseError, finalOperationError, finalAPIErrors,
        @"legacyReplyWorkflowWindow");

    @synchronized(BHTDetailedReplyLock()) {
        if (BHTDetailedReplyCaptureEpoch != acceptedEpoch ||
            BHTDetailedReplySessionGeneration != sessionGeneration ||
            !BHTDetailedReplyCapture) {
            return;
        }
        NSMutableDictionary* capture =
            [BHTDetailedReplyCapture mutableCopy];
        NSMutableDictionary* attempts =
            [capture[@"attempts"] mutableCopy];
        NSMutableDictionary* replyAttempt =
            [attempts[@"reply"] mutableCopy];
        if (!replyAttempt) return;
        replyAttempt[@"prepared"] = prepared;
        attempts[@"reply"] = [replyAttempt copy];
        capture[@"attempts"] = [attempts copy];
        BHTDetailedReplyCapture = [capture copy];
        BHTDetailedReplyCaptureState = @"preparedResponseCaptured";
    }
}

void BHTDetailedReplyDiagnosticsCaptureFailure(
    NSUInteger sessionGeneration,
    NSString* source,
    NSNotification* notification) {
    if (sessionGeneration == 0) return;
    NSUInteger acceptedEpoch = 0;
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        if (BHTDetailedReplySessionGeneration != sessionGeneration ||
            !BHTDetailedReplyCapture) {
            return;
        }
        acceptedEpoch = BHTDetailedReplyCaptureEpoch;
    }

    NSMutableDictionary* failure = [NSMutableDictionary dictionary];
    failure[@"source"] = source ?: @"unknown";
    failure[@"notificationPresent"] =
        @([notification isKindOfClass:NSNotification.class]);
    if ([notification isKindOfClass:NSNotification.class]) {
        NSString* name = notification.name ?: @"";
        failure[@"notificationNameFingerprint"] =
            BHTDetailedWriteFingerprint(name) ?: NSNull.null;
        failure[@"notificationUserInfo"] =
            BHTDetailedWriteSafeObjectSummary(notification.userInfo);
    }
    failure[@"notificationNameAndValuesRetained"] = @NO;

    @synchronized(BHTDetailedReplyLock()) {
        if (BHTDetailedReplyCaptureEpoch != acceptedEpoch ||
            BHTDetailedReplySessionGeneration != sessionGeneration ||
            !BHTDetailedReplyCapture) {
            return;
        }
        NSMutableDictionary* capture =
            [BHTDetailedReplyCapture mutableCopy];
        NSMutableDictionary* attempts =
            [capture[@"attempts"] mutableCopy];
        NSMutableDictionary* replyAttempt =
            [attempts[@"reply"] mutableCopy];
        if (!replyAttempt) return;
        replyAttempt[@"failure"] = [failure copy];
        attempts[@"reply"] = [replyAttempt copy];
        capture[@"attempts"] = [attempts copy];
        BHTDetailedReplyCapture = [capture copy];
        BHTDetailedReplyCaptureState = @"failureCaptured";
        // Keep the generation open for the bounded 90-second collection
        // window so a concurrently redacting decoded response is not lost.
    }
}

void BHTDetailedReplyDiagnosticsCaptureTypedResult(
    NSUInteger sessionGeneration,
    NSString* stage,
    id status,
    id error) {
    if (sessionGeneration == 0) return;
    BOOL accepted = NO;
    NSUInteger acceptedEpoch = 0;
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        NSDictionary* attempts = [BHTDetailedReplyCapture[@"attempts"]
            isKindOfClass:NSDictionary.class]
            ? BHTDetailedReplyCapture[@"attempts"]
            : nil;
        if (BHTDetailedReplyArmed && !attempts[@"reply"]) {
            BHTDetailedReplySessionGeneration = sessionGeneration;
            if (BHTDetailedReplyCaptureStartedAt <= 0) {
                BHTDetailedReplyCaptureStartedAt =
                    BHTDetailedReplyNow();
                BHTDetailedReplyScheduleExpiryLocked();
            }
            BHTDetailedReplyCaptureState = @"capturingTypedResult";
            NSMutableDictionary* capture =
                [BHTDetailedReplyCapture mutableCopy] ?:
                    [NSMutableDictionary dictionary];
            NSMutableDictionary* mutableAttempts =
                [attempts mutableCopy] ?:
                    [NSMutableDictionary dictionary];
            mutableAttempts[@"reply"] = @{
                @"writeKind": @"reply",
                @"request": @{
                    @"state": @"networkRequestCheckpointNotObserved",
                    @"nativeReplyWindowCorrelated": @YES,
                    @"capturesTextOrIdentifierValues": @NO,
                },
                @"network": @{ @"state": @"notObserved" },
                @"applicationResponse": @{
                    @"state": @"decoderCheckpointNotObservedYet",
                },
            };
            capture[@"attempts"] = [mutableAttempts copy];
            BHTDetailedReplyCapture = [capture copy];
            accepted = YES;
        } else if (BHTDetailedReplySessionGeneration ==
                       sessionGeneration &&
                   attempts[@"reply"]) {
            accepted = YES;
        }
        if (accepted) acceptedEpoch = BHTDetailedReplyCaptureEpoch;
    }
    if (!accepted) return;

    NSDictionary* typedResult = @{
        @"stage": stage ?: @"unknown",
        @"status": BHTDetailedWriteSafeObjectSummary(status),
        @"error": BHTDetailedWriteSafeObjectSummary(error),
        @"descriptionsAndValuesRetained": @NO,
    };

    @synchronized(BHTDetailedReplyLock()) {
        if (BHTDetailedReplyCaptureEpoch != acceptedEpoch ||
            BHTDetailedReplySessionGeneration != sessionGeneration ||
            !BHTDetailedReplyCapture) {
            return;
        }
        NSMutableDictionary* capture =
            [BHTDetailedReplyCapture mutableCopy];
        NSMutableDictionary* attempts =
            [capture[@"attempts"] mutableCopy];
        NSMutableDictionary* replyAttempt =
            [attempts[@"reply"] mutableCopy];
        if (!replyAttempt) return;
        NSMutableArray* stages =
            [replyAttempt[@"typedResultStages"] mutableCopy] ?:
                [NSMutableArray array];
        if (stages.count < 8) {
            [stages addObject:typedResult];
        }
        replyAttempt[@"typedResultStages"] = [stages copy];
        attempts[@"reply"] = [replyAttempt copy];
        capture[@"attempts"] = [attempts copy];
        BHTDetailedReplyCapture = [capture copy];
        BHTDetailedReplyCaptureState = @"typedResultCaptured";
    }
}

NSDictionary* BHTDetailedReplyDiagnosticSnapshot(void) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        return @{
            @"schemaVersion": @2,
            @"mode": @"temporary_paired_native_write_beta50",
            @"temporaryInvasiveBeta": @NO,
            @"containsSensitivePersonalData": @NO,
            @"captureState": BHTDetailedReplyCaptureState ?: @"unknown",
            @"armed": @(BHTDetailedReplyArmed),
            @"includedOnlyByExplicitDetailedExport": @YES,
            @"pairedCapture": BHTDetailedReplyCapture ?: NSNull.null,
            @"responseInfoDataAccessorsObserved":
                @(BHTDetailedReplyResponseAccessorsObserved),
            @"redactionCount": @(BHTDetailedReplyRedactionCount),
            @"truncationCount": @(BHTDetailedReplyTruncationCount),
            @"limits": @{
                @"attempts": @2,
                @"attemptsPerKind": @1,
                @"armLifetimeSeconds": @(BHTDetailedReplyArmLifetime),
                @"collectionLifetimeSeconds":
                    @(BHTDetailedReplyCollectionLifetime),
                @"exportLifetimeSeconds":
                    @(BHTDetailedReplyExportLifetime),
                @"responseBytes": @(BHTDetailedReplyResponseLimit),
                @"requestBytes": @(BHTDetailedWriteRequestLimit),
                @"maximumDepth": @(BHTDetailedReplyMaximumDepth),
                @"dictionaryKeys":
                    @(BHTDetailedReplyMaximumDictionaryKeys),
                @"arrayElements":
                    @(BHTDetailedReplyMaximumArrayElements),
                @"stringCharacters":
                    @(BHTDetailedReplyMaximumStringLength),
                @"requestSchemaDepth":
                    @(BHTDetailedWriteMaximumSchemaDepth),
                @"requestSchemaKeys":
                    @(BHTDetailedWriteMaximumSchemaKeys),
            },
            @"exclusions": @{
                @"passwordsAndCredentialValues": @YES,
                @"authorizationHeaders": @YES,
                @"requestAndResponseHeaders": @YES,
                @"cookiesAndWebKitStorage": @YES,
                @"authenticationTokens": @YES,
                @"rawNonJSONResponseBytes": @YES,
                @"rawRequestBodies": @YES,
                @"postAndReplyText": @YES,
                @"accountHandlesAndIdentifiers": @YES,
                @"postConversationAndMediaIdentifiers": @YES,
                @"rawQueryAndPersistedIDs": @YES,
                @"rawServerErrorMessages": @YES,
                @"errorUserInfoAndDescriptions": @YES,
                @"capturedRequestAndResponseBodySizes": @YES,
                @"capturedStringLengths": @YES,
                @"unknownRawDictionaryKeys": @YES,
            },
            @"protocol": @{
                @"requiredOrder": @"standaloneThenReply",
                @"testerMustVerifyStandaloneIsVisible": @YES,
                @"originalRequestApplicationBindingHookAvailable":
                    @(atomic_load_explicit(
                        &BHTDetailedApplicationBindingHookAvailable,
                        memory_order_acquire)),
                @"standaloneApplicationOutcomeCanBeObservedByCode":
                    @(atomic_load_explicit(
                        &BHTDetailedApplicationBindingHookAvailable,
                        memory_order_acquire)),
                @"replyBeforeStandaloneRejectsCapture": @YES,
            },
            @"schemaKeyPolicy": @{
                @"knownStructuralKeysAllowlisted": @YES,
                @"unknownKeysCollapseToOpaquePlaceholder": @YES,
                @"unknownKeyValuesOrFingerprintsExported": @NO,
            },
            @"includes": @[
                @"allowlisted GraphQL structural field names and value types",
                @"a non-reversible placeholder for unknown field names",
                @"boolean feature-count buckets and allowlisted settings",
                @"safe persisted-query fingerprints",
                @"fixed account object-identity comparisons",
                @"fixed HTTP and transport categories",
                @"fixed server error categories and numeric codes",
                @"standalone-versus-reply schema differences",
            ],
        };
    }
}
