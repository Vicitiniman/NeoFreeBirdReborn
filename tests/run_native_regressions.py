"""Compile production Objective-C helpers with native Foundation on macOS."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def section(source, start, end):
    return source[source.index(start):source.index(end, source.index(start))]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit-only", type=Path)
    args = parser.parse_args()
    source = (ROOT / "src/Hooks/Timeline.x").read_text(encoding="utf8")
    unit = '''#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <string.h>
#include <math.h>
#import "Timeline/BHTForYouKeywordFilter.h"
#import "Likes/BHTLikesNavigationUtility.h"
#import "Compatibility/BHTCompatibilityReporter.h"
NSString* const BHTSettingsProfileDidApplyNotification = @"TestProfileChanged";
NSString* const TabPageKey = @"page";
NSString* const TabTitleKey = @"title";
NSString* const TabImageKey = @"image";
static char kBHTForYouKeywordDecisionKey;
static id unwrapDataViewItem(id item) { return item; }
void BHTRecordForYouFilterDiagnostic(BHTForYouFilterDiagnosticEvent event) {}
'''
    unit += section(source, "@interface BHTForYouKeywordDecisionCache", "static NSMutableArray<BHTHomeTimelineRegistryEntry*>")
    unit += section(source, "static const char* SkipObjCTypeQualifiers", "static UIViewController* NearestURTTimelineController")
    unit += section(source, "static BOOL BHTIsKeywordStatusViewModel", "static BOOL BHTShouldHideForYouKeywordItemInURTController")
    media_source = (ROOT / "src/Likes/BHTLikesTab.m").read_text(encoding="utf8")
    switches = (ROOT / "src/Hooks/FeatureSwitches.x").read_text(encoding="utf8")
    unit += '''
@interface BHTLikedMediaItem : NSObject
@property(nonatomic, copy) NSString* identifier;
@property(nonatomic) double aspectRatio;
@property(nonatomic) BOOL aspectRatioConfirmedByImage;
@end
@implementation BHTLikedMediaItem
@end
@interface BHTSettings : NSObject
+ (BOOL)boolForKey:(NSString*)key;
@end
@implementation BHTSettings
+ (BOOL)boolForKey:(NSString*)key { return [NSUserDefaults.standardUserDefaults boolForKey:key]; }
@end
static BOOL ReportGenuineTabGates = NO;
static BOOL AccountIsGenuinelyPremium(void) { return NO; }
'''
    unit += section(media_source, "static NSArray<BHTLikedMediaItem*>* BHTProfileMediaSnapshot", "@protocol BHTWaterfallLayoutDelegate")
    profile_source = (ROOT / "src/Hooks/Profile.x").read_text(encoding="utf8")
    unit += section(profile_source, "static NSArray* BHTProfileMainEntriesWithPhotosFirst", "// Keep the profile's native")
    unit += section(switches, "static NSNumber* FeatureSwitchOverrideValueForKey", "// Every feature switch facade")
    unit += (ROOT / "tests/ProfileMediaTests.m").read_text(encoding="utf8")
    login_source = (ROOT / "src/Login/BHTCompatibilityLogin.m").read_text(encoding="utf8")
    unit += section(login_source, "static NSInteger BHTCompatibilityAPIErrorCode(", "static void BHTCompatibilityRecordCommandCompletion(")
    unit += section(login_source, "static NSString* BHTCompatibilityFailureCategory(", "static NSString* BHTNormalizedCompatibilityIdentifier(")
    unit += (ROOT / "tests/CompatibilityLoginTests.m").read_text(encoding="utf8")
    unit += (ROOT / "tests/TimelineKeywordTests.m").read_text(encoding="utf8")
    if args.emit_only:
        args.emit_only.write_text(unit, encoding="utf8")
        return
    with tempfile.TemporaryDirectory(prefix="nfb-native-tests-") as directory:
        base = Path(directory)
        test_source = base / "tests.m"
        test_source.write_text(unit, encoding="utf8")
        binary = base / "native-tests"
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Werror=implicit-function-declaration",
                        "-framework", "Foundation", "-I", str(ROOT / "src"), str(test_source),
                        str(ROOT / "src/Timeline/BHTForYouKeywordFilter.m"),
                        str(ROOT / "src/Likes/BHTLikesNavigationUtility.m"),
                        str(ROOT / "src/Core/BHTBundle.m"), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
