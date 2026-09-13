//  CustomTabBarViewController.m
//  NeoFreeBird
//
//  Created by Bandar Alruwaili on 11/12/2023.
//  Modified by actuallyaridan on 31/05/2025.
//
//  Clones the app's native tab-customization screen: a grid of every available
//  tab (tap to add/remove) above a tab-bar preview row. Both the selected
//  tiles and the preview row can be dragged to reorder the final tab bar.
//

#import "CustomTabBarViewController.h"
#import <objc/runtime.h>
#import "Core/BHTBundle.h"
#import "Core/BHTSettings.h"
#import "Sidebar/BHTSidebarNavigationUtility.h"
#import "Core/TwitterChirpFont.h"
#import "CustomTabBarCell.h"
#import "CustomTabBarNativeColors.h"
#import "CustomTabBarPreviewCell.h"
#import "CustomTabBarUtility.h"
#import "Likes/BHTLikesTab.h"

extern UIColor* CurrentAccentColor(void);

// Whether the account genuinely has a panel's tab, ignoring the forced tab
// gates
extern BOOL panelIsGenuinelyAvailable(long long panelID);

// The floating compose button, hidden while the editor is on screen.
@interface TFNFloatingActionButton : UIView
- (void)hideAnimated:(_Bool)animated completion:(id)completion;
@end

// The app's standard button, used for the restore control.
@interface TFNButton : UIButton
+ (id)buttonWithTitle:(id)arg1
           imageNamed:(id)arg2
                style:(long long)arg3
            sizeClass:(long long)arg4;
@end

// The app's tab navigation, asked to recompute its tabs so changes apply live.
@interface T1TabbedAppNavigationViewController : UIViewController
- (void)recalculateVisiblePanels;
@end

static NSString* const kGridHeaderID = @"gridHeader";
static NSString* const kGridFooterID = @"gridFooter";

static void BHTPulseCustomTabBarSearchTarget(UIView* target) {
    if (!target.window) return;
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,
                                    target);
    CGAffineTransform original = target.transform;
    [UIView animateWithDuration:0.18
                          delay:0
                        options:UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                         target.transform =
                             CGAffineTransformScale(original, 1.06, 1.06);
                     }
                     completion:^(__unused BOOL finished) {
                         [UIView animateWithDuration:0.18
                                               delay:0
                                             options:
                                                 UIViewAnimationOptionAllowUserInteraction |
                                                 UIViewAnimationOptionCurveEaseInOut
                                          animations:^{
                                              target.transform = original;
                                          }
                                          completion:nil];
                     }];
}

@interface CustomTabBarViewController () <UICollectionViewDataSource,
                                          UICollectionViewDelegateFlowLayout>
@property (nonatomic, strong) UICollectionView* gridView;
@property (nonatomic, strong) UICollectionView* previewView;
@property (nonatomic, strong) UIView* separator;
@property (nonatomic, weak) UISwitch* grokSidebarSwitch;

// All available tab pageIDs; and the selected ones in tab-bar order (Home
// first).
@property (nonatomic, strong) NSMutableArray<NSString*>* allPages;
@property (nonatomic, strong) NSMutableArray<NSString*>* selectedPages;
@property (nonatomic, strong) NSArray<NSString*>* originalSelection;
@property (nonatomic, assign) BOOL hasChanges;
@end

@implementation CustomTabBarViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = CustomTabBarScreenBackgroundColor();
    self.hasChanges = NO;

    [self setupGridView];
    [self setupPreviewRow];
    [self setupSaveButton];
    [self loadData];
    [self updateSaveButtonState];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Hide the floating compose button so it doesn't overlap the editor.
    for (UIWindow* window in [UIApplication sharedApplication].windows) {
        [self findAndHideFloatingActionButtonInView:window];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self revealSettingsSearchTargetIfNeeded];
}

