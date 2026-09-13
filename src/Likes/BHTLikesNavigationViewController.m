#import "Likes/BHTLikesNavigationViewController.h"
#import "Core/BHTBundle.h"
#import "Core/TwitterChirpFont.h"
#import "CustomTabBar/CustomTabBarCell.h"
#import "CustomTabBar/CustomTabBarNativeColors.h"
#import "CustomTabBar/CustomTabBarPreviewCell.h"
#import "CustomTabBar/CustomTabBarUtility.h"
#import "Likes/BHTLikesNavigationUtility.h"

extern UIColor* CurrentAccentColor(void);

@interface TFNFloatingActionButton : UIView
- (void)hideAnimated:(_Bool)animated completion:(id)completion;
@end

@interface TFNButton : UIButton
+ (id)buttonWithTitle:(id)title
           imageNamed:(id)imageName
                style:(long long)style
            sizeClass:(long long)sizeClass;
@end

static NSString* const kBHTLikesGridHeaderID = @"likesGridHeader";
static NSString* const kBHTLikesGridFooterID = @"likesGridFooter";

static void BHTPulseLikesSearchTarget(UIView* target) {
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

@interface BHTLikesNavigationViewController ()
    <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property(nonatomic, strong) UICollectionView* gridView;
@property(nonatomic, strong) UICollectionView* previewView;
@property(nonatomic, strong) UIView* separator;
@property(nonatomic, strong) NSMutableArray<NSString*>* allPages;
@property(nonatomic, strong) NSMutableArray<NSString*>* selectedPages;
@property(nonatomic, strong) NSArray<NSString*>* originalSelection;
@property(nonatomic) BOOL waterfallEnabled;
@property(nonatomic) BOOL originalWaterfallEnabled;
@property(nonatomic) BOOL hasChanges;
@property(nonatomic, weak) UISwitch* waterfallSearchTargetView;
@end

@implementation BHTLikesNavigationViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = CustomTabBarScreenBackgroundColor();
    [self setupGridView];
    [self setupPreviewRow];
    [self setupSaveButton];
    [self loadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    for (UIWindow* window in UIApplication.sharedApplication.windows) {
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
    self.settingsSearchTargetIdentifier = nil;

    if ([target isEqualToString:@"waterfall"]) {
        CGPoint top =
            CGPointMake(self.gridView.contentOffset.x,
                        -self.gridView.adjustedContentInset.top);
        [self.gridView setContentOffset:top animated:NO];
        [self.gridView layoutIfNeeded];
        UISwitch* waterfallTarget = self.waterfallSearchTargetView;
        if (waterfallTarget) {
            BHTPulseLikesSearchTarget(waterfallTarget);
            return;
        }
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            BHTPulseLikesSearchTarget(
                weakSelf.waterfallSearchTargetView);
        });
        return;
    }

    NSUInteger index = [self.allPages indexOfObject:target];
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
        BHTPulseLikesSearchTarget(cell);
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UICollectionViewCell* deferredCell =
            [weakSelf.gridView cellForItemAtIndexPath:indexPath];
        BHTPulseLikesSearchTarget(deferredCell);
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

#pragma mark - Setup

- (void)setupSaveButton {
    UIBarButtonItem* save = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                             target:self
                             action:@selector(saveTapped)];
    save.enabled = NO;
    self.navigationItem.rightBarButtonItem = save;
}

