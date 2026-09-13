#import <UIKit/UIKit.h>

// Adds a native X navigation entry for My Likes. Native entries (including
// Grok) remain separate and can be selected/reordered independently.
NSArray* BHTEntriesByInstallingLikesDestination(NSArray* entries);

// The Likes entry is created by X's own 12.9 navigation-entry factory. These
// helpers let the hooks identify its genuine Bookmarks carrier and replace only
// that carrier's content with the Likes surface.
BOOL BHTIsNativeLikesEntry(id entry);
void BHTRecordNativeLikesFactoryRequest(BOOL contentController);
BOOL BHTIsNativeLikesNavigationController(UIViewController* controller);
void BHTConnectNativeLikesNavigationController(UIViewController* controller,
                                               UIView* tabView);
void BHTConnectNativeLikesNavigationTree(UIViewController* root, id entry);
void BHTInstallNativeLikesNavigationController(UIViewController* controller,
                                               BOOL resetToNewest);

// True only for an Activity History controller embedded in NeoFreeBird's
// standalone Likes destination. Stock Grok/Bookmarks history stays untouched.
BOOL BHTIsManagedLikesActivityHistoryController(
    UIViewController* controller);
void BHTRefreshLikesActivityHistoryConfiguration(
    UIViewController* rootController);
void BHTRecordLikesNavigationConfiguration(NSInteger nativeCount,
                                            NSArray<NSString*>* appliedPages,
                                            NSString* state);

// Called by the timeline section hook while a private Likes timeline is active.
// Returns YES when the data controller belongs to the private Likes timeline,
// allowing the caller to suppress X's saved scroll-position restoration.
BOOL BHTCaptureLikesSections(UIViewController* dataViewController, NSArray* sections);

// Reuses the waterfall and viewer inside a native profile Photos/Videos tab.
// Each wrapper owns only the native feed supplied by that profile's factory.
UIViewController* BHTProfileMediaController(UIViewController* nativeController,
                                           NSString* mediaKind);

// Called when the real tab changes from unselected to selected. It reconnects
// the retained native controller without changing its scroll position.
void BHTActivateLikesTabView(UIView* tabView);

// Privacy-safe runtime diagnostics included in the compatibility export.
NSDictionary* BHTLikesDiagnosticsSnapshot(void);

// Applies the setting without requiring a relaunch.
void BHTRefreshVisibleAppTabs(void);

NSString* BHTLikesPageID(void);
