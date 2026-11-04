#import "Timeline/BHTTimelineCleanup.h"
#import "Timeline/BHTTimelineModelRuntime.h"

#import "Core/BHTSettings.h"
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdatomic.h>
#include <string.h>

static const NSUInteger BHTTimelineCleanupKindMask =
    BHTTimelineCleanupKindWhoToFollow |
    BHTTimelineCleanupKindPrompt |
    BHTTimelineCleanupKindDiscoverMore |
    BHTTimelineCleanupKindTopicPost |
    BHTTimelineCleanupKindTopicSuggestion;
static atomic_uint_fast64_t BHTTimelineCleanupSettingsGeneration =
    ATOMIC_VAR_INIT(0);
static atomic_uint_fast32_t BHTTimelineCleanupSettingsKinds =
    ATOMIC_VAR_INIT(BHTTimelineCleanupKindNone);

static const char* BHTCleanupUnqualifiedType(const char* type) {
    while (type && type[0] && strchr("rnNoORV", type[0])) type++;
    return type;
}

static id BHTCleanupObjectValue(id object, SEL selector,
                                const char* ivarName,
                                BOOL allowUntypedIvar) {
    if (!object) return nil;
    if (selector && [object respondsToSelector:selector]) {
        Method method = class_getInstanceMethod([object class], selector);
        char returnType[32] = {0};
        if (method) {
            method_getReturnType(method, returnType, sizeof(returnType));
        }
        const char* type = BHTCleanupUnqualifiedType(returnType);
        if (type && type[0] == '@') {
            return ((id (*)(id, SEL))objc_msgSend)(object, selector);
        }
    }

    if (!ivarName) return nil;
    Ivar ivar = class_getInstanceVariable([object class], ivarName);
    if (!ivar && ivarName[0] != '_') {
        NSString* name = [NSString stringWithUTF8String:ivarName];
        NSString* underscored = [@"_" stringByAppendingString:name];
        ivar = class_getInstanceVariable([object class],
                                         underscored.UTF8String);
    }
    if (!ivar) return nil;

    const char* type =
        BHTCleanupUnqualifiedType(ivar_getTypeEncoding(ivar));
    BOOL objectIvar = type && type[0] == '@';
    BOOL untypedIvar = !type || type[0] == '\0' || type[0] == '?';
    if (!objectIvar && !(allowUntypedIvar && untypedIvar)) return nil;
    return object_getIvar(object, ivar);
}

static NSString* BHTCleanupStringValue(id object, NSString* name) {
    id value = BHTCleanupObjectValue(
        object, NSSelectorFromString(name), name.UTF8String, NO);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static BHTTimelineCleanupKind BHTCleanupIdentifierKindsForObject(
    id object) {
    if (!object) return BHTTimelineCleanupKindNone;

    BHTTimelineCleanupKind kinds =
        BHTTimelineCleanupKindsForIdentifiers(
            NSStringFromClass([object classForCoder]),
            BHTCleanupStringValue(object, @"scribeComponent"),
            BHTCleanupStringValue(object, @"entryID"));
    NSString* objectIdentifier =
        BHTCleanupStringValue(object, @"objectIdentifier");
    if (objectIdentifier.length > 0) {
        kinds |= BHTTimelineCleanupKindsForIdentifiers(
            nil, nil, objectIdentifier);
    }
    return kinds;
}

static id BHTCleanupUnwrapItem(id item) {
    Class wrapperClass = objc_getClass("TFNDataViewItem");
    if (wrapperClass && [item isKindOfClass:wrapperClass]) {
        id unwrapped = BHTCleanupObjectValue(
            item, NSSelectorFromString(@"item"), "item", NO);
        return unwrapped ?: item;
    }
    return item;
}

static NSString* BHTCleanupNormalizedIdentifier(NSString* value) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) {
        return nil;
    }

    NSString* lower = value.lowercaseString;
    NSMutableString* normalized =
        [NSMutableString stringWithCapacity:lower.length];
    BOOL lastWasSeparator = NO;
    for (NSUInteger index = 0; index < lower.length; index++) {
        unichar character = [lower characterAtIndex:index];
        BOOL alphanumeric =
            (character >= 'a' && character <= 'z') ||
            (character >= '0' && character <= '9');
        if (alphanumeric) {
            [normalized appendFormat:@"%C", character];
            lastWasSeparator = NO;
        } else if (!lastWasSeparator && normalized.length > 0) {
            [normalized appendString:@"_"];
            lastWasSeparator = YES;
        }
    }
    while ([normalized hasSuffix:@"_"]) {
        [normalized deleteCharactersInRange:
            NSMakeRange(normalized.length - 1, 1)];
    }
    return normalized.length > 0 ? normalized : nil;
}

