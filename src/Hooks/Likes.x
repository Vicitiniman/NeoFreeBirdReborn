#import "HookHelpers.h"
#import "Likes/BHTLikesTab.h"
#import "Likes/BHTLikesNavigationUtility.h"

static id BHTLikesSafeValue(id object, NSString* key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

static UIImage* BHTLikesHeartImage(BOOL selected) {
    UIImageSymbolConfiguration* configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:23
                                                        weight:UIImageSymbolWeightRegular];
    UIImage* image = [UIImage systemImageNamed:selected ? @"heart.fill" : @"heart"
                              withConfiguration:configuration];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static void BHTFindLargestImageView(UIView* root, UIImageView** best,
                                    CGFloat* bestArea) {
    for (UIView* subview in root.subviews) {
        if ([subview isKindOfClass:UIImageView.class]) {
            CGSize size = subview.bounds.size;
            CGFloat area = MAX(1.0, size.width) * MAX(1.0, size.height);
            if (area > *bestArea && size.width <= 72 && size.height <= 72) {
                *best = (UIImageView*)subview;
                *bestArea = area;
            }
        }
        BHTFindLargestImageView(subview, best, bestArea);
    }
}

static UIImageView* BHTLikesIconView(T1TabView* tabView) {
    for (NSString* key in @[@"imageView", @"iconImageView", @"tabImageView"]) {
        id value = BHTLikesSafeValue(tabView, key);
        if ([value isKindOfClass:UIImageView.class]) return value;
    }
    UIImageView* best = nil;
    CGFloat bestArea = 0;
    BHTFindLargestImageView(tabView, &best, &bestArea);
    return best;
}

static void BHTApplyLikesHeartToTab(T1TabView* tabView) {
    if (![CustomTabBarUtility likesTabEnabled] ||
        ![tabView.scribePage isEqualToString:BHTLikesPageID()]) {
        return;
    }
    // The entry is a native Bookmarks carrier. X copies its original title
    // before the first selection-driven refresh, so update the live label as
    // soon as the carrier is identified instead of waiting for a tap.
    tabView.titleLabel.text = @"Likes";
    tabView.accessibilityLabel = @"Likes";

    UIImageView* imageView = BHTLikesIconView(tabView);
    if (imageView) {
        imageView.image = BHTLikesHeartImage(tabView.selected);
        imageView.contentMode = UIViewContentModeCenter;
        imageView.tintColor =
            tabView.selected ? CurrentAccentColor()
                             : [Palette currentSecondaryTextColor];
        imageView.accessibilityLabel = @"Likes";
    }
}

static void BHTApplyLikesHeartToNativeBar(T1TabBarViewController* controller) {
    if (![CustomTabBarUtility likesTabEnabled]) return;
    UITabBar* tabBar = nil;
    for (NSString* key in @[@"nativeTabBar", @"tabBar"]) {
        id value = BHTLikesSafeValue(controller, key);
        if ([value isKindOfClass:UITabBar.class]) {
            tabBar = value;
            break;
        }
    }
    NSArray* tabViews = controller.tabViews;
    NSArray<UITabBarItem*>* items = tabBar.items;
    NSUInteger count = MIN(tabViews.count, items.count);
    for (NSUInteger index = 0; index < count; index++) {
        T1TabView* tabView = tabViews[index];
        if (![tabView.scribePage isEqualToString:BHTLikesPageID()]) continue;
        UITabBarItem* item = items[index];
        item.title = @"Likes";
        item.image = BHTLikesHeartImage(NO);
        item.selectedImage = BHTLikesHeartImage(YES);
        item.accessibilityLabel = @"Likes";
    }
}

// MARK: - X 12.24.1 Activity History ordering

@interface BHTActivitySegmentedController : UIViewController
- (void)reloadDataWithSelectingIndex:(NSInteger)index;
@end

static char kBHTActivityOriginalCountKey;
static char kBHTActivityConfigurationReadyKey;
static char kBHTActivityAppliedSignatureKey;
static char kBHTActivityAppliedOrderKey;
static char kBHTActivityApplyingKey;

static NSInteger BHTActivityOriginalCount(UIViewController* controller) {
    NSNumber* count =
        objc_getAssociatedObject(controller, &kBHTActivityOriginalCountKey);
    return count ? count.integerValue : 0;
}

static void BHTRememberActivityOriginalCount(UIViewController* controller,
                                             NSInteger count) {
    if (count <= 0) return;
    objc_setAssociatedObject(controller, &kBHTActivityOriginalCountKey,
                             @(count),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (count != 4) BHTRecordLikesNavigationConfiguration(count, nil, @"unsupportedNativeTabCount");
}

static BOOL BHTActivityConfigurationActive(UIViewController* controller) {
    return BHTIsManagedLikesActivityHistoryController(controller) &&
           BHTActivityOriginalCount(controller) == 4 &&
           [objc_getAssociatedObject(
               controller, &kBHTActivityConfigurationReadyKey) boolValue];
}

static NSInteger BHTActivityOriginalIndex(UIViewController* controller,
                                          NSInteger visibleIndex) {
    if (!BHTActivityConfigurationActive(controller)) return visibleIndex;
    NSInteger mapped = [BHTLikesNavigationUtility
        originalIndexForVisibleIndex:visibleIndex
                       originalCount:BHTActivityOriginalCount(controller)];
    return mapped == NSNotFound ? visibleIndex : mapped;
}

static double BHTActivityOriginalFractionalIndex(
    UIViewController* controller, double visibleIndex) {
    if (!BHTActivityConfigurationActive(controller) || visibleIndex < 0) {
        return visibleIndex;
    }
    // X rounds this value before looking up its original page array. Mapping
    // the nearest displayed page directly avoids walking through hidden
    // intermediate native indices when the user chooses a non-linear order
    // such as Likes, Bookmarks, Articles.
    NSInteger nearest = (NSInteger)llround(visibleIndex);
    return BHTActivityOriginalIndex(controller, nearest);
}

static UIViewController* BHTFindActivitySegmentedController(
    UIViewController* controller) {
    Class wanted =
        NSClassFromString(@"TFNUISwift.LegacySegmentedViewController");
    if (wanted && [controller isKindOfClass:wanted]) return controller;
    for (UIViewController* child in controller.childViewControllers) {
        UIViewController* found =
            BHTFindActivitySegmentedController(child);
        if (found) return found;
    }
    return nil;
}

static void BHTApplyActivityHistoryConfiguration(
    UIViewController* controller) {
    if (!BHTActivityConfigurationActive(controller)) return;
    if ([objc_getAssociatedObject(controller, &kBHTActivityApplyingKey) boolValue]) return;
    NSInteger originalCount = BHTActivityOriginalCount(controller);
    NSArray<NSString*>* order = [BHTLikesNavigationUtility
        visiblePageIDsForOriginalCount:originalCount];
    NSString* signature =
        [NSString stringWithFormat:@"%ld:%@",
                                   (long)originalCount,
                                   [order componentsJoinedByString:@","]];
    NSString* applied =
        objc_getAssociatedObject(controller,
                                 &kBHTActivityAppliedSignatureKey);
    if ([applied isEqualToString:signature]) return;

    BHTActivitySegmentedController* segmented =
        (BHTActivitySegmentedController*)
            BHTFindActivitySegmentedController(controller);
    if (![segmented
            respondsToSelector:@selector(reloadDataWithSelectingIndex:)]) {
        BHTRecordLikesNavigationConfiguration(originalCount, nil, @"segmentedControllerUnavailable");
        return;
    }

    NSInteger targetIndex = [BHTLikesNavigationUtility
        visibleIndexForPageID:BHTLikesPostsPageID
                originalCount:originalCount];
    if (targetIndex == NSNotFound) targetIndex = 0;
    NSArray* oldOrder = objc_getAssociatedObject(controller, &kBHTActivityAppliedOrderKey);
    NSNumber* selected = BHTLikesSafeValue(segmented, @"selectedIndex");
    if ([selected isKindOfClass:NSNumber.class] && selected.integerValue >= 0 &&
        selected.unsignedIntegerValue < oldOrder.count) {
        NSUInteger retainedIndex = [order indexOfObject:oldOrder[selected.unsignedIntegerValue]];
        if (retainedIndex != NSNotFound) targetIndex = (NSInteger)retainedIndex;
    }
    objc_setAssociatedObject(controller, &kBHTActivityApplyingKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try {
        [segmented reloadDataWithSelectingIndex:targetIndex];
    } @finally {
        objc_setAssociatedObject(controller, &kBHTActivityApplyingKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(controller,
                             &kBHTActivityAppliedSignatureKey,
                             signature,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(controller, &kBHTActivityAppliedOrderKey, order,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    BHTRecordLikesNavigationConfiguration(originalCount, order, @"applied");
}

static void BHTPrepareActivityHistoryConfiguration(
    UIViewController* controller) {
    if (!BHTIsManagedLikesActivityHistoryController(controller)) return;
    objc_setAssociatedObject(
        controller, &kBHTActivityConfigurationReadyKey, @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void BHTRefreshLikesActivityHistoryConfiguration(
    UIViewController* rootController) {
    if (!rootController) return;
    Class activityClass = NSClassFromString(
        @"XActivityHistory.ActivityHistoryContainerViewController");
    if (activityClass &&
        [rootController isKindOfClass:activityClass]) {
        BHTPrepareActivityHistoryConfiguration(rootController);
        BHTApplyActivityHistoryConfiguration(rootController);
    }
    for (UIViewController* child in
         rootController.childViewControllers) {
        BHTRefreshLikesActivityHistoryConfiguration(child);
    }
}

// This Swift controller is the native Bookmarks / Videos / Articles / Likes
// surface. The hooks are gated by the BHTLikesViewController ancestor, so X's
// stock Activity History screen and Grok destination are never modified.
%hook _TtC16XActivityHistory38ActivityHistoryContainerViewController

- (NSInteger)numberOfTabsIn:(id)segmentedController {
    NSInteger originalCount = %orig;
    if (BHTIsManagedLikesActivityHistoryController(
            (UIViewController*)self)) {
        BHTRememberActivityOriginalCount((UIViewController*)self,
                                         originalCount);
    }
    if (!BHTActivityConfigurationActive((UIViewController*)self)) {
        return originalCount;
    }
    return [BHTLikesNavigationUtility
        visiblePageIDsForOriginalCount:originalCount].count;
}

- (UIViewController*)segmentedViewController:(id)controller
                      pageViewControllerAtIndex:(NSInteger)index {
    return %orig(controller,
                 BHTActivityOriginalIndex((UIViewController*)self, index));
}

- (id)segmentedViewController:(id)controller
             descriptorAtIndex:(NSInteger)index {
    return %orig(controller,
                 BHTActivityOriginalIndex((UIViewController*)self, index));
}

- (void)segmentedViewController:(id)controller
          willSelectViewController:(UIViewController*)viewController
                           atIndex:(NSInteger)index
                      indexChanged:(BOOL)indexChanged {
    %orig(controller, viewController,
          BHTActivityOriginalIndex((UIViewController*)self, index),
          indexChanged);
}

- (void)segmentedViewController:(id)controller
           didSelectViewController:(UIViewController*)viewController
                           atIndex:(NSInteger)index
                     previousIndex:(NSInteger)previousIndex
                           trigger:(NSInteger)trigger {
    NSInteger mappedPrevious =
        previousIndex < 0
            ? previousIndex
            : BHTActivityOriginalIndex((UIViewController*)self,
                                       previousIndex);
    %orig(controller, viewController,
          BHTActivityOriginalIndex((UIViewController*)self, index),
          mappedPrevious, trigger);
}

- (void)segmentedViewController:(id)controller
        didScrollToFractionalIndex:(double)index {
    %orig(controller,
          BHTActivityOriginalFractionalIndex(
              (UIViewController*)self, index));
}

- (void)segmentedViewController:(id)controller
                  didTapTabAtIndex:(NSInteger)index {
    %orig(controller,
          BHTActivityOriginalIndex((UIViewController*)self, index));
}

- (void)segmentedViewController:(id)controller
                didLongPressAtIndex:(NSInteger)index {
    %orig(controller,
          BHTActivityOriginalIndex((UIViewController*)self, index));
}

- (void)viewDidLoad {
    // Let X safely build its native page controller first. Enabling the
    // remap only after that transaction avoids feeding a hidden/reordered index
    // into its one-time initial-tab resolver.
    %orig;
    if (BHTIsManagedLikesActivityHistoryController(
            (UIViewController*)self)) {
        BHTPrepareActivityHistoryConfiguration(
            (UIViewController*)self);
        __weak UIViewController* weakController =
            (UIViewController*)self;
        dispatch_async(dispatch_get_main_queue(), ^{
            BHTApplyActivityHistoryConfiguration(weakController);
        });
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    BHTPrepareActivityHistoryConfiguration((UIViewController*)self);
    BHTApplyActivityHistoryConfiguration((UIViewController*)self);
}

%end

// X 12.9's navigation registry rejects an independently implemented
// Objective-C entry before sending it any protocol messages. The Likes entry is
// therefore a genuine BookmarksAppNavigationTabEntry made by X's own factory.
// These hooks keep its native lifecycle intact and replace only its controller.
%hook _TtC14T1TwitterSwift30BookmarksAppNavigationTabEntry

- (id)contentControllerFactory {
    BOOL isLikes = BHTIsNativeLikesEntry(self);
    if (isLikes) BHTRecordNativeLikesFactoryRequest(NO);
    return %orig;
}

- (UIViewController*)createContentController {
    BOOL isLikes = BHTIsNativeLikesEntry(self);
    if (isLikes) BHTRecordNativeLikesFactoryRequest(YES);
    UIViewController* controller = %orig;
    if (isLikes) {
        Class navigationClass =
            NSClassFromString(@"T1TwitterSwift.BookmarksNavigationController");
        if (navigationClass &&
            [controller isKindOfClass:navigationClass]) {
            T1TabView* tabView =
                ((id (*)(id, SEL))objc_msgSend)(self,
                                                @selector(tabView));
            BHTConnectNativeLikesNavigationController(controller, tabView);
        } else {
            BHTConnectNativeLikesNavigationTree(controller, self);
        }
    }
    return controller;
}

- (UIViewController*)rootTabViewController {
    BOOL isLikes = BHTIsNativeLikesEntry(self);
    UIViewController* root = %orig;
    if (isLikes) BHTConnectNativeLikesNavigationTree(root, self);
    return root;
}

%end

%hook _TtC14T1TwitterSwift29BookmarksNavigationController

- (id)initWithAccount:(id)account tabView:(T1TabView*)tabView {
    id controller = %orig(account, tabView);
    if ([tabView.scribePage isEqualToString:BHTLikesPageID()]) {
        BHTConnectNativeLikesNavigationController(controller, tabView);
    }
    return controller;
}

- (void)viewDidLoad {
    %orig;
    if (BHTIsNativeLikesNavigationController((UIViewController*)self)) {
        BHTInstallNativeLikesNavigationController(
            (UIViewController*)self, NO);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    if (BHTIsNativeLikesNavigationController((UIViewController*)self)) {
        BHTInstallNativeLikesNavigationController(
            (UIViewController*)self, NO);
    }
}

%end

// Capture the exact filtered snapshot sent to the private Likes timeline.
// Calling the shared filter here makes this independent of Logos hook order,
// so promoted media can never enter the custom waterfall while ad hiding is
// enabled. The native controller remains responsible for pagination.
%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restoreScrollPosition {
    NSArray* filtered =
        BHTFilteredTimelineSections(self, sections);
    BOOL isLikes =
        BHTCaptureLikesSections((UIViewController*)self, filtered);
    %orig(filtered, isLikes ? NO : restoreScrollPosition);
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    NSArray* filtered =
        BHTFilteredTimelineSections(self, sections);
    BHTCaptureLikesSections((UIViewController*)self, filtered);
    %orig(filtered, identifiers, animation, completion);
}

%end

%hook T1TabView

- (NSString*)title {
    return [self.scribePage isEqualToString:BHTLikesPageID()] ? @"My Likes" : %orig;
}

- (NSString*)imageName {
    return [self.scribePage isEqualToString:BHTLikesPageID()] ? @"heart_stroke" : %orig;
}

- (void)_t1_updateTitleLabel {
    %orig;
    if ([self.scribePage isEqualToString:BHTLikesPageID()]) {
        self.titleLabel.text = @"Likes";
    }
}

- (void)_t1_updateImageViewAnimated:(BOOL)animated {
    %orig;
    BHTApplyLikesHeartToTab(self);
}

- (void)setSelected:(BOOL)selected {
    BOOL wasSelected = self.selected;
    %orig;
    BHTApplyLikesHeartToTab(self);
    if (selected && !wasSelected &&
        [self.scribePage isEqualToString:BHTLikesPageID()]) {
        BHTActivateLikesTabView(self);
    }
}

- (void)layoutSubviews {
    %orig;
    BHTApplyLikesHeartToTab(self);
}

%end

%hook T1TabBarViewController

- (void)viewDidLayoutSubviews {
    %orig;
    BHTApplyLikesHeartToNativeBar(self);
}

%end
