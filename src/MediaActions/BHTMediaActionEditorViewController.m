#import "MediaActions/BHTMediaActionEditorViewController.h"
#import <objc/runtime.h>
#import "Core/BHTBundle.h"
#import "Core/TwitterChirpFont.h"
#import "CustomTabBar/CustomTabBarCell.h"
#import "CustomTabBar/CustomTabBarNativeColors.h"
#import "CustomTabBar/CustomTabBarPreviewCell.h"
#import "CustomTabBar/CustomTabBarUtility.h"
#import "Headers/TFNHeaders.h"

extern UIColor* CurrentAccentColor(void);

@interface TFNFloatingActionButton : UIView
- (void)hideAnimated:(BOOL)animated completion:(id)completion;
@end

static NSString* const kBHTMediaActionGridHeaderID =
    @"mediaActionGridHeader";
static NSString* const kBHTMediaActionGridFooterID =
    @"mediaActionGridFooter";

@interface BHTMediaActionEditorViewController ()
    <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property(nonatomic) BHTMediaActionKind kind;
@property(nonatomic, strong, nullable) TFNTwitterAccount* account;
@property(nonatomic, strong) UICollectionView* gridView;
@property(nonatomic, strong) UICollectionView* previewView;
@property(nonatomic, strong) UIView* separator;
@property(nonatomic, strong) UILabel* emptyPreviewLabel;
@property(nonatomic, strong) NSMutableArray<NSString*>* allActions;
@property(nonatomic, strong) NSMutableArray<NSString*>* selectedActions;
@property(nonatomic, copy) NSArray<NSString*>* originalAllActions;
@property(nonatomic, copy) NSArray<NSString*>* originalSelectedActions;
@end

@implementation BHTMediaActionEditorViewController

