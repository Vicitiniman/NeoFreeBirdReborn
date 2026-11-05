//
//  BHTSettings.h
//  NeoFreeBird
//
//  Created by nyaathea
//

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString* const BHTSettingsProfileDidApplyNotification;

// Single source of truth for every user setting: per-page toggle lists,
// page titles and the default value used when a key was never toggled.
@interface BHTSettings : NSObject

+ (NSArray<NSDictionary*>*)settingsForPage:(NSString*)pageKey;
+ (NSArray<NSString*>*)allPageKeys;
+ (NSArray<NSDictionary*>*)allSearchableSettings;
+ (NSString*)titleKeyForPage:(NSString*)pageKey;
+ (NSString*)subtitleKeyForPage:(NSString*)pageKey;
+ (NSDictionary*)settingForKey:(NSString*)key;
+ (BOOL)boolForKey:(NSString*)key;
+ (NSString*)unavailableReasonKeyForPreference:(NSString*)key;
+ (NSInteger)integerForKey:(NSString*)key;

// Cheap invalidation token for hot-path setting snapshots. Callers can cache
// several related values and refresh only after a preference write.
+ (NSUInteger)preferenceGeneration;
+ (void)notePreferencesChanged;

// Preference profiles are deliberately allow-listed. They contain tweak
// settings and layout choices, never Twitter account state, credentials,
// cookies, cached media, or migration markers.
+ (NSSet<NSString*>*)exportablePreferenceKeys;
+ (NSDictionary*)preferenceProfile;
+ (nullable NSData*)preferenceProfileJSONDataWithError:
    (NSError* _Nullable* _Nullable)error;
+ (BOOL)applyPreferenceProfile:(NSDictionary*)profile
                         error:(NSError* _Nullable* _Nullable)error;

@end