- (void)revealSettingsSearchTargetIfNeeded {
    NSString* target = self.settingsSearchTargetIdentifier;
    if (target.length == 0 || !self.gridView.window) return;

    if ([target isEqualToString:@"hide_grok_sidebar"]) {
        self.settingsSearchTargetIdentifier = nil;
        [self.gridView setContentOffset:CGPointMake(0, MAX(
            -self.gridView.adjustedContentInset.top,
            self.gridView.contentSize.height - self.gridView.bounds.size.height +
                self.gridView.adjustedContentInset.bottom)) animated:NO];
        [self.gridView layoutIfNeeded];
        BHTPulseCustomTabBarSearchTarget(self.grokSidebarSwitch);
        return;
    }

    NSUInteger index = [self.allPages indexOfObject:target];
    self.settingsSearchTargetIdentifier = nil;
    if (index == NSNotFound) return;

    NSIndexPath* indexPath =
        [NSIndexPath indexPathForItem:index inSection:0];
    [self.gridView scrollToItemAtIndexPath:indexPath
                          atScrollPosition:
                              UICollectionViewScrollPositionCenteredVertically
                                  animated:NO];
    [self.gridView layoutIfNeeded];
    UICollectionViewCell* cell =
        [self.gridView cellForItemAtIndexPath:indexPath];
    if (cell) {
        BHTPulseCustomTabBarSearchTarget(cell);
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UICollectionViewCell* deferredCell =
            [weakSelf.gridView cellForItemAtIndexPath:indexPath];
        BHTPulseCustomTabBarSearchTarget(deferredCell);
    });
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self.gridView.collectionViewLayout invalidateLayout];
    [self.previewView.collectionViewLayout invalidateLayout];
}

- (void)findAndHideFloatingActionButtonInView:(UIView*)view {
    if ([view isKindOfClass:NSClassFromString(@"TFNFloatingActionButton")]) {
        [(TFNFloatingActionButton*)view hideAnimated:YES completion:nil];
        return;
    }
    for (UIView* subview in view.subviews) {
        [self findAndHideFloatingActionButtonInView:subview];
    }
}

#pragma mark - UI Setup

- (void)setupSaveButton {
    UIBarButtonItem* saveButton = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                             target:self
                             action:@selector(saveButtonTapped)];
    self.navigationItem.rightBarButtonItem = saveButton;
    saveButton.enabled = NO;
}

- (void)setupGridView {
    // Grid metrics mirror the native TabCustomizationGridViewController.
    UICollectionViewFlowLayout* layout =
        [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 20;
    layout.minimumLineSpacing = 24;
    layout.sectionInset = UIEdgeInsetsMake(8, 20, 24, 20);

    self.gridView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                       collectionViewLayout:layout];
    self.gridView.translatesAutoresizingMaskIntoConstraints = NO;
    self.gridView.backgroundColor = [UIColor clearColor];
    self.gridView.alwaysBounceVertical = YES;
    self.gridView.delegate = self;
    self.gridView.dataSource = self;
    [self.gridView registerClass:[CustomTabBarCell class]
        forCellWithReuseIdentifier:[CustomTabBarCell reuseIdentifier]];
    [self.gridView registerClass:[UICollectionReusableView class]
        forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
               withReuseIdentifier:kGridHeaderID];
    [self.gridView registerClass:[UICollectionReusableView class]
        forSupplementaryViewOfKind:UICollectionElementKindSectionFooter
               withReuseIdentifier:kGridFooterID];
    [self.view addSubview:self.gridView];

    UILongPressGestureRecognizer* longPress =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(handleGridReorderGesture:)];
    [self.gridView addGestureRecognizer:longPress];
}

- (void)setupPreviewRow {
    UICollectionViewFlowLayout* layout =
        [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.minimumLineSpacing = 0;
    layout.minimumInteritemSpacing = 0;

    self.previewView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                          collectionViewLayout:layout];
    self.previewView.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewView.backgroundColor = [UIColor clearColor];
    self.previewView.showsHorizontalScrollIndicator = NO;
    self.previewView.delegate = self;
    self.previewView.dataSource = self;
    [self.previewView registerClass:[CustomTabBarPreviewCell class]
         forCellWithReuseIdentifier:[CustomTabBarPreviewCell reuseIdentifier]];
    [self.view addSubview:self.previewView];

    UILongPressGestureRecognizer* longPress =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(handleReorderGesture:)];
    [self.previewView addGestureRecognizer:longPress];

    // Hairline separator above the preview row.
    self.separator = [UIView new];
    self.separator.translatesAutoresizingMaskIntoConstraints = NO;
    self.separator.backgroundColor = CustomTabBarSeparatorColor();
    [self.view addSubview:self.separator];

    CGFloat hairline = 1.0 / UIScreen.mainScreen.scale;
    [NSLayoutConstraint activateConstraints:@[
        [self.previewView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.previewView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.previewView.bottomAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [self.previewView.heightAnchor constraintEqualToConstant:49],

        [self.separator.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.separator.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.separator.bottomAnchor
            constraintEqualToAnchor:self.previewView.topAnchor],
        [self.separator.heightAnchor constraintEqualToConstant:hairline],

        [self.gridView.topAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.gridView.leadingAnchor
            constraintEqualToAnchor:self.view.leadingAnchor],
        [self.gridView.trailingAnchor
            constraintEqualToAnchor:self.view.trailingAnchor],
        [self.gridView.bottomAnchor
            constraintEqualToAnchor:self.separator.topAnchor]
    ]];
}