- (instancetype)initWithKind:(BHTMediaActionKind)kind
                      account:(TFNTwitterAccount*)account {
    if ((self = [super init])) {
        self.kind = kind;
        self.account = account;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = CustomTabBarScreenBackgroundColor();
    [self setupNavigation];
    [self setupGridView];
    [self setupPreviewRow];
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

- (NSString*)titleLocalizationKey {
    switch (self.kind) {
        case BHTMediaActionKindPhoto:
            return @"MEDIA_ACTION_PHOTO_EDITOR_TITLE";
        case BHTMediaActionKindGIF:
            return @"MEDIA_ACTION_GIF_EDITOR_TITLE";
        case BHTMediaActionKindVideo:
        default:
            return @"MEDIA_ACTION_VIDEO_EDITOR_TITLE";
    }
}

- (void)setupNavigation {
    NSString* title = [[BHTBundle sharedBundle]
        localizedStringForKey:[self titleLocalizationKey]];
    if (self.account && objc_getClass("TFNTitleView")) {
        self.navigationItem.titleView =
            [objc_getClass("TFNTitleView")
                titleViewWithTitle:title
                          subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
    UIBarButtonItem* save = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemSave
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
               withReuseIdentifier:kBHTMediaActionGridHeaderID];
    [self.gridView registerClass:UICollectionReusableView.class
        forSupplementaryViewOfKind:UICollectionElementKindSectionFooter
               withReuseIdentifier:kBHTMediaActionGridFooterID];
    [self.view addSubview:self.gridView];

    UILongPressGestureRecognizer* reorder =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(handleGridReorder:)];
    [self.gridView addGestureRecognizer:reorder];
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

    self.emptyPreviewLabel = [UILabel new];
    self.emptyPreviewLabel.text = [[BHTBundle sharedBundle]
        localizedStringForKey:@"MEDIA_ACTION_EMPTY_PREVIEW_TITLE"];
    self.emptyPreviewLabel.textAlignment = NSTextAlignmentCenter;
    self.emptyPreviewLabel.textColor = UIColor.secondaryLabelColor;
    self.emptyPreviewLabel.font =
        [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
    self.previewView.backgroundView = self.emptyPreviewLabel;

    UILongPressGestureRecognizer* reorder =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(handlePreviewReorder:)];
    [self.previewView addGestureRecognizer:reorder];

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
    self.allActions = [[BHTMediaActionUtility
        orderedActionIdentifiersForKind:self.kind] mutableCopy];
    self.selectedActions = [[BHTMediaActionUtility
        visibleActionIdentifiersForKind:self.kind] mutableCopy];
    [self syncGridOrderToSelection];
    self.originalAllActions = [self.allActions copy];
    self.originalSelectedActions = [self.selectedActions copy];
    [self reloadCollections];
    [self recomputeChanges];
}

- (void)syncGridOrderToSelection {
    NSMutableArray<NSString*>* ordered =
        [self.selectedActions mutableCopy];
    for (NSString* identifier in self.allActions) {
        if (![ordered containsObject:identifier]) {
            [ordered addObject:identifier];
        }
    }
    self.allActions = ordered;
}

- (void)syncSelectionToGridOrder {
    NSSet<NSString*>* selected =
        [NSSet setWithArray:self.selectedActions];
    NSMutableArray<NSString*>* ordered = [NSMutableArray array];
    for (NSString* identifier in self.allActions) {
        if ([selected containsObject:identifier]) {
            [ordered addObject:identifier];
        }
    }
    self.selectedActions = ordered;
}

- (void)reloadCollections {
    self.emptyPreviewLabel.hidden = self.selectedActions.count != 0;
    [self.gridView reloadData];
    [self.previewView reloadData];
}

- (void)recomputeChanges {
    BOOL changed =
        ![self.allActions isEqualToArray:self.originalAllActions] ||
        ![self.selectedActions
            isEqualToArray:self.originalSelectedActions];
    self.navigationItem.rightBarButtonItem.enabled = changed;
}

#pragma mark - Settings search

- (NSIndexPath*)indexPathForSettingsSearchTarget:(NSString*)target {
    if (target.length == 0) return nil;
    for (NSUInteger item = 0; item < self.allActions.count; item++) {
        NSDictionary* metadata = [BHTMediaActionUtility
            metadataForIdentifier:self.allActions[item]
                             kind:self.kind];
        if ([metadata[TabPageKey] isEqualToString:target]) {
            return [NSIndexPath indexPathForItem:(NSInteger)item
                                      inSection:0];
        }
    }
    return nil;
}

- (void)highlightSettingsSearchTargetAtIndexPath:
    (NSIndexPath*)indexPath {
    if (!self.view.window ||
        (self.navigationController &&
         self.navigationController.topViewController != self)) {
        return;
    }
    [self.gridView layoutIfNeeded];
    UICollectionViewCell* cell =
        [self.gridView cellForItemAtIndexPath:indexPath];
    if (!cell) return;

    UIColor* accent = CurrentAccentColor() ?: UIColor.systemBlueColor;
    UIView* highlight =
        [[UIView alloc] initWithFrame:CGRectInset(cell.bounds, 2, 2)];
    highlight.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    highlight.userInteractionEnabled = NO;
    highlight.backgroundColor =
        [accent colorWithAlphaComponent:0.12];
    highlight.layer.cornerRadius = 14;
    highlight.layer.borderWidth = 3;
    highlight.layer.borderColor = accent.CGColor;
    highlight.alpha = 0;
    [cell addSubview:highlight];

    [UIView animateKeyframesWithDuration:0.85
                                  delay:0
                                options:
                                    UIViewKeyframeAnimationOptionAllowUserInteraction
                             animations:^{
        [UIView addKeyframeWithRelativeStartTime:0
                                relativeDuration:0.25
                                      animations:^{
            highlight.alpha = 1;
        }];
        [UIView addKeyframeWithRelativeStartTime:0.55
                                relativeDuration:0.45
                                      animations:^{
            highlight.alpha = 0;
        }];
    }
                             completion:^(__unused BOOL finished) {
        [highlight removeFromSuperview];
    }];
}

- (void)revealSettingsSearchTargetIfNeeded {
    NSString* target = self.settingsSearchTargetIdentifier;
    if (target.length == 0 || !self.gridView.window) return;

    NSIndexPath* indexPath =
        [self indexPathForSettingsSearchTarget:target];
    self.settingsSearchTargetIdentifier = nil;
    if (!indexPath) return;

    [self.gridView
        scrollToItemAtIndexPath:indexPath
              atScrollPosition:
                  UICollectionViewScrollPositionCenteredVertically
                      animated:YES];
    NSString* stableTarget = [target copy];
    __weak typeof(self) weakSelf = self;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(0.35 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf ||
                strongSelf.navigationController.topViewController !=
                    strongSelf) {
                return;
            }
            // The editor supports drag reordering, so resolve the stable
            // action identifier again instead of highlighting a stale slot.
            NSIndexPath* currentIndexPath =
                [strongSelf
                    indexPathForSettingsSearchTarget:stableTarget];
            if (currentIndexPath) {
                [strongSelf
                    highlightSettingsSearchTargetAtIndexPath:
                        currentIndexPath];
            }
        });
}

#pragma mark - Save and restore

