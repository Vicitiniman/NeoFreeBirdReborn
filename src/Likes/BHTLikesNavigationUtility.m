#import "Likes/BHTLikesNavigationUtility.h"
#import "Core/BHTBundle.h"
#import "CustomTabBar/CustomTabBarUtility.h"

NSString* const BHTLikesBookmarksPageID = @"bookmarks";
NSString* const BHTLikesVideosPageID = @"videos";
NSString* const BHTLikesArticlesPageID = @"articles";
NSString* const BHTLikesPostsPageID = @"likes";
NSString* const BHTLikesNavigationSettingsDidChangeNotification =
    @"BHTLikesNavigationSettingsDidChangeNotification";

static NSString* const kBHTLikesVisibleTabsKey =
    @"bht_likes_navigation_visible";

@implementation BHTLikesNavigationUtility

+ (NSArray<NSString*>*)canonicalPageIDs {
    return @[
        BHTLikesBookmarksPageID,
        BHTLikesVideosPageID,
        BHTLikesArticlesPageID,
        BHTLikesPostsPageID
    ];
}

+ (NSArray<NSDictionary*>*)availableTabs {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    return @[
        @{
            TabPageKey: BHTLikesBookmarksPageID,
            TabTitleKey:
                [bundle localizedStringForKey:@"LIKES_NAV_BOOKMARKS_TITLE"],
            TabImageKey: @"sf:bookmark"
        },
        @{
            TabPageKey: BHTLikesVideosPageID,
            TabTitleKey:
                [bundle localizedStringForKey:@"LIKES_NAV_VIDEOS_TITLE"],
            TabImageKey: @"sf:play.rectangle"
        },
        @{
            TabPageKey: BHTLikesArticlesPageID,
            TabTitleKey:
                [bundle localizedStringForKey:@"LIKES_NAV_ARTICLES_TITLE"],
            TabImageKey: @"sf:doc.text"
        },
        @{
            TabPageKey: BHTLikesPostsPageID,
            TabTitleKey:
                [bundle localizedStringForKey:@"LIKES_NAV_LIKES_TITLE"],
            TabImageKey: @"sf:heart"
        }
    ];
}

+ (NSDictionary*)metadataForPage:(NSString*)pageID {
    for (NSDictionary* entry in [self availableTabs]) {
        if ([entry[TabPageKey] isEqualToString:pageID]) return entry;
    }
    return nil;
}

+ (NSArray<NSString*>*)visiblePageIDsInOrder {
    NSArray<NSString*>* saved = [[NSUserDefaults standardUserDefaults]
        stringArrayForKey:kBHTLikesVisibleTabsKey];
    NSArray<NSString*>* source = saved ?: [self canonicalPageIDs];
    NSSet<NSString*>* valid =
        [NSSet setWithArray:[self canonicalPageIDs]];
    NSMutableArray<NSString*>* sanitized = [NSMutableArray array];
    for (NSString* pageID in source) {
        if ([valid containsObject:pageID] &&
            ![sanitized containsObject:pageID]) {
            [sanitized addObject:pageID];
        }
    }
    // An empty native segmented controller is invalid. If old/corrupt
    // preferences contain no usable destination, restore the four safe
    // defaults instead.
    return sanitized.count ? [sanitized copy] : [self canonicalPageIDs];
}

+ (void)setVisiblePageIDs:(NSArray<NSString*>*)visible {
    NSSet<NSString*>* valid =
        [NSSet setWithArray:[self canonicalPageIDs]];
    NSMutableArray<NSString*>* sanitized = [NSMutableArray array];
    for (NSString* pageID in visible) {
        if ([valid containsObject:pageID] &&
            ![sanitized containsObject:pageID]) {
            [sanitized addObject:pageID];
        }
    }
    if (sanitized.count == 0) return;
    [[NSUserDefaults standardUserDefaults] setObject:sanitized
                                              forKey:kBHTLikesVisibleTabsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BHTLikesNavigationSettingsDidChangeNotification
                      object:nil];
}

+ (void)resetSelection {
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:kBHTLikesVisibleTabsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BHTLikesNavigationSettingsDidChangeNotification
                      object:nil];
}

+ (BOOL)waterfallEnabled {
    id value = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"likes_media_waterfall"];
    return value ? [value boolValue] : YES;
}

+ (void)setWaterfallEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults]
        setBool:enabled
         forKey:@"likes_media_waterfall"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BHTLikesNavigationSettingsDidChangeNotification
                      object:nil];
}

+ (NSInteger)originalIndexForPageID:(NSString*)pageID {
    return [[self canonicalPageIDs] indexOfObject:pageID];
}

+ (NSArray<NSString*>*)visiblePageIDsForOriginalCount:(NSInteger)originalCount {
    // The mapping is deliberately enabled only for the verified X 12.24.1
    // Activity History shape. A later build with a different native tab count
    // keeps its stock ordering instead of receiving an unsafe guessed index.
    if (originalCount != (NSInteger)[self canonicalPageIDs].count) {
        return [[self canonicalPageIDs]
            subarrayWithRange:NSMakeRange(
                0, MIN(MAX(originalCount, 0),
                       (NSInteger)[self canonicalPageIDs].count))];
    }
    return [self visiblePageIDsInOrder];
}

+ (NSInteger)originalIndexForVisibleIndex:(NSInteger)visibleIndex
                         originalCount:(NSInteger)originalCount {
    NSArray<NSString*>* visible =
        [self visiblePageIDsForOriginalCount:originalCount];
    if (visibleIndex < 0 || visibleIndex >= (NSInteger)visible.count) {
        return NSNotFound;
    }
    NSInteger original = [self originalIndexForPageID:visible[visibleIndex]];
    return original < originalCount ? original : NSNotFound;
}

+ (NSInteger)visibleIndexForOriginalIndex:(NSInteger)originalIndex
                         originalCount:(NSInteger)originalCount {
    NSArray<NSString*>* canonical = [self canonicalPageIDs];
    if (originalIndex < 0 || originalIndex >= (NSInteger)canonical.count) {
        return NSNotFound;
    }
    return [[self visiblePageIDsForOriginalCount:originalCount]
        indexOfObject:canonical[originalIndex]];
}

+ (NSInteger)visibleIndexForPageID:(NSString*)pageID
                      originalCount:(NSInteger)originalCount {
    return [[self visiblePageIDsForOriginalCount:originalCount]
        indexOfObject:pageID];
}

@end