static BOOL BHTCleanupContainsMarker(NSString* identifier,
                                     NSString* marker) {
    if (identifier.length == 0 || marker.length == 0) return NO;
    NSRange searchRange = NSMakeRange(0, identifier.length);
    while (searchRange.length >= marker.length) {
        NSRange match = [identifier rangeOfString:marker
                                         options:0
                                           range:searchRange];
        if (match.location == NSNotFound) return NO;
        BOOL startsAtBoundary =
            match.location == 0 ||
            [identifier characterAtIndex:match.location - 1] == '_';
        NSUInteger end = NSMaxRange(match);
        BOOL endsAtBoundary =
            end == identifier.length ||
            [identifier characterAtIndex:end] == '_';
        if (startsAtBoundary && endsAtBoundary) return YES;
        NSUInteger next = match.location + 1;
        searchRange = NSMakeRange(next, identifier.length - next);
    }
    return NO;
}

static BOOL BHTCleanupContainsAnyMarker(
    NSString* identifier, NSArray<NSString*>* markers) {
    for (NSString* marker in markers) {
        if (BHTCleanupContainsMarker(identifier, marker)) return YES;
    }
    return NO;
}

static BHTTimelineCleanupKind BHTCleanupKindsForIdentifier(
    NSString* rawIdentifier) {
    NSString* identifier =
        BHTCleanupNormalizedIdentifier(rawIdentifier);
    if (identifier.length == 0) return BHTTimelineCleanupKindNone;

    BHTTimelineCleanupKind kinds = BHTTimelineCleanupKindNone;
    BOOL listRecommendationEditor =
        [identifier containsString:
            @"list_creation_recommended_users_timeline"] ||
        [identifier containsString:
            @"list_edit_recommended_users_timeline"];
    if (!listRecommendationEditor &&
        BHTCleanupContainsAnyMarker(
            identifier,
            @[@"suggest_who_to_follow", @"who_to_follow",
              @"recommended_users", @"user_recommendation",
              @"user_recommendations", @"connect_people",
              @"suggest_who_to_subscribe_module"])) {
        kinds |= BHTTimelineCleanupKindWhoToFollow;
    }

    if (BHTCleanupContainsAnyMarker(
            identifier,
            @[@"discover_more", @"related_tweets",
              @"related_posts"]) ||
        [identifier hasPrefix:@"tweetdetailrelatedtweets"] ||
        [identifier hasPrefix:@"tweet_detail_related_tweets"]) {
        kinds |= BHTTimelineCleanupKindDiscoverMore;
    }

    if (BHTCleanupContainsAnyMarker(
            identifier,
            @[@"suggest_topics_module", @"topics_to_follow",
              @"topic_recommendation", @"topic_recommendations",
              @"utt_topic_carousel", @"topic_carousel",
              @"topics_education_upsell", @"topics_upsell"])) {
        kinds |= BHTTimelineCleanupKindTopicSuggestion;
    }

    if (BHTCleanupContainsAnyMarker(
            identifier,
            @[@"relevance_prompt_module", @"community_prompt",
              @"follow_prompt", @"birdwatch_suggestion",
              @"contacts_prompt", @"contacts_sync_prompt",
              @"module_visibility_prompt",
              @"notification_push_preferences_prompt"])) {
        kinds |= BHTTimelineCleanupKindPrompt;
    }
    return kinds;
}

