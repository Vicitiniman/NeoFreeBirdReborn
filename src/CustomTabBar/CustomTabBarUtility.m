//
//  CustomTabBarUtility.m
//  BHTwitter
//
//  Created by Bandar Alruwaili on 10/12/2023.
//

#import "CustomTabBarUtility.h"
#import "Headers/T1Headers.h"
#import "Core/BHTSettings.h"

// The Home tab is the app's landing surface, so it is always kept visible,
// pinned first, and can never end up in the hidden list.
NSString* const CustomTabBarHomePageID = @"home";

NSString* const TabPageKey = @"page";
NSString* const TabTitleKey = @"title";
NSString* const TabImageKey = @"image";
NSString* const TabPanelIDKey = @"panelID";

static NSString* const kVisibleKey = @"bh_tabs_visible";
static NSString* const kRegistryKey = @"bh_tab_registry";

// Selection list retired when hiding became implicit (not in the visible list =
// hidden); removed on sight so old installs don't keep stale data around.
static NSString* const kLegacyHiddenKey = @"bh_tabs_hidden";

@implementation CustomTabBarUtility

#pragma mark - Live capture

// Ordered union of every tab seen this session, so a tab that briefly drops out
// of a tab bar update isn't forgotten while the editor is open.
+ (NSMutableArray<NSDictionary*>*)registry {
    static NSMutableArray<NSDictionary*>* registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [NSMutableArray array];
        NSArray* saved =
            [[NSUserDefaults standardUserDefaults] arrayForKey:kRegistryKey];
        if (saved) {
            [registry addObjectsFromArray:saved];
        }
    });
    return registry;
}

+ (void)recordTabViews:(NSArray*)tabViews {
    NSMutableArray<NSDictionary*>* registry = [self registry];
    BOOL changed = NO;

    for (T1TabView* tabView in tabViews) {
        NSString* page = tabView.scribePage;
        if (page.length == 0) {
            continue;
        }

        NSString* title = tabView.title.length ? tabView.title : page;
        NSString* image = tabView.imageName ?: @"";
        if (image.length == 0) {
            // Avatar-drawn tabs (Profile) have no imageName; use the glyph the
            // native customization screen resolves for the panel.
            image = [NSClassFromString(@"T1PanelIdentity")
                        iconImageNameForPanelID:tabView.panelID]
                        ?: @"";
        }
        NSDictionary* entry = @{
            TabPageKey: page,
            TabTitleKey: title,
            TabImageKey: image,
            TabPanelIDKey: @(tabView.panelID)
        };

        NSInteger existing = NSNotFound;
        for (NSInteger i = 0; i < (NSInteger)registry.count; i++) {
            if ([registry[i][TabPageKey] isEqualToString:page]) {
                existing = i;
                break;
            }
        }

        if (existing == NSNotFound) {
            [registry addObject:entry];
            changed = YES;
        } else if (![registry[existing] isEqualToDictionary:entry]) {
            registry[existing] = entry;
            changed = YES;
        }
    }

    if (changed) {
        [[NSUserDefaults standardUserDefaults] setObject:[registry copy]
                                                  forKey:kRegistryKey];
    }
}

+ (NSArray<NSDictionary*>*)availableTabs {
    NSMutableArray<NSDictionary*>* tabs = [[self registry] mutableCopy];

    // Likes is always offered in the editor. Including its page ID in the
    // visible list is now the sole user-facing on/off control.
    NSDictionary* likes = nil;
    for (NSDictionary* entry in tabs) {
        NSString* page = entry[TabPageKey];
        if ([page isEqualToString:@"likes"]) likes = entry;
    }
    if (!likes) {
        [tabs addObject:@{
            TabPageKey: @"likes",
            TabTitleKey: @"My Likes",
            TabImageKey: @"heart_stroke",
            // X's native entry factory uses panel 6 for the Bookmarks carrier
            // backing the separate Likes destination.
            TabPanelIDKey: @(6)
        }];
    }
    return [tabs copy];
}

+ (void)recordTabMetadata:(NSArray<NSDictionary*>*)metadata {
    NSMutableArray<NSDictionary*>* registry = [self registry];
    BOOL changed = NO;
    for (NSDictionary* entry in metadata) {
        if (![entry isKindOfClass:NSDictionary.class] ||
            ![entry[TabPageKey] isKindOfClass:NSString.class] ||
            [entry[TabPageKey] length] == 0 ||
            ![entry[TabTitleKey] isKindOfClass:NSString.class] ||
            ![entry[TabImageKey] isKindOfClass:NSString.class]) continue;
        NSUInteger index = [registry indexOfObjectPassingTest:^BOOL(NSDictionary* value, NSUInteger i, BOOL* stop) {
            return [value[TabPageKey] isEqual:entry[TabPageKey]];
        }];
        if (index == NSNotFound) { [registry addObject:entry]; changed = YES; }
        else {
            NSMutableDictionary* merged = [registry[index] mutableCopy];
            [merged addEntriesFromDictionary:entry];
            if (![merged isEqualToDictionary:registry[index]]) { registry[index] = merged; changed = YES; }
        }
    }
    if (changed) [[NSUserDefaults standardUserDefaults] setObject:[registry copy] forKey:kRegistryKey];
}

+ (NSDictionary*)metadataForPage:(NSString*)pageID {
    for (NSDictionary* entry in [self availableTabs]) {
        if ([entry[TabPageKey] isEqualToString:pageID]) {
            return entry;
        }
    }
    return nil;
}

#pragma mark - Selection

+ (NSArray<NSString*>*)visiblePageIDsInOrder {
    NSArray<NSString*>* visible =
        [[NSUserDefaults standardUserDefaults] stringArrayForKey:kVisibleKey];
    if (!visible) {
        return nil;
    }

    NSMutableArray<NSString*>* pageIDs = [visible mutableCopy];
    // Home is always visible and always first.
    [pageIDs removeObject:CustomTabBarHomePageID];
    [pageIDs insertObject:CustomTabBarHomePageID atIndex:0];
    return pageIDs;
}

+ (BOOL)likesTabEnabled {
    NSArray<NSString*>* saved =
        [[NSUserDefaults standardUserDefaults] stringArrayForKey:kVisibleKey];
    if (saved) {
        return [saved containsObject:@"likes"];
    }

    // One-time compatibility with beta.8, where this lived as a Timelines
    // toggle. Once the navigation editor saves, its ordered list wins.
    id legacy =
        [[NSUserDefaults standardUserDefaults] objectForKey:@"enable_likes_tab"];
    return [legacy boolValue];
}

+ (void)setVisiblePageIDs:(NSArray<NSString*>*)visible {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:visible forKey:kVisibleKey];
    [defaults removeObjectForKey:kLegacyHiddenKey];
    // Keep the deprecated key synchronized for compatibility reports and
    // migrations from builds that still read it.
    [defaults setBool:[visible containsObject:@"likes"]
               forKey:@"enable_likes_tab"];
    [defaults synchronize];
    [BHTSettings notePreferencesChanged];
}

+ (void)resetSelection {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kVisibleKey];
    [defaults removeObjectForKey:kLegacyHiddenKey];
    [defaults setBool:NO forKey:@"enable_likes_tab"];
    [defaults synchronize];
    [BHTSettings notePreferencesChanged];
}

+ (NSArray<NSString*>*)defaultVisiblePageIDs {
    return @[@"home", @"guide", @"ntab", @"messages"];
}

@end
