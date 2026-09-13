//
//  BHTBundle.m
//  BHTwitter
//
//  Created by BandarHelal on 07/08/2022.
//

#import "BHTBundle.h"

@interface BHTBundle ()
@property (nonatomic, strong) NSBundle* mainBundle;
@end

@implementation BHTBundle
+ (instancetype)sharedBundle {
    static BHTBundle* sharedBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager* fileManager = [NSFileManager defaultManager];
        NSURL* bundlePath = nil;
        if ([fileManager
                fileExistsAtPath:
                    @"/Library/Application Support/BHT/BHTwitter.bundle"]) {
            bundlePath = [NSURL
                fileURLWithPath:@"/Library/Application Support/BHT/BHTwitter.bundle"];
        } else if ([fileManager fileExistsAtPath:@"/var/jb/Library/Application "
                                                 @"Support/BHT/BHTwitter.bundle"]) {
            bundlePath = [NSURL
                fileURLWithPath:
                    @"/var/jb/Library/Application Support/BHT/BHTwitter.bundle"];
        } else {
            bundlePath = [[NSBundle mainBundle] URLForResource:@"BHTwitter"
                                                 withExtension:@"bundle"];
        }

        sharedBundle = [[self alloc] initWithBundlePath:bundlePath];
    });
    return sharedBundle;
}
- (instancetype)initWithBundlePath:(NSURL*)bundlePath {
    if (self = [super init]) {
        NSBundle* bundle =
            bundlePath ? [NSBundle bundleWithURL:bundlePath] : nil;
        self.mainBundle = bundle ?: [NSBundle mainBundle];
    }

    return self;
}

- (NSString*)localizedStringForKey:(NSString*)key {
    if (key.length == 0) return @"";
    NSString* value =
        [self.mainBundle localizedStringForKey:key value:key table:nil];
    if ([value isEqualToString:key]) {
        NSString* englishPath =
            [self.mainBundle pathForResource:@"en" ofType:@"lproj"];
        NSBundle* englishBundle =
            englishPath ? [NSBundle bundleWithPath:englishPath] : nil;
        NSString* english =
            [englishBundle localizedStringForKey:key
                                            value:key
                                            table:nil];
        if (english.length > 0) value = english;
    }
    return value ?: key;
}

// Fetches one of Twitter's own strings, reusing the app's translations for
// every language. These flow through the terminology rename hook like any app
// string.
- (NSString*)localizedTwitterStringForKey:(NSString*)key {
    if (key.length == 0) return @"";
    static NSBundle* twitterBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* path =
            [[NSBundle mainBundle] pathForResource:@"Localization_Localization"
                                            ofType:@"bundle"];
        twitterBundle =
            path ? [NSBundle bundleWithPath:path] : [NSBundle mainBundle];
    });
    NSString* value =
        [twitterBundle localizedStringForKey:key value:key table:nil];
    if (value.length == 0 || [value isEqualToString:key]) {
        // Host translations can disappear between X releases. Keep the
        // tweak's English fallback available for strings it still uses.
        value = [self localizedStringForKey:key];
    }
    return value ?: key;
}
- (NSURL*)pathForFile:(NSString*)fileName {
    return [self.mainBundle URLForResource:fileName withExtension:nil];
}
@end