- (void)setupGridView {
    UICollectionViewFlowLayout* layout =
        [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 20;
    layout.minimumLineSpacing = 24;
    layout.sectionInset = UIEdgeInsetsMake(8, 20, 24, 20);

    self.gridView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                       collectionViewLayout:layout];
    self.gridView.translatesAutoresizingMaskIntoConstraints = NO;
    self.gridView.backgroundColor = UIColor.clearColor;
    self.gridView.alwaysBounceVertical = YES;
    self.gridView.delegate = self;
    self.gridView.dataSource = self;
    [self.gridView registerClass:CustomTabBarCell.class
        forCellWithReuseIdentifier:[CustomTabBarCell reuseIdentifier]];
    [self.gridView registerClass:UICollectionReusableView.class
        forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
               withReuseIdentifier:kBHTLikesGridHeaderID];
    [self.gridView registerClass:UICollectionReusableView.class
        forSupplementaryViewOfKind:UICollectionElementKindSectionFooter
               withReuseIdentifier:kBHTLikesGridFooterID];
    [self.view addSubview:self.gridView];

    UILongPressGestureRecognizer* longPress =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(handleGridReorder:)];
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
    self.previewView.backgroundColor = UIColor.clearColor;
    self.previewView.showsHorizontalScrollIndicator = NO;
    self.previewView.delegate = self;
    self.previewView.dataSource = self;
    [self.previewView registerClass:CustomTabBarPreviewCell.class
         forCellWithReuseIdentifier:
             [CustomTabBarPreviewCell reuseIdentifier]];
    [self.view addSubview:self.previewView];

    UILongPressGestureRecognizer* longPress =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(handlePreviewReorder:)];
    [self.previewView addGestureRecognizer:longPress];

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
    self.allPages = [NSMutableArray array];
    for (NSDictionary* entry in
         [BHTLikesNavigationUtility availableTabs]) {
        [self.allPages addObject:entry[TabPageKey]];
    }
    self.selectedPages =
        [[BHTLikesNavigationUtility visiblePageIDsInOrder] mutableCopy];
    [self syncGridOrderToSelection];
    self.waterfallEnabled =
        [BHTLikesNavigationUtility waterfallEnabled];
    self.originalSelection = [self.selectedPages copy];
    self.originalWaterfallEnabled = self.waterfallEnabled;
    [self recomputeChanges];
    [self.gridView reloadData];
    [self.previewView reloadData];
}

- (void)syncGridOrderToSelection {
    NSMutableArray<NSString*>* ordered = [self.selectedPages mutableCopy];
    for (NSString* pageID in self.allPages) {
        if (![ordered containsObject:pageID]) [ordered addObject:pageID];
    }
    self.allPages = ordered;
}

- (void)syncSelectionToGridOrder {
    NSSet<NSString*>* selected =
        [NSSet setWithArray:self.selectedPages];
    NSMutableArray<NSString*>* ordered = [NSMutableArray array];
    for (NSString* pageID in self.allPages) {
        if ([selected containsObject:pageID]) [ordered addObject:pageID];
    }
    self.selectedPages = ordered;
}

- (void)recomputeChanges {
    self.hasChanges =
        ![self.selectedPages isEqualToArray:self.originalSelection] ||
        self.waterfallEnabled != self.originalWaterfallEnabled;
    self.navigationItem.rightBarButtonItem.enabled = YES;
    if (self.hasChanges) {
        [BHTLikesNavigationUtility setVisiblePageIDs:self.selectedPages];
        [BHTLikesNavigationUtility setWaterfallEnabled:self.waterfallEnabled];
        self.originalSelection = [self.selectedPages copy];
        self.originalWaterfallEnabled = self.waterfallEnabled;
        self.hasChanges = NO;
    }
}

#pragma mark - Save and restore

- (void)saveTapped {
    [BHTLikesNavigationUtility setVisiblePageIDs:self.selectedPages];
    [BHTLikesNavigationUtility
        setWaterfallEnabled:self.waterfallEnabled];
    self.originalSelection = [self.selectedPages copy];
    self.originalWaterfallEnabled = self.waterfallEnabled;
    [self recomputeChanges];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)restoreTapped {
    UIAlertController* alert = [UIAlertController
        alertControllerWithTitle:
            [[BHTBundle sharedBundle]
                localizedStringForKey:
                    @"BHT_RESTORE_DEFAULTS"]
                         message:[[BHTBundle sharedBundle]
                                     localizedStringForKey:
                                         @"LIKES_NAVIGATION_RESET_MESSAGE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction
                         actionWithTitle:[[BHTBundle sharedBundle]
                                             localizedStringForKey:
                                                 @"BHT_RESTORE_DEFAULTS"]
                                   style:UIAlertActionStyleDestructive
                                 handler:^(__unused UIAlertAction* action) {
                                     typeof(self) strongSelf = weakSelf;
                                     if (!strongSelf) return;
                                     strongSelf.selectedPages =
                                         [NSMutableArray arrayWithArray:@[
                                             BHTLikesBookmarksPageID,
                                             BHTLikesVideosPageID,
                                             BHTLikesArticlesPageID,
                                             BHTLikesPostsPageID
                                         ]];
                                     strongSelf.waterfallEnabled = YES;
                                     [strongSelf syncGridOrderToSelection];
                                     [strongSelf recomputeChanges];
                                     [strongSelf.gridView reloadData];
                                     [strongSelf.previewView reloadData];
                                 }]];
    [alert addAction:[UIAlertAction
                         actionWithTitle:[[BHTBundle sharedBundle]
                                             localizedTwitterStringForKey:
                                                 @"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)waterfallChanged:(UISwitch*)sender {
    self.waterfallEnabled = sender.isOn;
    [self recomputeChanges];
}

#pragma mark - Reordering

- (void)handleGridReorder:(UILongPressGestureRecognizer*)gesture {
    CGPoint point = [gesture locationInView:self.gridView];
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath* path =
                [self.gridView indexPathForItemAtPoint:point];
            if (path) {
                [self.gridView
                    beginInteractiveMovementForItemAtIndexPath:path];
            }
            break;
        }
        case UIGestureRecognizerStateChanged:
            [self.gridView updateInteractiveMovementTargetPosition:point];
            break;
        case UIGestureRecognizerStateEnded:
            [self.gridView endInteractiveMovement];
            break;
        default:
            [self.gridView cancelInteractiveMovement];
            break;
    }
}

- (void)handlePreviewReorder:(UILongPressGestureRecognizer*)gesture {
    CGPoint point = [gesture locationInView:self.previewView];
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            NSIndexPath* path =
                [self.previewView indexPathForItemAtPoint:point];
            if (path) {
                [self.previewView
                    beginInteractiveMovementForItemAtIndexPath:path];
            }
            break;
        }
        case UIGestureRecognizerStateChanged:
            [self.previewView updateInteractiveMovementTargetPosition:point];
            break;
        case UIGestureRecognizerStateEnded:
            [self.previewView endInteractiveMovement];
            break;
        default:
            [self.previewView cancelInteractiveMovement];
            break;
    }
}

