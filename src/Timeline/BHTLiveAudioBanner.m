#import "BHTLiveAudioBanner.h"
#import "Core/BHTSettings.h"
#import <objc/runtime.h>
#import <objc/message.h>

static NSHashTable* BHTLiveBannerOwners;
static NSUInteger BHTLiveBannerChecks, BHTLiveBannerHiddenChecks, BHTLiveBannerRefreshes;

BOOL BHTShouldHideLiveAudioBanner(void) {
    BHTLiveBannerChecks++;
    BOOL hidden = [BHTSettings boolForKey:@"hide_listen_live"] || [BHTSettings boolForKey:@"hide_spaces"];
    if (hidden) BHTLiveBannerHiddenChecks++;
    return hidden;
}

void BHTTrackLiveAudioBannerOwner(id owner) {
    if (!NSThread.isMainThread || !owner) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        BHTLiveBannerOwners = [NSHashTable weakObjectsHashTable];
        [NSNotificationCenter.defaultCenter addObserverForName:BHTSettingsProfileDidApplyNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification* note) { BHTRefreshLiveAudioBanner(); }];
    });
    [BHTLiveBannerOwners addObject:owner];
}

void BHTRefreshLiveAudioBanner(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ BHTRefreshLiveAudioBanner(); }); return; }
    for (id owner in BHTLiveBannerOwners.allObjects) {
        for (NSString* name in @[@"_t1_updateFleetLineVisibility", @"_t1_updateFleetlineHeaderExpandedHeight",
             @"_t1_updateFleetLineActiveHeight", @"_t1_updateTopInsetIfNeeded"]) {
            SEL selector = NSSelectorFromString(name);
            Method method = class_getInstanceMethod([owner class], selector);
            char result[16] = {0};
            if (!method || method_getNumberOfArguments(method) != 2) continue;
            method_getReturnType(method, result, sizeof(result));
            if (result[0] == 'v') { ((void (*)(id, SEL))objc_msgSend)(owner, selector); BHTLiveBannerRefreshes++; }
        }
    }
}

NSDictionary* BHTLiveAudioBannerDiagnostics(void) {
    if (!NSThread.isMainThread) {
        __block NSDictionary* result;
        dispatch_sync(dispatch_get_main_queue(), ^{ result = BHTLiveAudioBannerDiagnostics(); });
        return result;
    }
    BOOL hidden = [BHTSettings boolForKey:@"hide_listen_live"] || [BHTSettings boolForKey:@"hide_spaces"];
    return @{@"hidden": @(hidden), @"visibilityChecks": @(BHTLiveBannerChecks),
        @"hiddenChecks": @(BHTLiveBannerHiddenChecks), @"nativeRefreshCalls": @(BHTLiveBannerRefreshes),
        @"ownerCount": @(BHTLiveBannerOwners.allObjects.count), @"stopsActiveAudio": @NO};
}
