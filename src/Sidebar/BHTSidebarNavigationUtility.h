#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString* const BHTSidebarProfileItemID;
extern NSString* const BHTSidebarBlueItemID;
extern NSString* const BHTSidebarHistoryItemID;
extern NSString* const BHTSidebarCommunitiesItemID;
extern NSString* const BHTSidebarNewsItemID;
extern NSString* const BHTSidebarListsItemID;
extern NSString* const BHTSidebarChatItemID;
extern NSString* const BHTSidebarNotificationsItemID;
extern NSString* const BHTSidebarSpacesItemID;
extern NSString* const BHTSidebarFollowRequestsItemID;
extern NSString* const BHTSidebarGrokBotItemID;
extern NSString* const BHTSidebarNavigationSettingsDidChangeNotification;

FOUNDATION_EXPORT void BHTRecordSidebarDeferredApplyScheduled(void);
FOUNDATION_EXPORT void BHTRecordSidebarDeferredApplyExecuted(void);
FOUNDATION_EXPORT void BHTRecordSidebarDeferredApplyCoalesced(void);
FOUNDATION_EXPORT void BHTRecordSidebarAddAccountRefreshRequested(void);

@interface BHTSidebarNavigationUtility : NSObject

+ (NSArray<NSString*>*)canonicalItemIDs;
+ (NSArray<NSDictionary*>*)availableItems;
+ (nullable NSDictionary*)metadataForItemID:(NSString*)itemID;
+ (NSArray<NSString*>*)visibleItemIDsInOrder;
+ (void)setVisibleItemIDs:(NSArray<NSString*>*)visible;
+ (void)resetSelection;

// X 12.9's sidebar is a SwiftUI view backed by a retained
// TwitterDash.DashDataSource. These helpers keep weak references to its
// content controllers and reapply the user's layout after native rebuilds.
+ (void)registerDashContentController:(id)controller;
+ (void)applyConfigurationToDashContentController:(id)controller;
+ (void)refreshRegisteredDashContentControllers;
+ (NSDictionary<NSString*, NSNumber*>*)diagnosticSnapshot;

@end

NS_ASSUME_NONNULL_END
