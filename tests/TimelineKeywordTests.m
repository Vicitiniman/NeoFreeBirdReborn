// Included after the actual production extraction/matching helpers by
// run_native_regressions.py. These fixtures never load or execute X code.
@interface TFNTwitterCanonicalStatus : NSObject
@property(nonatomic, copy) NSString* originalText;
@end
@implementation TFNTwitterCanonicalStatus
@end

@interface TFSTwitterEntityUserMention : NSObject
@property(nonatomic, copy) NSString* username;
@end
@implementation TFSTwitterEntityUserMention
@end

@interface TFNTwitterStatus : NSObject
@property(nonatomic, copy) NSString* fullText;
@property(nonatomic, copy) NSString* text;
@property(nonatomic, copy) NSString* fromUserName;
@property(nonatomic, copy) NSString* fromUserFullName;
@property(nonatomic, strong) TFNTwitterCanonicalStatus* canonicalStatus;
@property(nonatomic, strong) TFNTwitterStatus* representedStatus;
@property(nonatomic, strong) TFNTwitterStatus* retweetedStatus;
@property(nonatomic, strong) TFNTwitterStatus* quotedStatus;
@property(nonatomic, copy) NSArray* entitiesRemovingUnmentioned;
@property(nonatomic, strong) id tweetContext;
@property(nonatomic, strong) id banner;
@property(nonatomic, strong) id promotedContent;
- (BOOL)isPromoted;
@end
@implementation TFNTwitterStatus
- (BOOL)isPromoted {
    return self.promotedContent != nil;
}
@end

// Mirrors the tweak's host-facing promotedContent hook: the public getter is
// masked even though X's typed backing ivar still contains the ad metadata.
@interface BHTMaskedPromotedStatus : TFNTwitterStatus
@end
@implementation BHTMaskedPromotedStatus
- (id)promotedContent {
    return nil;
}
@end

static NSUInteger BHTTopicContextReadCount = 0;

@interface BHTCountingTwitterStatus : TFNTwitterStatus
@end
@implementation BHTCountingTwitterStatus
- (id)tweetContext {
    BHTTopicContextReadCount++;
    return [super tweetContext];
}
@end

static NSUInteger BHTScribeComponentReadCount = 0;

@interface BHTCountingCleanupModule : NSObject {
@public
    NSString* _scribeComponent;
}
@end
@implementation BHTCountingCleanupModule
- (NSString*)scribeComponent {
    BHTScribeComponentReadCount++;
    return _scribeComponent;
}
@end

@interface TFNDataViewItem : NSObject
@property(nonatomic, strong) id item;
@property(nonatomic, copy) id objectIdentifier;
@property(nonatomic, strong) id sectionController;
@end
@implementation TFNDataViewItem
@end

@interface TFNTwitterTweetTopicFeedbackContext : NSObject
@end
@implementation TFNTwitterTweetTopicFeedbackContext
@end

@interface TFNTwitterTweetContext : NSObject
@property(nonatomic, strong) TFNTwitterTweetTopicFeedbackContext*
    topicFeedbackContext;
@end
@implementation TFNTwitterTweetContext
@end

@interface T1URTTimelineStatusItemViewModel : NSObject
@property(nonatomic, strong) TFNTwitterStatus* tweet;
@end
@implementation T1URTTimelineStatusItemViewModel
@end
@interface T1CompositionStatusViewModel : NSObject
@property(nonatomic, strong) TFNTwitterStatus* tweet;
@end
@implementation T1CompositionStatusViewModel
@end

static BOOL hidden(id item) {
    BOOL usernames, text;
    NSUInteger generation = [BHTForYouKeywordFilter
        filterGenerationWithUsernameFilters:&usernames postTextFilters:&text];
    return ShouldHideForYouKeywordItem(
        item, generation, usernames, text, nil, 0);
}