#pragma mark - Data

- (void)loadData {
    // Offer the captured tabs the account genuinely has; panels that only exist
    // because of the tweak's forced gates stay out of the grid.
    self.allPages = [NSMutableArray array];
    for (NSDictionary* entry in [CustomTabBarUtility availableTabs]) {
        NSNumber* panelID = entry[TabPanelIDKey];
        NSString* pageID = entry[TabPageKey];
        BOOL isLikes = [pageID isEqualToString:BHTLikesPageID()];
        if (!isLikes && panelID &&
            !panelIsGenuinelyAvailable(panelID.longLongValue)) {
            continue;
        }
        [self.allPages addObject:pageID];
    }

    NSArray<NSString*>* saved = [CustomTabBarUtility visiblePageIDsInOrder];
    NSMutableArray<NSString*>* source =
        [saved ?: [CustomTabBarUtility defaultVisiblePageIDs] mutableCopy];
    if (!saved && [CustomTabBarUtility likesTabEnabled] &&
        ![source containsObject:BHTLikesPageID()]) {
        [source addObject:BHTLikesPageID()];
    }

    self.selectedPages = [NSMutableArray array];
    for (NSString* page in source) {
        if ([self.allPages containsObject:page] &&
            ![self.selectedPages containsObject:page]) {
            [self.selectedPages addObject:page];
        }
    }
    [self pinHomeFirst];
    [self syncGridOrderToSelectedPages];

    self.originalSelection = [self.selectedPages copy];
    self.hasChanges = NO;

    [self.gridView reloadData];
    [self.previewView reloadData];
}

- (void)pinHomeFirst {
    [self.selectedPages removeObject:CustomTabBarHomePageID];
    if ([CustomTabBarUtility metadataForPage:CustomTabBarHomePageID]) {
        [self.selectedPages insertObject:CustomTabBarHomePageID atIndex:0];
    }
}

- (void)syncGridOrderToSelectedPages {
    NSMutableArray<NSString*>* ordered = [self.selectedPages mutableCopy];
    for (NSString* page in self.allPages) {
        if (![ordered containsObject:page]) [ordered addObject:page];
    }
    self.allPages = ordered;
}

- (void)syncSelectedPagesToGridOrder {
    NSSet<NSString*>* selected = [NSSet setWithArray:self.selectedPages];
    NSMutableArray<NSString*>* ordered = [NSMutableArray array];
    for (NSString* page in self.allPages) {
        if ([selected containsObject:page]) [ordered addObject:page];
    }
    self.selectedPages = ordered;
    [self pinHomeFirst];
}

- (void)recomputeChanges {
    self.hasChanges = ![self.selectedPages isEqualToArray:self.originalSelection];
    [self updateSaveButtonState];
}

- (void)updateSaveButtonState {
    self.navigationItem.rightBarButtonItem.enabled = self.hasChanges;
}

#pragma mark - Save / Reset

- (void)grokSidebarChanged:(UISwitch*)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on
                                           forKey:@"hide_grok_sidebar"];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BHTSidebarNavigationSettingsDidChangeNotification
                      object:nil];
    [BHTSidebarNavigationUtility refreshRegisteredDashContentControllers];
}

- (void)saveButtonTapped {
    [self persistChanges];

    // Apply the new layout live by asking the app to recompute its visible tabs;
    // this re-runs the tab-entry hook with the freshly saved order.
    [self applyLiveLayout];
    [self.navigationController popViewControllerAnimated:YES];
}

static UIViewController* findViewControllerOfClass(UIViewController* vc,
                                                   Class cls) {
    if (!vc) {
        return nil;
    }
    if ([vc isKindOfClass:cls]) {
        return vc;
    }
    for (UIViewController* child in vc.childViewControllers) {
        UIViewController* found = findViewControllerOfClass(child, cls);
        if (found) {
            return found;
        }
    }
    return findViewControllerOfClass(vc.presentedViewController, cls);
}

