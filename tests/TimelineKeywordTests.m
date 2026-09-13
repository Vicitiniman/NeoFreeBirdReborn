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
@end
@implementation TFNTwitterStatus
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
    return ShouldHideForYouKeywordItem(item, generation, usernames, text);
}

int main(void) {
    @autoreleasepool {
        testProfileMediaAndGrok();
        testCompatibilityLogin();
        [BHTForYouKeywordFilter setKeywords:@[@"grok"] forKind:BHTForYouKeywordFilterKindUsername error:nil];
        [BHTForYouKeywordFilter setKeywords:@[] forKind:BHTForYouKeywordFilterKindPostText error:nil];
        TFNTwitterStatus* status = [TFNTwitterStatus new];
        status.fullText = @"Explain this please";
        status.text = status.fullText;
        status.fromUserName = @"reader";
        T1URTTimelineStatusItemViewModel* item = [T1URTTimelineStatusItemViewModel new];
        item.tweet = status;
        NSCAssert(!hidden(item), @"Ordinary posts remain visible");
        status.canonicalStatus = [TFNTwitterCanonicalStatus new];
        status.canonicalStatus.originalText = @"@Grok Explain this please";
        NSCAssert(hidden(item), @"Canonical leading mention must invalidate the earlier no-match");
        NSCAssert(hidden(item), @"The cached match stays correct");
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
        puts("PASS: original text, mention metadata, hydration/cache edits, row types, quoted-text isolation, filter removal, and Likes destination mapping");
    }
    return 0;
}
