//
//  BHTHookHelpers.h
//  NeoFreeBird
//
//  Shared imports and helpers for the hook files in src/Hooks.
//

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "CustomTabBar/CustomTabBarUtility.h"
#import "Download/DownloadInlineButton.h"
#import "Headers/TWHeaders.h"
#import "Padlock/AuthViewController.h"
#import "Settings/ModernSettingsViewController.h"
#import "ThemeColor/Palette.h"
#import "Compatibility/BHTHostCompatibility.h"
#import "Timeline/BHTTimelineModelRuntime.h"

// Recursive view traversal (BHTHookHelpers.m)
void EnumerateSubviewsRecursively(UIView* view,
                                  void (^block)(UIView* currentView));

// TFNDataViewItem unwrapping for timeline section filtering (BHTHookHelpers.m)
id unwrapDataViewItem(id item);

// Module header/footer cleanup for timeline section filtering (BHTHookHelpers.m)
BOOL IsModuleHeaderItem(id item);
BOOL IsModuleFooterItem(id item);
void MarkEmptiedModuleChrome(NSArray* items, NSMutableIndexSet* removed);

// Shared ad/timeline section filter (Ads.x). Timeline.x runs this before
// cleanup and Likes capture so every consumer receives the same ad-free
// snapshot without repeating a full section scan in separate hooks.
NSArray* BHTFilteredTimelineSections(
    TFNItemsDataViewController* dataViewController, NSArray* sections);

// Live square-avatar restyling (Avatars.x)
void applySquareAvatarsSetting(void);

// Custom theme color re-apply (Theme.x)
void applySelectedThemeColor(void);

// Live pinned-tabs refresh when the hide setting is toggled (Timeline.x)
void applyHideCustomTimelinesSetting(void);

// Whether the account genuinely has a panel's tab, ignoring the forced tab
// gates (FeatureSwitches.x)
BOOL panelIsGenuinelyAvailable(long long panelID);