static BOOL hiddenForContentGeneration(
    id item, id owner, NSUInteger contentGeneration) {
    BOOL usernames, text;
    NSUInteger generation = [BHTForYouKeywordFilter
        filterGenerationWithUsernameFilters:&usernames postTextFilters:&text];
    return ShouldHideForYouKeywordItem(
        item, generation, usernames, text, owner,
        contentGeneration);
}

int main(void) {
    @autoreleasepool {
        testProfileMediaAndGrok();
        testCompatibilityLogin();
        testWebSessionSecurity();
        testWebSessionVault();
        testTimelineCleanupClassification();
        BHTTestSettingsBoolReadCount = 0;
        BHTEnabledTimelineCleanupKinds();
        BHTEnabledTimelineCleanupKinds();
        NSCAssert(BHTTestSettingsBoolReadCount == 5,
                  @"Cleanup toggles are read once per settings generation");
        [BHTSettings notePreferencesChanged];
        BHTEnabledTimelineCleanupKinds();
        NSCAssert(BHTTestSettingsBoolReadCount == 10,
                  @"A preference change refreshes the cleanup snapshot");
        [BHTForYouKeywordFilter setKeywords:@[@"grok"] forKind:BHTForYouKeywordFilterKindUsername error:nil];
        [BHTForYouKeywordFilter setKeywords:@[] forKind:BHTForYouKeywordFilterKindPostText error:nil];
        TFNTwitterStatus* status = [TFNTwitterStatus new];
        status.fullText = @"Explain this please";
        status.text = status.fullText;
        status.fromUserName = @"reader";
        T1URTTimelineStatusItemViewModel* item = [T1URTTimelineStatusItemViewModel new];
        item.tweet = status;
        BOOL promotionStatusResolved = NO;
        NSCAssert(!StatusItemPromotionDecision(
                       item, &promotionStatusResolved) &&
                       promotionStatusResolved,
                  @"An ordinary status remains visible after status resolution");
        BHTMaskedPromotedStatus* promotedStatus =
            [BHTMaskedPromotedStatus new];
        [promotedStatus setPromotedContent:[NSObject new]];
        item.tweet = promotedStatus;
        promotionStatusResolved = NO;
        NSCAssert(StatusItemPromotionDecision(
                      item, &promotionStatusResolved) &&
                      promotionStatusResolved,
                  @"Typed promoted metadata survives the masked public getter");
        item.tweet = status;
        TFNTwitterTweetContext* topicContext =
            [TFNTwitterTweetContext new];
        topicContext.topicFeedbackContext =
            [TFNTwitterTweetTopicFeedbackContext new];
        status.tweetContext = topicContext;
        NSCAssert((BHTTimelineCleanupKindsForItem(item) &
                       BHTTimelineCleanupKindTopicPost) != 0,
                  @"X 12.24.1 topic feedback metadata identifies Topic posts");
        status.tweetContext = nil;
        NSCAssert((BHTTimelineCleanupKindsForItem(item) &
                       BHTTimelineCleanupKindTopicPost) == 0,
                  @"Hydrated Topic metadata is re-evaluated");

        BHTCountingTwitterStatus* countingStatus =
            [BHTCountingTwitterStatus new];
        TFNTwitterTweetContext* countingTopicContext =
            [TFNTwitterTweetContext new];
        countingTopicContext.topicFeedbackContext =
            [TFNTwitterTweetTopicFeedbackContext new];
        countingStatus.tweetContext = countingTopicContext;
        T1URTTimelineStatusItemViewModel* countingItem =
            [T1URTTimelineStatusItemViewModel new];
        countingItem.tweet = countingStatus;
        BHTTopicContextReadCount = 0;
        NSCAssert(!BHTShouldHideTimelineCleanupItemForKinds(
                       countingItem,
                       BHTTimelineCleanupKindWhoToFollow),
                  @"Unrelated cleanup toggles leave Topic posts visible");
        NSCAssert(!BHTShouldHideTimelineCleanupItemForKinds(
                       countingItem,
                       BHTTimelineCleanupKindWhoToFollow),
                  @"Repeated unrelated classification stays visible");
        NSCAssert(BHTTopicContextReadCount == 0,
                  @"Topic metadata is skipped while its toggle is disabled");
        NSCAssert(BHTShouldHideTimelineCleanupItemForKinds(
                      countingItem,
                      BHTTimelineCleanupKindTopicPost),
                  @"Topic metadata is evaluated when requested");
        countingStatus.tweetContext = nil;
        NSCAssert(!BHTShouldHideTimelineCleanupItemForKinds(
                       countingItem,
                       BHTTimelineCleanupKindTopicPost),
                  @"Reused items cannot keep a stale Topic decision");
        NSCAssert(BHTTopicContextReadCount == 2,
                  @"Current Topic metadata is checked on each delivery");

        BHTCountingCleanupModule* cleanupModule =
            [BHTCountingCleanupModule new];
        cleanupModule->_scribeComponent = @"suggest_who_to_follow";
        BHTScribeComponentReadCount = 0;
        NSCAssert(BHTShouldHideTimelineCleanupItemForKinds(
                      cleanupModule,
                      BHTTimelineCleanupKindWhoToFollow),
                  @"Who-to-follow module controllers are classified");
        cleanupModule->_scribeComponent = @"ordinary_profile_module";
        NSCAssert(!BHTShouldHideTimelineCleanupItemForKinds(
                       cleanupModule,
                       BHTTimelineCleanupKindWhoToFollow),
                  @"Reused module controllers cannot keep a stale decision");
        NSCAssert(BHTScribeComponentReadCount == 2,
                  @"Current module identifiers are re-evaluated");

        TFNDataViewItem* wrappedModuleItem = [TFNDataViewItem new];
        wrappedModuleItem.item = [NSObject new];
        wrappedModuleItem.sectionController = cleanupModule;
        cleanupModule->_scribeComponent = @"suggest_who_to_follow";
        NSCAssert(BHTShouldHideTimelineCleanupItemForKinds(
                      wrappedModuleItem,
                      BHTTimelineCleanupKindWhoToFollow),
                  @"Paginated wrapper section identity hides module chrome");
        cleanupModule->_scribeComponent = @"ordinary_profile_module";
        wrappedModuleItem.objectIdentifier = @"who-to-follow-page-2";
        NSCAssert(BHTShouldHideTimelineCleanupItemForKinds(
                      wrappedModuleItem,
                      BHTTimelineCleanupKindWhoToFollow),
                  @"Wrapper object identifiers are classified before unwrapping");

        NSCAssert(!hidden(item), @"Ordinary posts remain visible");
        status.canonicalStatus = [TFNTwitterCanonicalStatus new];
        status.canonicalStatus.originalText = @"@Grok Explain this please";
        NSCAssert(hidden(item), @"Canonical leading mention must invalidate the earlier no-match");
        NSCAssert(hidden(item), @"The cached match stays correct");

        NSObject* timelineOwner = [NSObject new];
        TFNTwitterStatus* snapshotStatus = [TFNTwitterStatus new];
        snapshotStatus.fullText = @"ordinary text";
        snapshotStatus.canonicalStatus =
            [TFNTwitterCanonicalStatus new];
        snapshotStatus.canonicalStatus.originalText =
            @"ordinary text";
        T1URTTimelineStatusItemViewModel* snapshotItem =
            [T1URTTimelineStatusItemViewModel new];
        snapshotItem.tweet = snapshotStatus;
        NSCAssert(!hiddenForContentGeneration(
                       snapshotItem, timelineOwner, 1),
                  @"A delivered ordinary item remains visible");
        snapshotStatus.canonicalStatus.originalText =
            @"@grok newly hydrated";
        NSCAssert(hiddenForContentGeneration(
                      snapshotItem, timelineOwner, 1),
                  @"Hydrated text invalidates a same-generation no-match");
        NSCAssert(hiddenForContentGeneration(
                      snapshotItem, timelineOwner, 2),
                  @"A later section generation keeps the current match");

        [BHTForYouKeywordFilter setKeywords:@[] forKind:BHTForYouKeywordFilterKindUsername error:nil];
        [BHTForYouKeywordFilter setKeywords:@[@"grok"] forKind:BHTForYouKeywordFilterKindPostText error:nil];
        NSCAssert(hidden(item), @"The post-text filter must also cover the leading mention");
        status.canonicalStatus.originalText = @"ordinary text";
        NSCAssert(!hidden(item), @"A changed post must invalidate a cached match");
        status.quotedStatus = [TFNTwitterStatus new];
        status.quotedStatus.fullText = @"@grok";
        NSCAssert(!hidden(item), @"Quoted posts are not primary post text");
        TFSTwitterEntityUserMention* mention = [TFSTwitterEntityUserMention new];
        mention.username = @"grok";
        status.entitiesRemovingUnmentioned = @[mention];
        NSCAssert(hidden(item), @"Mention metadata must work before text hydration");
        NSCAssert(hidden(status), @"Direct native status rows must be handled");
        T1CompositionStatusViewModel* composition = [T1CompositionStatusViewModel new];
        composition.tweet = status;
        NSCAssert(hidden(composition), @"Composition rows must use their primary tweet");
        NSCAssert(!hidden(@{@"tweet": status}), @"Unknown item shapes fail open");
        status.entitiesRemovingUnmentioned = @[];
        NSCAssert(!hidden(item), @"Unmentioned users must not match");
        [BHTForYouKeywordFilter setKeywords:@[@"@grok"] forKind:BHTForYouKeywordFilterKindUsername error:nil];
        [BHTForYouKeywordFilter setKeywords:@[] forKind:BHTForYouKeywordFilterKindPostText error:nil];
        status.canonicalStatus.originalText = @"mail me at reader@grok.example";
        NSCAssert(!hidden(item), @"Email addresses are not @mentions");
        status.canonicalStatus.originalText = @"Hi (@GROK), explain this";
        NSCAssert(hidden(item), @"Punctuation and case must not prevent matching");
        [BHTForYouKeywordFilter setKeywords:@[] forKind:BHTForYouKeywordFilterKindUsername error:nil];
        NSCAssert(!hidden(item), @"Removing filters clears cached hiding decisions");

        NSArray* destinations = @[@"bookmarks", @"videos", @"articles", @"likes"];
        for (NSUInteger index = 0; index < destinations.count; index++) {
            [BHTLikesNavigationUtility setVisiblePageIDs:@[destinations[index]]];
            NSCAssert([BHTLikesNavigationUtility originalIndexForVisibleIndex:0 originalCount:4] == (NSInteger)index,
                      @"Each selected Likes destination must map to its native page");
        }
        [BHTLikesNavigationUtility setVisiblePageIDs:@[@"articles", @"bookmarks", @"likes", @"likes", @"invalid"]];
        NSCAssert(([BHTLikesNavigationUtility visiblePageIDsInOrder].count == 3), @"Duplicate/unknown destinations are discarded");
        NSCAssert([BHTLikesNavigationUtility originalIndexForVisibleIndex:0 originalCount:4] == 2, @"Articles first");
        NSCAssert([BHTLikesNavigationUtility originalIndexForVisibleIndex:1 originalCount:4] == 0, @"Bookmarks second");
        NSCAssert([BHTLikesNavigationUtility visibleIndexForOriginalIndex:3 originalCount:4] == 2, @"Likes third");
        NSCAssert([BHTLikesNavigationUtility originalIndexForVisibleIndex:3 originalCount:4] == NSNotFound, @"Out of range is rejected");
        [BHTLikesNavigationUtility resetSelection];
        NSCAssert([[BHTLikesNavigationUtility visiblePageIDsInOrder] isEqualToArray:destinations], @"Restore defaults restores every native destination");
        puts("PASS: original text, mention metadata, paginated cleanup identity, hydrated-state rechecks, row types, quoted-text isolation, filter removal, and Likes destination mapping");
    }
    return 0;
}
