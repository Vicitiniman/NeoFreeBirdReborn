@interface BHTTestLiveBanner : NSObject
@property(nonatomic) NSUInteger calls;
@property(nonatomic) BOOL hidden;
@property(nonatomic) double topInset;
@end
@implementation BHTTestLiveBanner
- (void)_t1_updateFleetLineVisibility { self.calls++; self.hidden = BHTShouldHideLiveAudioBanner(); }
- (void)_t1_updateFleetlineHeaderExpandedHeight { self.calls++; }
- (void)_t1_updateFleetLineActiveHeight { self.calls++; }
- (void)_t1_updateTopInsetIfNeeded { self.calls++; self.topInset = self.hidden ? 0 : 64; }
@end
static void testLiveAudioBanner(void) {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    id oldLive = [defaults objectForKey:@"hide_listen_live"], oldSpaces = [defaults objectForKey:@"hide_spaces"];
    [defaults setBool:NO forKey:@"hide_spaces"];
    [defaults setBool:YES forKey:@"hide_listen_live"];
    BHTTestLiveBanner* owner = [BHTTestLiveBanner new];
    BHTTrackLiveAudioBannerOwner(owner); BHTTrackLiveAudioBannerOwner(owner);
    BHTRefreshLiveAudioBanner();
    NSCAssert(owner.hidden && owner.topInset == 0 && owner.calls == 4, @"Hide uses one set of native visibility/height/inset updates");
    [defaults setBool:NO forKey:@"hide_listen_live"];
    BHTRefreshLiveAudioBanner();
    NSCAssert(!owner.hidden && owner.topInset == 64, @"Turning the preference off restores the native strip");
    [defaults setBool:YES forKey:@"hide_spaces"];
    NSCAssert(BHTShouldHideLiveAudioBanner(), @"Existing Spaces preferences remain authoritative");
    if (oldLive) [defaults setObject:oldLive forKey:@"hide_listen_live"]; else [defaults removeObjectForKey:@"hide_listen_live"];
    if (oldSpaces) [defaults setObject:oldSpaces forKey:@"hide_spaces"]; else [defaults removeObjectForKey:@"hide_spaces"];
    NSLog(@"PASS: Listen Live hide/restore, native strip height/inset collapse and existing Spaces preference");
}