#pragma mark - Collection data source

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
            dequeueReusableCellWithReuseIdentifier:
                [CustomTabBarPreviewCell reuseIdentifier]
                                      forIndexPath:indexPath];
        NSDictionary* metadata = [BHTLikesNavigationUtility
            metadataForPage:self.selectedPages[indexPath.item]];
        [cell configureWithImageName:metadata[TabImageKey]];
        return cell;
    }

    CustomTabBarCell* cell = [collectionView
        dequeueReusableCellWithReuseIdentifier:
            [CustomTabBarCell reuseIdentifier]
                                  forIndexPath:indexPath];
    NSString* pageID = self.allPages[indexPath.item];
    NSDictionary* metadata =
        [BHTLikesNavigationUtility metadataForPage:pageID];
    [cell configureWithTitle:metadata[TabTitleKey]
                   imageName:metadata[TabImageKey]
                    selected:[self.selectedPages containsObject:pageID]
                       fixed:NO
                 accentColor:CurrentAccentColor()];
    return cell;
}

- (UICollectionReusableView*)collectionView:(UICollectionView*)collectionView
          viewForSupplementaryElementOfKind:(NSString*)kind
                                atIndexPath:(NSIndexPath*)indexPath {
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        UICollectionReusableView* header =
            [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                               withReuseIdentifier:
                                                   kBHTLikesGridHeaderID
                                                      forIndexPath:indexPath];
        [header.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

        UILabel* detail = [UILabel new];
        detail.translatesAutoresizingMaskIntoConstraints = NO;
        detail.numberOfLines = 0;
        detail.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
        detail.textColor = UIColor.secondaryLabelColor;
        detail.text = [[BHTBundle sharedBundle]
            localizedStringForKey:@"LIKES_NAVIGATION_GRID_DETAIL"];
        [header addSubview:detail];

        UILabel* waterfall = [UILabel new];
        waterfall.translatesAutoresizingMaskIntoConstraints = NO;
        waterfall.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:15];
        waterfall.textColor = CustomTabBarTitleColor();
        waterfall.text = [[BHTBundle sharedBundle]
            localizedStringForKey:@"LIKES_MEDIA_WATERFALL_TITLE"];
        [header addSubview:waterfall];

        UISwitch* toggle = [UISwitch new];
        toggle.translatesAutoresizingMaskIntoConstraints = NO;
        toggle.on = self.waterfallEnabled;
        toggle.onTintColor = CurrentAccentColor();
        toggle.accessibilityLabel = waterfall.text;
        [toggle addTarget:self
                   action:@selector(waterfallChanged:)
         forControlEvents:UIControlEventValueChanged];
        [header addSubview:toggle];
        self.waterfallSearchTargetView = toggle;

        [NSLayoutConstraint activateConstraints:@[
            [detail.topAnchor constraintEqualToAnchor:header.topAnchor
                                              constant:4],
            [detail.leadingAnchor constraintEqualToAnchor:header.leadingAnchor
                                                  constant:24],
            [detail.trailingAnchor
                constraintEqualToAnchor:header.trailingAnchor
                               constant:-24],
            [waterfall.leadingAnchor
                constraintEqualToAnchor:detail.leadingAnchor],
            [waterfall.bottomAnchor
                constraintEqualToAnchor:header.bottomAnchor
                               constant:-10],
            [toggle.trailingAnchor
                constraintEqualToAnchor:detail.trailingAnchor],
            [toggle.centerYAnchor
                constraintEqualToAnchor:waterfall.centerYAnchor]
        ]];
        return header;
    }

    UICollectionReusableView* footer =
        [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                           withReuseIdentifier:
                                               kBHTLikesGridFooterID
                                                  forIndexPath:indexPath];
    [footer.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    NSString* title = [[BHTBundle sharedBundle]
        localizedStringForKey:
            @"BHT_RESTORE_DEFAULTS"];
    UIButton* restore = [objc_getClass("TFNButton")
        buttonWithTitle:title
             imageNamed:nil
                  style:2
              sizeClass:2];
    restore.translatesAutoresizingMaskIntoConstraints = NO;
    [restore addTarget:self
                  action:@selector(restoreTapped)
        forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:restore];
    [NSLayoutConstraint activateConstraints:@[
        [restore.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [restore.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor]
    ]];
    return footer;
}

#pragma mark - Collection delegate

- (void)collectionView:(UICollectionView*)collectionView
    didSelectItemAtIndexPath:(NSIndexPath*)indexPath {
    if (collectionView != self.gridView) return;
    NSString* pageID = self.allPages[indexPath.item];
    if ([self.selectedPages containsObject:pageID]) {
        // Activity History cannot safely render with zero destinations.
        if (self.selectedPages.count == 1) return;
        [self.selectedPages removeObject:pageID];
    } else {
        [self.selectedPages addObject:pageID];
        [self syncSelectionToGridOrder];
    }
    [self recomputeChanges];
    [self.gridView reloadItemsAtIndexPaths:@[indexPath]];
    [self.previewView reloadData];
}

- (BOOL)collectionView:(UICollectionView*)collectionView
    canMoveItemAtIndexPath:(NSIndexPath*)indexPath {
    return YES;
}

- (void)collectionView:(UICollectionView*)collectionView
    moveItemAtIndexPath:(NSIndexPath*)source
            toIndexPath:(NSIndexPath*)destination {
    if (collectionView == self.gridView) {
        NSString* pageID = self.allPages[source.item];
        [self.allPages removeObjectAtIndex:source.item];
        [self.allPages insertObject:pageID atIndex:destination.item];
        [self syncSelectionToGridOrder];
        [self.previewView reloadData];
    } else {
        NSString* pageID = self.selectedPages[source.item];
        [self.selectedPages removeObjectAtIndex:source.item];
        [self.selectedPages insertObject:pageID atIndex:destination.item];
        [self syncGridOrderToSelection];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.gridView reloadData];
        });
    }
    [self recomputeChanges];
}