- (BOOL)applyLiveLayout {
    Class navClass = objc_getClass("T1TabbedAppNavigationViewController");
    if (!navClass) {
        return NO;
    }

    UIViewController* tabNav = nil;
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
        tabNav = findViewControllerOfClass(window.rootViewController, navClass);
        if (tabNav) {
            break;
        }
    }

    if (![tabNav respondsToSelector:@selector(recalculateVisiblePanels)]) {
        return NO;
    }

    [(T1TabbedAppNavigationViewController*)tabNav recalculateVisiblePanels];
    return YES;
}

- (void)persistChanges {
    [self pinHomeFirst];

    [CustomTabBarUtility setVisiblePageIDs:self.selectedPages];

    self.originalSelection = [self.selectedPages copy];
    self.hasChanges = NO;
    [self updateSaveButtonState];
}

- (void)restoreTapped {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:
            [[BHTBundle sharedBundle]
                localizedStringForKey:
                    @"BHT_RESTORE_DEFAULTS"]
                         message:[[BHTBundle sharedBundle]
                                     localizedStringForKey:
                                         @"CUSTOM_TAB_BAR_RESET_MESSAGE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction
                         actionWithTitle:[[BHTBundle sharedBundle]
                                             localizedStringForKey:
                                                 @"BHT_RESTORE_DEFAULTS"]
                                   style:UIAlertActionStyleDestructive
                                 handler:^(UIAlertAction* _Nonnull action) {
                                     [CustomTabBarUtility resetSelection];
                                     [[NSUserDefaults standardUserDefaults]
                                         removeObjectForKey:@"hide_grok_sidebar"];
                                     [self loadData];
                                     [self recomputeChanges];
                                 }]];
    [alert
        addAction:[UIAlertAction actionWithTitle:[[BHTBundle sharedBundle]
                                                     localizedTwitterStringForKey:
                                                         @"CANCEL_ACTION_LABEL"]
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Reordering

- (void)handleGridReorderGesture:(UILongPressGestureRecognizer*)gesture {
    CGPoint location = [gesture locationInView:self.gridView];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath* indexPath =
                [self.gridView indexPathForItemAtPoint:location];
            if (!indexPath ||
                [self.allPages[indexPath.item]
                    isEqualToString:CustomTabBarHomePageID]) {
                return;
            }
            [self.gridView
                beginInteractiveMovementForItemAtIndexPath:indexPath];
            break;
        }
        case UIGestureRecognizerStateChanged:
            [self.gridView
                updateInteractiveMovementTargetPosition:location];
            break;
        case UIGestureRecognizerStateEnded:
            [self.gridView endInteractiveMovement];
            break;
        default:
            [self.gridView cancelInteractiveMovement];
            break;
    }
}

- (void)handleReorderGesture:(UILongPressGestureRecognizer*)gesture {
    CGPoint location = [gesture locationInView:self.previewView];

    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath* indexPath =
                [self.previewView indexPathForItemAtPoint:location];
            // Home stays pinned first and can't be dragged.
            if (!indexPath || indexPath.item == 0) {
                return;
            }
            [self.previewView beginInteractiveMovementForItemAtIndexPath:indexPath];
            break;
        }
        case UIGestureRecognizerStateChanged:
            [self.previewView updateInteractiveMovementTargetPosition:location];
            break;
        case UIGestureRecognizerStateEnded:
            [self.previewView endInteractiveMovement];
            break;
        default:
            [self.previewView cancelInteractiveMovement];
            break;
    }
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView*)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return collectionView == self.gridView ? self.allPages.count
                                           : self.selectedPages.count;
}

- (__kindof UICollectionViewCell*)collectionView:
                                      (UICollectionView*)collectionView
                          cellForItemAtIndexPath:(NSIndexPath*)indexPath {
    if (collectionView == self.previewView) {
        CustomTabBarPreviewCell* cell = [collectionView
            dequeueReusableCellWithReuseIdentifier:[CustomTabBarPreviewCell
                                                       reuseIdentifier]
                                      forIndexPath:indexPath];
        NSDictionary* meta = [CustomTabBarUtility
            metadataForPage:self.selectedPages[indexPath.item]];
        [cell configureWithImageName:meta[TabImageKey]];
        return cell;
    }

    CustomTabBarCell* cell = [collectionView
        dequeueReusableCellWithReuseIdentifier:[CustomTabBarCell reuseIdentifier]
                                  forIndexPath:indexPath];
    NSString* page = self.allPages[indexPath.item];
    NSDictionary* meta = [CustomTabBarUtility metadataForPage:page];
    [cell configureWithTitle:(meta[TabTitleKey] ?: page)
                   imageName:meta[TabImageKey]
                    selected:[self.selectedPages containsObject:page]
                       fixed:[page isEqualToString:CustomTabBarHomePageID]
                 accentColor:CurrentAccentColor()];
    return cell;
}