BHTTimelineCleanupKind BHTTimelineCleanupKindsForIdentifiers(
    NSString* className, NSString* scribeComponent,
    NSString* entryID) {
    BHTTimelineCleanupKind kinds =
        BHTCleanupKindsForIdentifier(scribeComponent) |
        BHTCleanupKindsForIdentifier(entryID);

    if ([className isEqualToString:
            @"TwitterURT.URTTimelinePromptViewModel"] ||
        [className hasSuffix:@".URTTimelinePromptViewModel"] ||
        [className isEqualToString:@"URTTimelinePromptViewModel"]) {
        kinds |= BHTTimelineCleanupKindPrompt;
    }
    if ([className isEqualToString:
            @"T1TwitterSwift.URTTimelineTopicCollectionViewModel"] ||
        [className isEqualToString:
            @"TwitterURT.URTTimelineTopicCollectionViewModel"] ||
        [className hasSuffix:
            @".URTTimelineTopicCollectionViewModel"] ||
        [className isEqualToString:
            @"URTTimelineTopicCollectionViewModel"]) {
        kinds |= BHTTimelineCleanupKindTopicSuggestion;
    }
    return kinds;
}

static id BHTCleanupStatusFromItem(id item) {
    id viewModel = BHTCleanupUnwrapItem(item);
    Class statusClass = NSClassFromString(@"TFNTwitterStatus");
    if (!statusClass || !viewModel) return nil;
    if ([viewModel isKindOfClass:statusClass]) return viewModel;

    id tweet = BHTCleanupObjectValue(
        viewModel, NSSelectorFromString(@"tweet"), "tweet", NO);
    if ([tweet isKindOfClass:statusClass]) return tweet;

    // X 12.24.1's Swift-backed status item keeps this object in an untyped
    // ivar. Permit that one known shape and validate the resolved class before
    // reading any status metadata.
    NSString* className = NSStringFromClass([viewModel classForCoder]);
    BOOL knownStatusViewModel =
        BHTIsURTStatusItemViewModel(viewModel) ||
        [className isEqualToString:
            @"T1CompositionStatusViewModel"];
    id status = BHTCleanupObjectValue(
        viewModel, NSSelectorFromString(@"status"), "status",
        knownStatusViewModel);
    return [status isKindOfClass:statusClass] ? status : nil;
}

static BOOL BHTCleanupItemHasTopicContext(id item) {
    id viewModel = BHTCleanupUnwrapItem(item);
    id status = BHTCleanupStatusFromItem(viewModel);
    for (id candidate in @[viewModel ?: NSNull.null,
                           status ?: NSNull.null]) {
        if (candidate == NSNull.null) continue;
        id banner = BHTCleanupObjectValue(
            candidate, NSSelectorFromString(@"banner"), "banner", NO);
        NSString* bannerClass =
            banner ? NSStringFromClass([banner classForCoder]) : nil;
        if ([bannerClass isEqualToString:
                @"TFNTwitterURTTimelineStatusTopicBanner"] ||
            [bannerClass hasSuffix:
                @".URTTimelineStatusTopicBanner"] ||
            [bannerClass hasSuffix:@"StatusTopicBanner"]) {
            return YES;
        }
    }

    id tweetContext = BHTCleanupObjectValue(
        status, NSSelectorFromString(@"tweetContext"),
        "tweetContext", NO);
    id topicFeedbackContext = BHTCleanupObjectValue(
        tweetContext, NSSelectorFromString(@"topicFeedbackContext"),
        "topicFeedbackContext", NO);
    if (!topicFeedbackContext) return NO;

    NSString* contextClass =
        NSStringFromClass([topicFeedbackContext classForCoder]);
    return [contextClass isEqualToString:
                @"TFNTwitterTweetTopicFeedbackContext"] ||
           [contextClass hasSuffix:@"TweetTopicFeedbackContext"];
}