#pragma mark - Collection layout

- (CGSize)collectionView:(UICollectionView*)collectionView
                    layout:(UICollectionViewLayout*)layout
    sizeForItemAtIndexPath:(NSIndexPath*)indexPath {
    if (collectionView == self.previewView) {
        CGFloat width = floor(CGRectGetWidth(collectionView.bounds) / 6.0);
        return CGSizeMake(width, CGRectGetHeight(collectionView.bounds));
    }
    UICollectionViewFlowLayout* flow =
        (UICollectionViewFlowLayout*)layout;
    CGFloat available = CGRectGetWidth(collectionView.bounds) -
                        flow.sectionInset.left - flow.sectionInset.right;
    CGFloat width =
        floor((available - flow.minimumInteritemSpacing * 2) / 3.0);
    width = MIN(width, 98.0);
    return CGSizeMake(width, width + 27.0);
}

- (CGSize)collectionView:(UICollectionView*)collectionView
                             layout:(UICollectionViewLayout*)layout
    referenceSizeForHeaderInSection:(NSInteger)section {
    return collectionView == self.gridView
               ? CGSizeMake(CGRectGetWidth(collectionView.bounds), 118)
               : CGSizeZero;
}

- (CGSize)collectionView:(UICollectionView*)collectionView
                             layout:(UICollectionViewLayout*)layout
    referenceSizeForFooterInSection:(NSInteger)section {
    return collectionView == self.gridView
               ? CGSizeMake(CGRectGetWidth(collectionView.bounds), 72)
               : CGSizeZero;
}

@end