- (UICollectionReusableView*)collectionView:(UICollectionView*)collectionView
          viewForSupplementaryElementOfKind:(NSString*)kind
                                atIndexPath:(NSIndexPath*)indexPath {
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        UICollectionReusableView* header =
            [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                               withReuseIdentifier:kGridHeaderID
                                                      forIndexPath:indexPath];
        [header.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

        UILabel* label =
            [[UILabel alloc] initWithFrame:CGRectInset(header.bounds, 4, 0)];
        label.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.numberOfLines = 0;
        label.font = [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
        label.textColor = [UIColor secondaryLabelColor];
        label.text = [[BHTBundle sharedBundle]
            localizedStringForKey:@"CUSTOM_TAB_BAR_GRID_DETAIL"];
        [header addSubview:label];
        return header;
    }

    UICollectionReusableView* footer =
        [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                           withReuseIdentifier:kGridFooterID
                                                  forIndexPath:indexPath];
    [footer.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    NSString* title = [[BHTBundle sharedBundle]
        localizedStringForKey:
            @"BHT_RESTORE_DEFAULTS"];
    UIButton* restore = [objc_getClass("TFNButton") buttonWithTitle:title
                                                         imageNamed:nil
                                                              style:2
                                                          sizeClass:2];
    restore.translatesAutoresizingMaskIntoConstraints = NO;
    [restore addTarget:self
                  action:@selector(restoreTapped)
        forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:restore];
    BHTBundle* bundle = [BHTBundle sharedBundle];
    UILabel* grokTitle = [UILabel new];
    grokTitle.text = [bundle localizedStringForKey:@"NAV_HIDE_GROK_BOT_TITLE"];
    grokTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    grokTitle.textColor = UIColor.labelColor;
    grokTitle.numberOfLines = 0;
    UISwitch* grokSwitch = [UISwitch new];
    grokSwitch.on = [BHTSettings boolForKey:@"hide_grok_sidebar"];
    grokSwitch.accessibilityLabel = grokTitle.text;
    grokSwitch.onTintColor = CurrentAccentColor();
    [grokSwitch addTarget:self action:@selector(grokSidebarChanged:)
        forControlEvents:UIControlEventValueChanged];
    self.grokSidebarSwitch = grokSwitch;
    UIStackView* row = [[UIStackView alloc] initWithArrangedSubviews:@[grokTitle, grokSwitch]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    UILabel* detail = [UILabel new];
    detail.text = [bundle localizedStringForKey:@"NAV_HIDE_GROK_BOT_DETAIL"];
    detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    detail.textColor = UIColor.secondaryLabelColor;
    detail.numberOfLines = 0;
    UIStackView* controls = [[UIStackView alloc] initWithArrangedSubviews:@[row, detail]];
    controls.axis = UILayoutConstraintAxisVertical;
    controls.spacing = 6;
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:controls];
    [NSLayoutConstraint activateConstraints:@[
        [controls.topAnchor constraintEqualToAnchor:footer.topAnchor constant:8],
        [controls.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:20],
        [controls.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-20],
        [restore.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [restore.topAnchor constraintEqualToAnchor:controls.bottomAnchor constant:24]
    ]];
    return footer;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView*)collectionView
    didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
    // Only the grid toggles selection; the preview row is reorder-only.
    if (collectionView != self.gridView) {
        return;
    }

    NSString* page = self.allPages[indexPath.item];
    if ([page isEqualToString:CustomTabBarHomePageID]) {
        return;
    }

    if ([self.selectedPages containsObject:page]) {
        [self.selectedPages removeObject:page];
    } else {
        [self.selectedPages addObject:page];
        [self syncSelectedPagesToGridOrder];
    }

    [self recomputeChanges];
    [self.gridView reloadItemsAtIndexPaths:@[indexPath]];
    [self.previewView reloadData];
}

- (BOOL)collectionView:(UICollectionView*)collectionView
    canMoveItemAtIndexPath:(NSIndexPath*)indexPath {
    if (collectionView == self.previewView) {
        return indexPath.item != 0;
    }
    if (collectionView == self.gridView) {
        return ![self.allPages[indexPath.item]
            isEqualToString:CustomTabBarHomePageID];
    }
    return NO;
}

- (NSIndexPath*)collectionView:(UICollectionView*)collectionView
    targetIndexPathForMoveFromItemAtIndexPath:(NSIndexPath*)originalIndexPath
                          toProposedIndexPath:(NSIndexPath*)proposedIndexPath {
    // Keep Home pinned first in either draggable surface.
    if (proposedIndexPath.item == 0) {
        return [NSIndexPath indexPathForItem:1 inSection:0];
    }
    return proposedIndexPath;
}

- (void)collectionView:(UICollectionView*)collectionView
    moveItemAtIndexPath:(NSIndexPath*)sourceIndexPath
            toIndexPath:(NSIndexPath*)destinationIndexPath {
    if (collectionView == self.gridView) {
        NSString* page = self.allPages[sourceIndexPath.item];
        [self.allPages removeObjectAtIndex:sourceIndexPath.item];
        [self.allPages insertObject:page atIndex:destinationIndexPath.item];
        [self syncSelectedPagesToGridOrder];
        [self.previewView reloadData];
    } else {
        NSString* page = self.selectedPages[sourceIndexPath.item];
        [self.selectedPages removeObjectAtIndex:sourceIndexPath.item];
        [self.selectedPages insertObject:page
                                 atIndex:destinationIndexPath.item];
        [self syncGridOrderToSelectedPages];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.gridView reloadData];
        });
    }
    [self recomputeChanges];
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView*)collectionView
                    layout:(UICollectionViewLayout*)collectionViewLayout
    sizeForItemAtIndexPath:(NSIndexPath*)indexPath {
    if (collectionView == self.previewView) {
        // Native sizes each preview item to 1/6 of the width; full row height.
        CGFloat width = floor(CGRectGetWidth(collectionView.bounds) / 6.0);
        return CGSizeMake(width, CGRectGetHeight(collectionView.bounds));
    }

    UICollectionViewFlowLayout* flow =
        (UICollectionViewFlowLayout*)collectionViewLayout;
    UIEdgeInsets insets = flow.sectionInset;
    CGFloat spacing = flow.minimumInteritemSpacing;

    // Native grid: 3 columns, tile width capped at 98pt, height = width + 27.
    CGFloat available =
        CGRectGetWidth(collectionView.bounds) - insets.left - insets.right;
    CGFloat itemWidth = floor((available - spacing * 2) / 3.0);
    itemWidth = MIN(itemWidth, 98.0);
    return CGSizeMake(itemWidth, itemWidth + 27.0);
}