- (void)saveTapped {
    NSMutableArray<NSString*>* hidden = [NSMutableArray array];
    for (NSString* identifier in self.allActions) {
        if (![self.selectedActions containsObject:identifier]) {
            [hidden addObject:identifier];
        }
    }
    [BHTMediaActionUtility
        setOrderedActionIdentifiers:self.allActions
            hiddenActionIdentifiers:hidden
                                kind:self.kind];
    self.originalAllActions = [self.allActions copy];
    self.originalSelectedActions = [self.selectedActions copy];
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
                                         @"MEDIA_ACTION_RESET_MESSAGE"]
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
                                     strongSelf.allActions =
                                         [[BHTMediaActionUtility
                                             canonicalActionIdentifiersForKind:
                                                 strongSelf.kind]
                                             mutableCopy];
                                     strongSelf.selectedActions =
                                         [strongSelf.allActions mutableCopy];
                                     [strongSelf reloadCollections];
                                     [strongSelf recomputeChanges];
                                 }]];
    [alert addAction:[UIAlertAction
                         actionWithTitle:[[BHTBundle sharedBundle]
                                             localizedTwitterStringForKey:
                                                 @"CANCEL_ACTION_LABEL"]
                                   style:UIAlertActionStyleCancel
                                 handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
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
    return collectionView == self.gridView ? self.allActions.count
                                           : self.selectedActions.count;
}

- (__kindof UICollectionViewCell*)collectionView:
                                      (UICollectionView*)collectionView
                          cellForItemAtIndexPath:(NSIndexPath*)indexPath {
    if (collectionView == self.previewView) {
        CustomTabBarPreviewCell* cell = [collectionView
            dequeueReusableCellWithReuseIdentifier:
                [CustomTabBarPreviewCell reuseIdentifier]
                                      forIndexPath:indexPath];
        NSDictionary* metadata = [BHTMediaActionUtility
            metadataForIdentifier:self.selectedActions[indexPath.item]
                             kind:self.kind];
        [cell configureWithImageName:metadata[TabImageKey]];
        return cell;
    }

    CustomTabBarCell* cell = [collectionView
        dequeueReusableCellWithReuseIdentifier:
            [CustomTabBarCell reuseIdentifier]
                                  forIndexPath:indexPath];
    NSString* identifier = self.allActions[indexPath.item];
    NSDictionary* metadata = [BHTMediaActionUtility
        metadataForIdentifier:identifier
                         kind:self.kind];
    [cell configureWithTitle:metadata[TabTitleKey]
                   imageName:metadata[TabImageKey]
                    selected:[self.selectedActions
                                 containsObject:identifier]
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
                                                   kBHTMediaActionGridHeaderID
                                                      forIndexPath:indexPath];
        [header.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
        UILabel* detail =
            [[UILabel alloc] initWithFrame:CGRectInset(header.bounds, 4, 0)];
        detail.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        detail.numberOfLines = 0;
        detail.font =
            [TwitterChirpFont(TwitterFontStyleRegular) fontWithSize:13];
        detail.textColor = UIColor.secondaryLabelColor;
        detail.text = [[BHTBundle sharedBundle]
            localizedStringForKey:@"MEDIA_ACTION_GRID_DETAIL"];
        [header addSubview:detail];
        return header;
    }

    UICollectionReusableView* footer =
        [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                           withReuseIdentifier:
                                               kBHTMediaActionGridFooterID
                                                  forIndexPath:indexPath];
    [footer.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    NSString* title = [[BHTBundle sharedBundle]
        localizedStringForKey:
            @"BHT_RESTORE_DEFAULTS"];
    UIButton* restore = nil;
    Class buttonClass = objc_getClass("TFNButton");
    if ([buttonClass
            respondsToSelector:@selector(buttonWithTitle:imageNamed:style:sizeClass:)]) {
        restore = [buttonClass buttonWithTitle:title
                                    imageNamed:nil
                                         style:2
                                     sizeClass:2];
    } else {
        restore = [UIButton buttonWithType:UIButtonTypeSystem];
        [restore setTitle:title forState:UIControlStateNormal];
    }
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
    NSString* identifier = self.allActions[indexPath.item];
    if ([self.selectedActions containsObject:identifier]) {
        [self.selectedActions removeObject:identifier];
    } else {
        [self.selectedActions addObject:identifier];
        [self syncSelectionToGridOrder];
    }
    self.emptyPreviewLabel.hidden = self.selectedActions.count != 0;
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
        NSString* identifier = self.allActions[source.item];
        [self.allActions removeObjectAtIndex:source.item];
        [self.allActions insertObject:identifier atIndex:destination.item];
        [self syncSelectionToGridOrder];
        [self.previewView reloadData];
    } else {
        NSString* identifier = self.selectedActions[source.item];
        [self.selectedActions removeObjectAtIndex:source.item];
        [self.selectedActions insertObject:identifier
                                   atIndex:destination.item];
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
               ? CGSizeMake(CGRectGetWidth(collectionView.bounds), 76)
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
