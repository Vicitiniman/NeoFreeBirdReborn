//
//  Ads.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import "Compatibility/BHTCompatibilityReporter.h"
#include <string.h>

static char kBHTHiddenAdCellKey;
static char kBHTRecordedAdCellKey;
static char kBHTPromotionClassDecisionKey;
static char kBHTTimelineFilterDecisionKey;

static const char* BHTUnqualifiedType(const char* type) {
    while (type && strchr("rnNoORV", type[0])) type++;
    return type;
}

static id BHTObjectForSelector(id object, SEL selector) {
    if (!object || !selector || ![object respondsToSelector:selector]) return nil;
    NSMethodSignature* signature = [object methodSignatureForSelector:selector];
    const char* returnType = BHTUnqualifiedType(signature.methodReturnType);
    if (!returnType || returnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static BOOL BHTBoolForSelector(id object, SEL selector) {
    if (!object || !selector || ![object respondsToSelector:selector]) return NO;
    NSMethodSignature* signature = [object methodSignatureForSelector:selector];
    const char* returnType = BHTUnqualifiedType(signature.methodReturnType);
    if (!returnType) return NO;
    if (returnType[0] == '@') {
        return [((id (*)(id, SEL))objc_msgSend)(object, selector) boolValue];
    }
    if (strchr("BcCsSiIlLqQ", returnType[0])) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    }
    return NO;
}

static BOOL BHTValueMarksPromotion(id value) {
    if (!value || value == NSNull.null) return NO;
    if ([value isKindOfClass:NSString.class]) return ((NSString*)value).length > 0;
    if ([value isKindOfClass:NSNumber.class]) return ((NSNumber*)value).boolValue;
    if ([value respondsToSelector:@selector(count)]) {
        return ((NSUInteger (*)(id, SEL))objc_msgSend)(value, @selector(count)) > 0;
    }
    return YES;
}

static BOOL BHTDictionaryMarksPromotion(NSDictionary* dictionary) {
    if (![dictionary isKindOfClass:NSDictionary.class]) return NO;
    for (id keyObject in dictionary) {
        NSString* key = [[keyObject description] lowercaseString];
        BOOL promotionKey = [key containsString:@"promoted"] ||
                            [key containsString:@"advertiser"] ||
                            [key isEqualToString:@"ad_metadata"] ||
                            [key isEqualToString:@"admetadata"] ||
                            [key isEqualToString:@"ad_id"] ||
                            [key isEqualToString:@"adid"];
        if (promotionKey && BHTValueMarksPromotion(dictionary[keyObject])) {
            return YES;
        }
    }
    return NO;
}

static BOOL BHTClassNameMarksPromotion(NSString* className) {
    NSString* lower = className.lowercaseString;
    return [lower containsString:@"googlenativead"] ||
           [lower containsString:@"promotedviewmodel"] ||
           [lower containsString:@"promotabletrend"] ||
           [lower hasSuffix:@"advertisementviewmodel"] ||
           [lower hasSuffix:@"adviewmodel"] ||
           [lower hasSuffix:@"adcell"];
}

// This hook is consulted from UICollectionViewCell layout methods, so avoid
// lowercasing and searching the same runtime class name on every layout pass.
static BOOL BHTClassMarksPromotion(Class cls) {
    if (!cls) return NO;
    NSNumber* cached =
        objc_getAssociatedObject(cls, &kBHTPromotionClassDecisionKey);
    if (cached) return cached.boolValue;

    BOOL marksPromotion = BHTClassNameMarksPromotion(NSStringFromClass(cls));
    objc_setAssociatedObject(cls, &kBHTPromotionClassDecisionKey,
                             @(marksPromotion),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return marksPromotion;
}

static id BHTSafeValueForKey(id object, NSString* key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

// X 12.9's status item is Swift-backed and its status storage has changed
// names across releases. Follow only promotion/status-shaped properties and
// object ivars so the detector remains bounded and does not inspect post text.
static BOOL BHTNestedObjectMarksPromotion(id object, NSUInteger depth) {
    if (!object || depth > 2) return NO;
    NSString* className = NSStringFromClass([object classForCoder]);
    if (BHTClassMarksPromotion([object classForCoder]) ||
        BHTBoolForSelector(object, @selector(isPromoted)) ||
        BHTBoolForSelector(object, NSSelectorFromString(@"isAd")) ||
        BHTBoolForSelector(object, NSSelectorFromString(@"isAdvertisement")) ||
        BHTBoolForSelector(object, NSSelectorFromString(@"isSponsored"))) {
        return YES;
    }
    if ([object isKindOfClass:NSDictionary.class] &&
        BHTDictionaryMarksPromotion(object)) {
        return YES;
    }
    if ([object isKindOfClass:NSString.class] ||
        [object isKindOfClass:NSNumber.class] ||
        [object isKindOfClass:NSArray.class] ||
        [object isKindOfClass:NSSet.class]) {
        return NO;
    }

    NSArray<NSString*>* keys = @[
        @"status", @"tweet", @"twitterStatus", @"displayedStatus",
        @"statusModel", @"statusDataSource", @"dataSource", @"model",
        @"item", @"content", @"scribeItem", @"scribeParameters",
        @"promotedContent", @"promotedMetadata", @"adMetadata",
        @"advertiser"
    ];
    for (NSString* key in keys) {
        id value = BHTSafeValueForKey(object, key);
        if (!value || value == object) continue;
        NSString* lowerKey = key.lowercaseString;
        if (([lowerKey containsString:@"promoted"] ||
             [lowerKey containsString:@"advertiser"] ||
             [lowerKey containsString:@"admetadata"]) &&
            BHTValueMarksPromotion(value)) {
            return YES;
        }
        if (BHTNestedObjectMarksPromotion(value, depth + 1)) return YES;
    }

    for (Class current = [object class]; current && current != NSObject.class;
         current = class_getSuperclass(current)) {
        unsigned int count = 0;
        Ivar* ivars = class_copyIvarList(current, &count);
        for (unsigned int index = 0; index < count; index++) {
            const char* type = BHTUnqualifiedType(ivar_getTypeEncoding(ivars[index]));
            if (!type || type[0] != '@') continue;
            const char* rawName = ivar_getName(ivars[index]);
            NSString* name = rawName
                                 ? [[NSString stringWithUTF8String:rawName]
                                       lowercaseString]
                                 : @"";
            BOOL relevant = [name containsString:@"status"] ||
                            [name containsString:@"tweet"] ||
                            [name containsString:@"promoted"] ||
                            [name containsString:@"advert"] ||
                            [name containsString:@"scribe"] ||
                            [name containsString:@"model"] ||
                            [name containsString:@"content"];
            if (!relevant) continue;
            id value = object_getIvar(object, ivars[index]);
            if (!value || value == object) continue;
            if (([name containsString:@"promoted"] ||
                 [name containsString:@"advert"]) &&
                BHTValueMarksPromotion(value)) {
                free(ivars);
                return YES;
            }
            if (BHTNestedObjectMarksPromotion(value, depth + 1)) {
                free(ivars);
                return YES;
            }
        }
        free(ivars);
    }
    return NO;
}

// Timeline items are removed from the section data before it reaches the data
// view controller, so no empty cells or gaps are left behind. This covers every
// timeline surface (home, profile, search, conversations) regardless of whether
// it renders through a table view or the newer diffable collection view path.

// The promoted state of a status item is only reachable through its Swift-side
// `status` stored property, which is still registered as an ObjC ivar.
static BOOL StatusItemIsPromoted(id item) {
    TFNTwitterStatus* status = BHTObjectForSelector(item, @selector(status));

    Ivar statusIvar = class_getInstanceVariable([item class], "status");
    if (!statusIvar) {
        statusIvar = class_getInstanceVariable([item class], "_status");
    }
    if (!statusIvar) {
        return BHTBoolForSelector(status, @selector(isPromoted));
    }

    status = status ?: object_getIvar(item, statusIvar);
    return BHTBoolForSelector(status, @selector(isPromoted));
}

// Promoted trends and event summary heroes (the image ads at the top of
// explore) carry their promotion in the Swift-side `promotedContent` stored
// property, which isn't always reflected in the scribe item.
static BOOL ItemHasPromotedContent(id item) {
    if ([item respondsToSelector:@selector(promotedContent)] &&
        ((id (*)(id, SEL))objc_msgSend)(item, @selector(promotedContent)) != nil) {
        return YES;
    }

    Ivar promotedIvar =
        class_getInstanceVariable([item class], "promotedContent");
    if (!promotedIvar) {
        promotedIvar = class_getInstanceVariable([item class], "_promotedContent");
    }
    return promotedIvar && object_getIvar(item, promotedIvar) != nil;
}

static BOOL ItemHasPromotedTrendID(id item) {
    if ([item respondsToSelector:@selector(promotedTrendID)]) {
        NSMethodSignature* signature =
            [item methodSignatureForSelector:@selector(promotedTrendID)];
        const char* returnType = signature.methodReturnType;
        if (returnType && returnType[0] == '@') {
            id trendID = ((id (*)(id, SEL))objc_msgSend)(
                item, @selector(promotedTrendID));
            return trendID != nil && ![trendID isEqual:@0] &&
                   ![trendID isEqual:@""];
        }
        if (signature.methodReturnLength > 0 &&
            signature.methodReturnLength <= sizeof(unsigned long long)) {
            unsigned long long value =
                ((unsigned long long (*)(id, SEL))objc_msgSend)(
                    item, @selector(promotedTrendID));
            return value != 0;
        }
    }

    Ivar ivar = class_getInstanceVariable([item class], "promotedTrendID");
    if (!ivar) {
        ivar = class_getInstanceVariable([item class], "_promotedTrendID");
    }
    if (!ivar) return NO;

    const char* type = ivar_getTypeEncoding(ivar);
    if (!type) return NO;
    if (type && type[0] == '@') {
        id trendID = object_getIvar(item, ivar);
        return trendID != nil && ![trendID isEqual:@0] &&
               ![trendID isEqual:@""];
    }

    unsigned long long value = 0;
    NSUInteger size = 0;
    NSGetSizeAndAlignment(type, &size, NULL);
    uint8_t* bytes = (uint8_t*)(__bridge void*)item + ivar_getOffset(ivar);
    memcpy(&value, bytes, MIN(sizeof(value), size));
    return value != 0;
}

static BOOL ScribeItemIsPromoted(id item) {
    NSDictionary* scribeItem = BHTObjectForSelector(item, @selector(scribeItem));
    NSDictionary* scribeParameters =
        BHTObjectForSelector(item, @selector(scribeParameters));
    return BHTDictionaryMarksPromotion(scribeItem) ||
           BHTDictionaryMarksPromotion(scribeParameters);
}

static BOOL ShouldHideItem(id item, NSString* location) {
    item = unwrapDataViewItem(item);
    NSString* className = NSStringFromClass([item classForCoder]);

    if ([BHTSettings boolForKey:@"hide_promoted"]) {
        if (BHTBoolForSelector(item, @selector(isPromoted)) ||
            BHTBoolForSelector(item, NSSelectorFromString(@"isAd")) ||
            BHTBoolForSelector(item, NSSelectorFromString(@"isAdvertisement")) ||
            BHTBoolForSelector(item, NSSelectorFromString(@"isSponsored")) ||
            BHTBoolForSelector(item, NSSelectorFromString(@"isPromotedContent"))) {
            return YES;
        }

        if (StatusItemIsPromoted(item) ||
            BHTClassMarksPromotion([item classForCoder]) ||
            ScribeItemIsPromoted(item) ||
            ([className isEqualToString:@"T1URTTimelineStatusItemViewModel"] &&
             BHTNestedObjectMarksPromotion(item, 0))) {
            return YES;
        }

        if ([className isEqualToString:
                           @"TwitterURT.URTTimelineGoogleNativeAdViewModel"] ||
            [className isEqualToString:@"TwitterURT.PromotableTrend"] ||
            [className isEqualToString:
                           @"T1TwitterSwift.ImmersiveGoogleNativeAdCardViewModel"] ||
            [className isEqualToString:
                           @"T1TwitterSwift.ExplorePromotedViewModel"]) {
            return YES;
        }

        if (([className isEqualToString:@"TwitterURT.URTTimelineTrendViewModel"] ||
             [className
                 isEqualToString:@"TwitterURT.URTTimelineEventSummaryViewModel"]) &&
            (ScribeItemIsPromoted(item) || ItemHasPromotedContent(item) ||
             ItemHasPromotedTrendID(item))) {
            return YES;
        }

        if (ItemHasPromotedContent(item) || ItemHasPromotedTrendID(item)) {
            return YES;
        }
    }

    if ([BHTSettings boolForKey:@"hide_premium_offer"]) {
        if ([className
                isEqualToString:@"TwitterURT.URTTimelineMessageItemViewModel"]) {
            return YES;
        }
    }

    if ([BHTSettings boolForKey:@"hide_trend_videos"] &&
        [location isEqualToString:@"OTHER"]) {
        if ([className
                isEqualToString:@"T1TwitterSwift.URTTimelineCarouselViewModel"]) {
            return YES;
        }
    }

    return NO;
}

static BOOL ShouldHideAndRecord(id item, NSString* location) {
    id unwrapped = unwrapDataViewItem(item);
    if (!unwrapped) return NO;

    // URT timeline view models are immutable after delivery, but X asks about
    // the same item from section filtering, adapter lookup, cell creation, and
    // row sizing. Cache the decision per filter settings/location so expensive
    // Swift/KVC promotion inspection runs once per item instead of per pass.
    NSUInteger settingsSignature =
        ([BHTSettings boolForKey:@"hide_promoted"] ? 1u : 0u) |
        ([BHTSettings boolForKey:@"hide_premium_offer"] ? 2u : 0u) |
        ([BHTSettings boolForKey:@"hide_trend_videos"] ? 4u : 0u);
    NSString* cacheLocation = location ?: @"";
    NSDictionary* cachedDecisions =
        objc_getAssociatedObject(unwrapped, &kBHTTimelineFilterDecisionKey);
    NSNumber* packedDecision = cachedDecisions[cacheLocation];
    if (packedDecision &&
        (packedDecision.unsignedIntegerValue >> 1) == settingsSignature) {
        return (packedDecision.unsignedIntegerValue & 1u) != 0;
    }

    BOOL hidden = ShouldHideItem(unwrapped, location);
    BHTRecordTimelineItemObservation(item, location, hidden);
    if (unwrapped != item) {
        BHTRecordTimelineItemObservation(unwrapped, location, hidden);
    }

    NSMutableDictionary* updatedDecisions =
        cachedDecisions ? [cachedDecisions mutableCopy]
                        : [NSMutableDictionary dictionaryWithCapacity:1];
    updatedDecisions[cacheLocation] =
        @((settingsSignature << 1) | (hidden ? 1u : 0u));
    objc_setAssociatedObject(unwrapped, &kBHTTimelineFilterDecisionKey,
                             [updatedDecisions copy],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return hidden;
}

NSArray* BHTFilteredTimelineSections(
    TFNItemsDataViewController* dataViewController, NSArray* sections) {
    if (!([BHTSettings boolForKey:@"hide_promoted"] ||
          [BHTSettings boolForKey:@"hide_premium_offer"] ||
          [BHTSettings boolForKey:@"hide_trend_videos"])) {
        return sections;
    }

    NSString* location =
        [dataViewController respondsToSelector:@selector(adDisplayLocation)]
            ? dataViewController.adDisplayLocation
            : nil;

    BOOL modified = NO;
    NSMutableArray* filteredSections =
        [NSMutableArray arrayWithCapacity:sections.count];

    for (id section in sections) {
        if (![section isKindOfClass:[NSArray class]]) {
            [filteredSections addObject:section];
            continue;
        }

        NSArray* items = section;
        NSUInteger count = items.count;
        NSMutableIndexSet* removed = [NSMutableIndexSet indexSet];

        for (NSUInteger i = 0; i < count; i++) {
            if (ShouldHideAndRecord(items[i], location)) {
                [removed addIndex:i];
            }
        }

        if (removed.count == 0) {
            [filteredSections addObject:section];
            continue;
        }

        MarkEmptiedModuleChrome(items, removed);

        NSMutableArray* keptItems = [items mutableCopy];
        [keptItems removeObjectsAtIndexes:removed];
        modified = YES;

        if (keptItems.count > 0) {
            [filteredSections addObject:keptItems];
        }
    }

    return modified ? filteredSections : sections;
}

static id BHTItemAtIndexPath(TFNItemsDataViewController* controller,
                             NSIndexPath* indexPath, id fallback) {
    SEL selector = NSSelectorFromString(@"itemAtIndexPath:");
    return [controller respondsToSelector:selector]
               ? ((id (*)(id, SEL, id))objc_msgSend)(controller, selector,
                                                     indexPath)
               : fallback;
}

%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections
    restoreScrollPosition:(BOOL)restoreScrollPosition {
    %orig(BHTFilteredTimelineSections(self, sections),
          restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    %orig(BHTFilteredTimelineSections(self, sections), identifiers,
          animation, completion);
}

// Some X 12.9 timelines keep their section model opaque and only expose the
// resolved item while constructing a table cell. This is the proven fallback
// used by NeoFreeBird's prior blocker: hide the cell and collapse its row even
// when the structural section path above cannot rewrite the data source.
- (id)tableViewCellForItem:(id)item atIndexPath:(NSIndexPath*)indexPath {
    id cell = %orig;
    id resolved = BHTItemAtIndexPath(self, indexPath, item);
    NSString* location = [self respondsToSelector:@selector(adDisplayLocation)]
                             ? self.adDisplayLocation
                             : nil;
    BOOL hidden = ShouldHideAndRecord(resolved, location);
    NSNumber* hiddenByBHT = objc_getAssociatedObject(cell,
                                                      &kBHTHiddenAdCellKey);
    if (hidden && [cell isKindOfClass:UIView.class]) {
        UIView* view = cell;
        view.hidden = YES;
        view.alpha = 0.0;
        view.userInteractionEnabled = NO;
        objc_setAssociatedObject(cell, &kBHTHiddenAdCellKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (hiddenByBHT.boolValue && [cell isKindOfClass:UIView.class]) {
        UIView* view = cell;
        view.hidden = NO;
        view.alpha = 1.0;
        view.userInteractionEnabled = YES;
        objc_setAssociatedObject(cell, &kBHTHiddenAdCellKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return cell;
}

- (double)tableView:(UITableView*)tableView
    heightForRowAtIndexPath:(NSIndexPath*)indexPath {
    id item = BHTItemAtIndexPath(self, indexPath, nil);
    NSString* location = [self respondsToSelector:@selector(adDisplayLocation)]
                             ? self.adDisplayLocation
                             : nil;
    return ShouldHideAndRecord(item, location) ? 0.0 : %orig;
}

%end

// X 12.9 asks the adapter registry for an adapter before a number of timeline
// items reach the section setters above.  Refusing a promoted item here closes
// that earlier path; the section filter remains as the structural fallback.
%hook TFNItemsDataViewAdapterRegistry

- (id)dataViewAdapterForItem:(id)item {
    if ([BHTSettings boolForKey:@"hide_promoted"] &&
        ShouldHideAndRecord(item, nil)) {
        return nil;
    }
    return %orig;
}

%end

// T1StatusTableSlideshowManager was removed in X 12.24.1.

// X 12.9's video session initializer accepts ad metadata separately from the
// playable media entity. Keep the real media untouched and strip only that
// promoted payload, preventing preroll/session ad construction.
%hook T1PlayerMediaEntitySessionProducible

- (id)initWithMediaEntity:(id)mediaEntity
    contentMediaIdentifier:(id)contentMediaIdentifier
           ownerIdentifier:(id)ownerIdentifier
            baseScribeItem:(id)baseScribeItem
         promotedContent:(id)promotedContent {
    if ([BHTSettings boolForKey:@"hide_promoted"]) {
        promotedContent = nil;
    }
    return %orig(mediaEntity, contentMediaIdentifier, ownerIdentifier,
                 baseScribeItem, promotedContent);
}

%end

// Swift ad-cell classes may not exist when tweak constructors run. Hooking the
// UIKit base class instead catches them whenever their module is loaded, while
// the class-name guard keeps normal collection cells untouched.
static BOOL BHTIsRenderedAdCell(id cell) {
    return [BHTSettings boolForKey:@"hide_promoted"] &&
           BHTClassMarksPromotion([cell classForCoder]);
}

static void BHTCollapseRenderedAdCell(UICollectionViewCell* cell) {
    if (!BHTIsRenderedAdCell(cell)) return;
    cell.hidden = YES;
    cell.alpha = 0.0;
    cell.userInteractionEnabled = NO;
    if (![objc_getAssociatedObject(cell, &kBHTRecordedAdCellKey) boolValue]) {
        BHTRecordTimelineItemObservation(cell, @"RENDERED_COLLECTION_CELL",
                                         YES);
        objc_setAssociatedObject(cell, &kBHTRecordedAdCellKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook UICollectionViewCell

- (void)didMoveToWindow {
    %orig;
    BHTCollapseRenderedAdCell(self);
}

- (void)layoutSubviews {
    %orig;
    BHTCollapseRenderedAdCell(self);
}

- (CGSize)sizeThatFits:(CGSize)size {
    return BHTIsRenderedAdCell(self) ? CGSizeZero : %orig;
}

- (UICollectionViewLayoutAttributes*)preferredLayoutAttributesFittingAttributes:
    (UICollectionViewLayoutAttributes*)attributes {
    UICollectionViewLayoutAttributes* result = %orig;
    if (BHTIsRenderedAdCell(self) && result) {
        result.size = CGSizeZero;
        result.hidden = YES;
    }
    return result;
}

- (void)applyLayoutAttributes:(UICollectionViewLayoutAttributes*)attributes {
    if (BHTIsRenderedAdCell(self)) {
        UICollectionViewLayoutAttributes* collapsed = [attributes copy];
        collapsed.size = CGSizeZero;
        collapsed.hidden = YES;
        %orig(collapsed);
        BHTCollapseRenderedAdCell(self);
        return;
    }
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    %orig(BHTIsRenderedAdCell(self) ? YES : hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    %orig(BHTIsRenderedAdCell(self) ? 0.0 : alpha);
}

%end

%hook TFSTwitterSspMetadata

- (BOOL)isPrerollEligible {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (id)adTagURL {
    return [BHTSettings boolForKey:@"hide_promoted"] ? nil : %orig;
}

%end

%hook TFNTwitterStatus

- (BOOL)isPoliticalAd {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (BOOL)isIssueAd {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (BOOL)isRTBCreative {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (BOOL)isPrerollContent {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (BOOL)isAdsVideoCard {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (BOOL)allowDynamicAd {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (id)sspMetadata {
    return [BHTSettings boolForKey:@"hide_promoted"] ? nil : %orig;
}

- (id)promotedContent {
    return [BHTSettings boolForKey:@"hide_promoted"] ? nil : %orig;
}

- (_Bool)isCardHidden {
    return ([BHTSettings boolForKey:@"hide_promoted"] && [self isPromoted])
               ? true
               : %orig;
}

%end