static BHTTimelineCleanupKind BHTCleanupKindsForCurrentItemState(
    id item, BOOL includeTopicContext) {
    if (!item) return BHTTimelineCleanupKindNone;

    id viewModel = BHTCleanupUnwrapItem(item);
    BHTTimelineCleanupKind kinds =
        BHTCleanupIdentifierKindsForObject(viewModel);

    if (viewModel != item) {
        kinds |= BHTCleanupIdentifierKindsForObject(item);

        // X 12.24.1's paginated profile modules keep their server component
        // on TFNDataViewItem.sectionController. The visible Swift header and
        // carousel view models themselves have no Objective-C identifier
        // accessors, so preserving and checking the wrapper is essential.
        id sectionController = BHTCleanupObjectValue(
            item, NSSelectorFromString(@"sectionController"),
            "sectionController", NO);
        kinds |= BHTCleanupIdentifierKindsForObject(sectionController);
    }

    // X hydrates and can reuse timeline objects after their first sizing pass.
    // Re-read the current identifiers and topic state on each delivered pass;
    // caching a negative result can let later pages, ads, or Topic posts escape.
    if (includeTopicContext) {
        if (BHTCleanupItemHasTopicContext(viewModel)) {
            kinds |= BHTTimelineCleanupKindTopicPost;
        }
    }
    return kinds;
}

BHTTimelineCleanupKind BHTTimelineCleanupKindsForItem(id item) {
    return BHTCleanupKindsForCurrentItemState(item, YES) &
           BHTTimelineCleanupKindMask;
}

BHTTimelineCleanupKind BHTEnabledTimelineCleanupKinds(void) {
    NSUInteger generation = [BHTSettings preferenceGeneration];
    NSUInteger cachedGeneration = (NSUInteger)atomic_load_explicit(
        &BHTTimelineCleanupSettingsGeneration, memory_order_acquire);
    if (cachedGeneration == generation) {
        return (BHTTimelineCleanupKind)atomic_load_explicit(
            &BHTTimelineCleanupSettingsKinds, memory_order_relaxed);
    }

    BHTTimelineCleanupKind kinds = BHTTimelineCleanupKindNone;
    if ([BHTSettings boolForKey:@"hide_who_to_follow"]) {
        kinds |= BHTTimelineCleanupKindWhoToFollow;
    }
    if ([BHTSettings boolForKey:@"hide_timeline_prompts"]) {
        kinds |= BHTTimelineCleanupKindPrompt;
    }
    if ([BHTSettings boolForKey:@"hide_discover_more"]) {
        kinds |= BHTTimelineCleanupKindDiscoverMore;
    }
    if ([BHTSettings boolForKey:@"hide_topics"]) {
        kinds |= BHTTimelineCleanupKindTopicPost;
    }
    if ([BHTSettings boolForKey:@"hide_topics_to_follow"]) {
        kinds |= BHTTimelineCleanupKindTopicSuggestion;
    }
    atomic_store_explicit(
        &BHTTimelineCleanupSettingsKinds, (uint_fast32_t)kinds,
        memory_order_relaxed);
    atomic_store_explicit(
        &BHTTimelineCleanupSettingsGeneration,
        (uint_fast64_t)generation, memory_order_release);
    return kinds;
}

BOOL BHTShouldHideTimelineCleanupItemForKinds(
    id item, BHTTimelineCleanupKind enabledKinds) {
    if (!item || enabledKinds == BHTTimelineCleanupKindNone) return NO;
    BOOL includeTopicContext =
        (enabledKinds & BHTTimelineCleanupKindTopicPost) != 0;
    BHTTimelineCleanupKind state = BHTCleanupKindsForCurrentItemState(
        item, includeTopicContext);
    return (state & enabledKinds & BHTTimelineCleanupKindMask) != 0;
}

BOOL BHTShouldHideTimelineCleanupItem(id item) {
    return BHTShouldHideTimelineCleanupItemForKinds(
        item, BHTEnabledTimelineCleanupKinds());
}
