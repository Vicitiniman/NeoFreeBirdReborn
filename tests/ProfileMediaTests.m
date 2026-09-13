// Uses the production snapshot and feature-switch functions, extracted by
// run_native_regressions.py. No host binaries or private user data are loaded.
static BHTLikedMediaItem* media(NSString* identifier, double ratio, BOOL decoded) {
    BHTLikedMediaItem* item = [BHTLikedMediaItem new];
    item.identifier = identifier;
    item.aspectRatio = ratio;
    item.aspectRatioConfirmedByImage = decoded;
    return item;
}

static void testProfileMediaAndGrok(void) {
    // Native X 12.24.1 groups media as [Videos, Photos] and selects inner
    // index zero initially. The outer group index varies across accounts.
    NSObject* photos = [NSObject new];
    NSObject* videos = [NSObject new];
    NSObject* posts = [NSObject new];
    NSObject* premium = [NSObject new];
    NSArray* original = @[@[posts], @[premium], @[videos, photos]];
    NSArray* ordered = BHTProfileMainEntriesWithPhotosFirst(original, photos, videos);
    NSCAssert(([ordered[2] isEqualToArray:@[photos, videos]]),
              @"Photos becomes the default, and Videos remains selectable at index one");
    NSCAssert(ordered[0] == original[0] && ordered[1] == original[1],
              @"Unrelated native groups must remain untouched");
    NSCAssert(([original[2] isEqualToArray:@[videos, photos]]),
              @"Do not mutate the native provider's arrays");
    NSCAssert(BHTProfileMainEntriesWithPhotosFirst(ordered, photos, videos) == ordered,
              @"Repeated reads keep the same inner indices after choosing Videos");
    NSArray* shifted = @[@[posts], @[videos, photos]];
    NSCAssert(([BHTProfileMainEntriesWithPhotosFirst(shifted, photos, videos)[1]
                  isEqualToArray:@[photos, videos]]), @"No fixed media group index");
    NSArray* photosOnly = @[@[photos]];
    NSCAssert(BHTProfileMainEntriesWithPhotosFirst(photosOnly, photos, videos) == photosOnly,
              @"Accounts without a Videos entry retain their native tabs");
    NSArray* separated = @[@[videos], @[photos]];
    NSCAssert(BHTProfileMainEntriesWithPhotosFirst(separated, photos, videos) == separated,
              @"Never move entries between outer groups or invent an unavailable tab");
    NSCAssert(BHTProfileMainEntriesWithPhotosFirst(nil, photos, videos) == nil,
              @"Missing native groups remain missing");

    CGFloat firstRow = BHTProfileMediaOffsetForTopInset(0, 0, 320);
    NSCAssert(firstRow == -320 && firstRow + 320 == 0,
              @"Initial media starts below the expanded profile header, without clipping");
    CGFloat partiallyScrolled = BHTProfileMediaOffsetForTopInset(-240, 320, 400);
    NSCAssert(partiallyScrolled + 400 == 80,
              @"A changed header height retains its partial collapse instead of jumping to the top");
    CGFloat scrolled = BHTProfileMediaOffsetForTopInset(700, 320, 240);
    NSCAssert(scrolled + 240 == 1020,
              @"Rotation preserves the visible reading position deep in the gallery");
    NSCAssert(BHTProfileMediaOffsetForTopInset(-350, 320, 400) == -430,
              @"Preserve pull-to-refresh overscroll while the safe area updates");
    NSCAssert(BHTProfileMediaOffsetForTopInset(scrolled, 240, 240) == scrolled,
              @"Repeated layouts with unchanged insets cannot drift the gallery");
    BHTLikedMediaItem* old = media(@"photo-a", 0.5, YES);
    BHTLikedMediaItem* refreshed = media(@"photo-a", 1.0, NO);
    BHTLikedMediaItem* added = media(@"photo-b", 1.8, NO);
    NSArray* page = BHTProfileMediaSnapshot(@[refreshed, added], @[old]);
    NSCAssert(page.count == 2 && page[0] == refreshed && page[1] == added,
              @"Pagination preserves the current native ordering and metadata objects");
    NSCAssert(refreshed.aspectRatio == 0.5 && refreshed.aspectRatioConfirmedByImage,
              @"A refreshed snapshot must not turn an already decoded portrait square");
    NSCAssert(added.aspectRatio == 1.8, @"New media uses its own dimensions");
    NSCAssert([BHTProfileMediaSnapshot(@[added], page) isEqualToArray:@[added]],
              @"Deleted photos must not reappear from an old cached snapshot");
    NSCAssert(BHTProfileMediaSnapshot(@[], page).count == 0,
              @"Native empty or denied-access states clear the gallery");
    NSCAssert(BHTProfileMediaSnapshot(nil, page).count == 0, @"Nil snapshots clear safely");
    BHTLikedMediaItem* otherProfile = media(@"photo-c", 2.0, NO);
    NSArray* isolated = BHTProfileMediaSnapshot(@[otherProfile], page);
    NSCAssert(isolated.count == 1 && isolated.firstObject == otherProfile,
              @"An unrelated profile snapshot cannot inherit old images");
    BHTLikedMediaItem* video = media(@"video-a", 1.7, NO);
    NSCAssert(BHTProfileMediaSnapshot(@[video], @[]).firstObject == video,
              @"Photo and video instances keep separate snapshots");

    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    id previous = [defaults objectForKey:@"hide_grok_sidebar"];
    [defaults setBool:YES forKey:@"hide_grok_sidebar"];
    NSCAssert([FeatureSwitchOverrideValueForKey(@"grok_ios_grok_bot_sidebar_enabled") isEqual:@NO],
              @"The current GrokBotSidebarUpsell initializer must receive false");
    NSCAssert(FeatureSwitchOverrideValueForKey(@"grok_ios_grok_bot_upsells_enabled") == nil,
              @"The sidebar choice must not disable every Grok feature");
    [defaults setBool:NO forKey:@"hide_grok_sidebar"];
    NSCAssert(FeatureSwitchOverrideValueForKey(@"grok_ios_grok_bot_sidebar_enabled") == nil,
              @"Showing the promotion restores the native account gate, without forcing it on");
    if (previous) [defaults setObject:previous forKey:@"hide_grok_sidebar"];
    else [defaults removeObjectForKey:@"hide_grok_sidebar"];
    NSLog(@"PASS: profile media menu ordering, header offsets, snapshots, dimensions, isolation, and Grok promotion gate");
}