- (CGSize)collectionView:(UICollectionView*)collectionView
                             layout:
                                 (UICollectionViewLayout*)collectionViewLayout
    referenceSizeForHeaderInSection:(NSInteger)section {
    if (collectionView != self.gridView) {
        return CGSizeZero;
    }
    return CGSizeMake(CGRectGetWidth(collectionView.bounds), 60);
}

- (CGSize)collectionView:(UICollectionView*)collectionView
                             layout:
                                 (UICollectionViewLayout*)collectionViewLayout
    referenceSizeForFooterInSection:(NSInteger)section {
    if (collectionView != self.gridView) {
        return CGSizeZero;
    }
    CGFloat width = CGRectGetWidth(collectionView.bounds);
    BHTBundle* bundle = [BHTBundle sharedBundle];
    CGFloat titleHeight = [[bundle localizedStringForKey:@"NAV_HIDE_GROK_BOT_TITLE"]
        boundingRectWithSize:CGSizeMake(MAX(80, width - 105), CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin
        attributes:@{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody]}
        context:nil].size.height;
    CGFloat detailHeight = [[bundle localizedStringForKey:@"NAV_HIDE_GROK_BOT_DETAIL"]
        boundingRectWithSize:CGSizeMake(MAX(100, width - 40), CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin
        attributes:@{NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]}
        context:nil].size.height;
    return CGSizeMake(width, ceil(MAX(31, titleHeight) + detailHeight + 100));
}

@end
