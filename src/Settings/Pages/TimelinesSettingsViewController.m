//
//  TimelinesSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/TimelinesSettingsViewController.h"
#import "Headers/TWHeaders.h"
#import "Settings/Pages/BHTForYouKeywordFiltersViewController.h"
#import "Timeline/BHTLiveAudioBanner.h"

extern void applyHideCustomTimelinesSetting(void);

@implementation TimelinesSettingsViewController

- (NSString*)pageKey {
    return @"timelines";
}

- (void)switchChanged:(UISwitch*)sender {
    [super switchChanged:sender];
    NSString* key = BHTSettingsKeyForSwitch(sender);
    if ([key isEqualToString:@"hide_custom_timelines"]) {
        applyHideCustomTimelinesSetting();
    } else if ([key isEqualToString:@"hide_listen_live"] || [key isEqualToString:@"hide_spaces"]) {
        BHTRefreshLiveAudioBanner();
    }
}

- (void)showForYouKeywordFilters:(__unused NSDictionary*)setting {
    BHTForYouKeywordFiltersViewController* controller =
        [[BHTForYouKeywordFiltersViewController alloc]
            initWithAccount:self.account];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
