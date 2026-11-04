//
//  ModernSettingsPageViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/ModernSettingsPageViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "Headers/TWHeaders.h"
#import "Settings/ModernSettingsCells.h"
#import "ThemeColor/Palette.h"

static char kBHTSettingsPreferenceKeyAssociation;
static char kBHTFontPickerTypeAssociation;

extern UIColor* CurrentAccentColor(void);

NSString* BHTSettingsKeyForSwitch(UISwitch* settingsSwitch) {
    return objc_getAssociatedObject(
        settingsSwitch, &kBHTSettingsPreferenceKeyAssociation);
}

void BHTMarkNeoFreeBirdFontPicker(UIFontPickerViewController* picker,
                                  NSString* fontType) {
    objc_setAssociatedObject(picker, &kBHTFontPickerTypeAssociation,
                             fontType, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

NSString* BHTFontTypeForPicker(UIFontPickerViewController* picker) {
    return objc_getAssociatedObject(picker,
                                    &kBHTFontPickerTypeAssociation);
}

@interface ModernSettingsPageViewController ()
@property (nonatomic, copy) NSString* registryPageKey;
@property (nonatomic, copy) NSArray<NSDictionary*>* visibleSections;
@property (nonatomic, assign) BOOL settingsSearchRevealScheduled;
@property (nonatomic, assign) NSUInteger settingsSearchRevealAttempts;
@property (nonatomic, assign) BOOL settingsSearchPageDidAppear;
- (void)scheduleSettingsSearchTargetRevealIfNeeded;
- (void)revealSettingsSearchTargetIfNeeded;
- (void)spotlightSettingsSearchTargetCell:(UITableViewCell*)cell;
@end

@implementation ModernSettingsPageViewController

#pragma mark - Lifecycle

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    return [self initWithAccount:account pageKey:nil];
}

- (instancetype)initWithAccount:(TFNTwitterAccount*)account pageKey:(NSString*)pageKey {
    if ((self = [super init])) {
        self.account = account;
        self.registryPageKey = pageKey;
        [self buildSettingsList];
        [self updateVisibleToggles];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // A global-search target may be a conditional child (for example a font
    // picker while custom fonts are off). Include that one row for navigation
    // without changing its parent preference.
    [self updateVisibleToggles];
    [self setupNav];
    [self setupTable];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.settingsSearchPageDidAppear = YES;
    [self scheduleSettingsSearchTargetRevealIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.settingsSearchPageDidAppear = NO;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // UIKit may report viewDidAppear before a grouped table has realized the
    // destination row. Scheduling from layout makes the reveal deterministic
    // without repeatedly running it after the target succeeds.
    [self scheduleSettingsSearchTargetRevealIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.view.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.backgroundColor = [Palette currentBackgroundColor];
    // Search may temporarily reveal a child whose parent toggle is off.
    // Rebuild on every return so that exception lasts only long enough to
    // reach the requested setting.
    [self updateVisibleToggles];
    [self.tableView reloadData];
}

#pragma mark - Page Registry

- (NSString*)pageKey {
    return self.registryPageKey;
}

- (NSString*)pageTitleKey {
    return [BHTSettings titleKeyForPage:[self pageKey]];
}

- (NSString*)pageSubtitleKey {
    return [BHTSettings subtitleKeyForPage:[self pageKey]];
}

- (void)buildSettingsList {
    self.toggles = [BHTSettings settingsForPage:[self pageKey]];
}

#pragma mark - Setup

- (void)setupNav {
    NSString* title = [[BHTBundle sharedBundle] localizedStringForKey:[self pageTitleKey]];
    if (self.account) {
        self.navigationItem.titleView =
            [objc_getClass("TFNTitleView") titleViewWithTitle:title
                                                     subtitle:self.account.displayUsername];
    } else {
        self.title = title;
    }
}

- (void)setupTable {
    self.view.backgroundColor = [Palette currentBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 80;
    [self.tableView registerClass:[ModernSettingsToggleCell class]
           forCellReuseIdentifier:@"ToggleCell"];
    [self.tableView registerClass:[ModernSettingsTableViewCell class]
           forCellReuseIdentifier:@"ButtonCell"];
    [self.tableView registerClass:[ModernSettingsCompactButtonCell class]
           forCellReuseIdentifier:@"CompactButtonCell"];
    [self.view addSubview:self.tableView];
}

#pragma mark - Visible Toggles

- (void)updateVisibleToggles {
    NSMutableArray* visible = [NSMutableArray array];
    for (NSDictionary* toggleData in self.toggles) {
        NSString* parentKey = toggleData[@"parentKey"];
        if (parentKey) {
            BOOL parentEnabled = [BHTSettings boolForKey:parentKey];
            BOOL isSearchTarget =
                self.settingsSearchTargetIdentifier.length > 0 &&
                ([toggleData[@"key"]
                    isEqualToString:
                        self.settingsSearchTargetIdentifier] ||
                 [toggleData[@"titleKey"]
                    isEqualToString:
                        self.settingsSearchTargetIdentifier]);
            if (parentEnabled || isSearchTarget) {
                [visible addObject:toggleData];
            }
        } else {
            [visible addObject:toggleData];
        }
    }
    self.visibleToggles = [visible copy];

    NSMutableArray<NSMutableDictionary*>* sections =
        [NSMutableArray array];
    NSMutableDictionary<NSString*, NSMutableDictionary*>* sectionsByKey =
        [NSMutableDictionary dictionary];
    for (NSDictionary* entry in visible) {
        NSString* sectionKey = entry[@"sectionKey"] ?: @"";
        NSMutableDictionary* section = sectionsByKey[sectionKey];
        if (!section) {
            section = [@{
                @"titleKey": sectionKey,
                @"settings": [NSMutableArray array]
            } mutableCopy];
            sectionsByKey[sectionKey] = section;
            [sections addObject:section];
        }
        [section[@"settings"] addObject:entry];
    }

    NSMutableArray* immutableSections = [NSMutableArray array];
    for (NSDictionary* section in sections) {
        [immutableSections addObject:@{
            @"titleKey": section[@"titleKey"],
            @"settings": [section[@"settings"] copy]
        }];
    }
    self.visibleSections = [immutableSections copy];
}

- (void)scheduleSettingsSearchTargetRevealIfNeeded {
    if (self.settingsSearchTargetIdentifier.length == 0 ||
        self.settingsSearchRevealScheduled ||
        !self.settingsSearchPageDidAppear || !self.tableView.window) {
        return;
    }
    self.settingsSearchRevealScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.settingsSearchRevealScheduled = NO;
        [strongSelf revealSettingsSearchTargetIfNeeded];
    });
}

- (void)spotlightSettingsSearchTargetCell:(UITableViewCell*)cell {
    if (!cell.window) return;

    UIColor* accent = CurrentAccentColor() ?: UIColor.systemBlueColor;
    UIView* spotlight =
        [[UIView alloc] initWithFrame:CGRectInset(cell.bounds, 3, 2)];
    spotlight.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    spotlight.userInteractionEnabled = NO;
    spotlight.backgroundColor = [accent colorWithAlphaComponent:0.14];
    spotlight.layer.cornerRadius = 12;
    spotlight.layer.borderWidth = 2;
    spotlight.layer.borderColor = accent.CGColor;
    spotlight.alpha = 0;
    [cell addSubview:spotlight];

    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification,
                                    cell);
    if (UIAccessibilityIsReduceMotionEnabled()) {
        spotlight.alpha = 1;
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(0.9 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                [spotlight removeFromSuperview];
            });
        return;
    }
    [UIView animateKeyframesWithDuration:1.15
                                  delay:0
                                options:
                                    UIViewKeyframeAnimationOptionAllowUserInteraction
                             animations:^{
        [UIView addKeyframeWithRelativeStartTime:0
                                relativeDuration:0.2
                                      animations:^{
            spotlight.alpha = 1;
        }];
        [UIView addKeyframeWithRelativeStartTime:0.58
                                relativeDuration:0.42
                                      animations:^{
            spotlight.alpha = 0;
        }];
    }
                             completion:^(__unused BOOL finished) {
        [spotlight removeFromSuperview];
    }];
}

- (void)revealSettingsSearchTargetIfNeeded {
    NSString* target = self.settingsSearchTargetIdentifier;
    if (target.length == 0 || !self.tableView.window) return;

    // Recompute conditional rows with the still-pending target, then force a
    // layout pass before asking UIKit for the concrete destination cell.
    [self updateVisibleToggles];
    [self.tableView reloadData];
    [self.tableView layoutIfNeeded];

    NSDictionary* targetEntry = nil;
    for (NSDictionary* entry in self.toggles) {
        if ([entry[@"key"] isEqualToString:target] ||
            [entry[@"titleKey"] isEqualToString:target]) {
            targetEntry = entry;
            break;
        }
    }

    NSIndexPath* match = nil;
    for (NSUInteger section = 0; section < self.visibleSections.count;
         section++) {
        NSArray* entries = self.visibleSections[section][@"settings"];
        for (NSUInteger row = 0; row < entries.count; row++) {
            NSDictionary* entry = entries[row];
            if ([entry[@"key"] isEqualToString:target] ||
                [entry[@"titleKey"] isEqualToString:target]) {
                match = [NSIndexPath indexPathForRow:row
                                          inSection:section];
                break;
            }
        }
        if (match) break;
    }
    if (!match) {
        // An invalid/stale identifier cannot become valid through another
        // layout pass, so discard it instead of retrying forever.
        self.settingsSearchTargetIdentifier = nil;
        self.settingsSearchShouldOpenTarget = NO;
        self.settingsSearchRevealAttempts = 0;
        return;
    }

    [self.tableView scrollToRowAtIndexPath:match
                         atScrollPosition:UITableViewScrollPositionMiddle
                                 animated:NO];
    [self.tableView layoutIfNeeded];
    UITableViewCell* targetCell =
        [self.tableView cellForRowAtIndexPath:match];
    if (!targetCell) {
        self.settingsSearchRevealAttempts += 1;
        if (self.settingsSearchRevealAttempts < 3) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW,
                              (int64_t)(0.05 * NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    [weakSelf
                        scheduleSettingsSearchTargetRevealIfNeeded];
                });
        } else {
            self.settingsSearchTargetIdentifier = nil;
            self.settingsSearchShouldOpenTarget = NO;
            self.settingsSearchRevealAttempts = 0;
        }
        return;
    }

    BOOL shouldOpen = self.settingsSearchShouldOpenTarget;
    self.settingsSearchTargetIdentifier = nil;
    self.settingsSearchShouldOpenTarget = NO;
    self.settingsSearchRevealAttempts = 0;
    [self spotlightSettingsSearchTargetCell:targetCell];

    NSString* actionName = targetEntry[@"action"];
    if (shouldOpen && actionName.length > 0) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(0.3 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                // Only auto-open while this remains the visible page. A
                // fast back gesture must not trigger a delayed picker.
                if (self.navigationController.topViewController != self) {
                    return;
                }
                // Route through the page's normal row-selection path. This
                // preserves subclass behavior such as Web settings attaching
                // the index path needed to refresh its saved subtitle.
                [self tableView:self.tableView
                    didSelectRowAtIndexPath:match];
            });
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return self.visibleSections.count;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.visibleSections.count) {
        return 0;
    }
    return [self.visibleSections[section][@"settings"] count];
}

- (NSDictionary*)settingAtIndexPath:(NSIndexPath*)indexPath {
    if (indexPath.section >= self.visibleSections.count) return nil;
    NSArray* settings =
        self.visibleSections[indexPath.section][@"settings"];
    if (indexPath.row >= settings.count) return nil;
    return settings[indexPath.row];
}

// Title key defaults to KEY_TITLE; an explicit titleKey takes precedence.
- (NSString*)localizedTitleForEntry:(NSDictionary*)entry {
    NSString* titleKey = entry[@"titleKey"];
    if (!titleKey) {
        titleKey = [NSString stringWithFormat:@"%@_TITLE", [entry[@"key"] uppercaseString]];
    }
    return [[BHTBundle sharedBundle] localizedStringForKey:titleKey];
}

// The bundle returns the key itself when no string exists, which counts as no detail.
- (NSString*)localizedDetailForKey:(NSString*)key {
    NSString* detailKey = [NSString stringWithFormat:@"%@_DETAIL", [key uppercaseString]];
    NSString* detail = [[BHTBundle sharedBundle] localizedStringForKey:detailKey];
    return [detail isEqualToString:detailKey] ? @"" : detail;
}

// Localized at render time; the registry can't call localizedStringForKey
// without re-entering the settings lookup.
- (NSString*)defaultSubtitleForEntry:(NSDictionary*)entry {
    NSString* subtitleDefaultKey = entry[@"subtitleDefaultKey"];
    if (subtitleDefaultKey) {
        return [[BHTBundle sharedBundle] localizedStringForKey:subtitleDefaultKey];
    }
    return entry[@"subtitleDefault"];
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    NSDictionary* toggleData = [self settingAtIndexPath:indexPath];
    if (!toggleData) return [UITableViewCell new];
    NSString* type = toggleData[@"type"];
    if ([type isEqualToString:@"compactButton"]) {
        ModernSettingsCompactButtonCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"CompactButtonCell"
                                            forIndexPath:indexPath];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = @"";
        NSString* prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            NSString* defaultSubtitle = [self defaultSubtitleForEntry:toggleData];
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: defaultSubtitle;
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 &&
                ![subtitle isEqualToString:defaultSubtitle]) {
                subtitle = @"••••••••••••••••";
            }
        }
        [cell configureWithTitle:title subtitle:subtitle];
        return cell;
    } else if ([type isEqualToString:@"button"]) {
        ModernSettingsTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ButtonCell"
                                                                            forIndexPath:indexPath];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = @"";
        NSString* prefKey = toggleData[@"prefKeyForSubtitle"];
        if (prefKey) {
            NSString* defaultSubtitle = [self defaultSubtitleForEntry:toggleData];
            subtitle = [[NSUserDefaults standardUserDefaults] objectForKey:prefKey] ?: defaultSubtitle;
            if ([toggleData[@"isSecure"] boolValue] && subtitle.length > 0 &&
                ![subtitle isEqualToString:defaultSubtitle]) {
                subtitle = @"••••••••••••••••";
            }
        }
        NSString* iconName = toggleData[@"icon"];
        [cell configureWithTitle:title subtitle:subtitle iconName:iconName];
        return cell;
    } else {
        ModernSettingsToggleCell* cell = [tableView dequeueReusableCellWithIdentifier:@"ToggleCell"
                                                                         forIndexPath:indexPath];
        NSString* key = toggleData[@"key"];
        NSString* title = [self localizedTitleForEntry:toggleData];
        NSString* subtitle = [self localizedDetailForKey:key];
        NSString* unavailable = [BHTSettings unavailableReasonKeyForPreference:key];
        if (unavailable) subtitle = [[BHTBundle sharedBundle] localizedStringForKey:unavailable];
        [cell configureWithTitle:title subtitle:subtitle];
        BOOL isEnabled = [[[NSUserDefaults standardUserDefaults] objectForKey:key]
                              ?: toggleData[@"default"] boolValue];
        cell.toggleSwitch.enabled = unavailable == nil;
        cell.toggleSwitch.on = unavailable ? NO : isEnabled;
        cell.contentView.alpha = unavailable ? 0.55 : 1.0;
        cell.accessibilityHint = unavailable ? subtitle : nil;
        objc_setAssociatedObject(
            cell.toggleSwitch, &kBHTSettingsPreferenceKeyAssociation, key,
            OBJC_ASSOCIATION_COPY_NONATOMIC);
        [cell.toggleSwitch removeTarget:self
                                 action:@selector(switchChanged:)
                       forControlEvents:UIControlEventValueChanged];
        [cell.toggleSwitch addTarget:self
                              action:@selector(switchChanged:)
                    forControlEvents:UIControlEventValueChanged];
        return cell;
    }
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary* data = [self settingAtIndexPath:indexPath];
    if (!data) return;
    if ([data[@"type"] isEqualToString:@"button"] ||
        [data[@"type"] isEqualToString:@"compactButton"]) {
        NSString* actionName = data[@"action"];
        if (actionName) {
            SEL action = NSSelectorFromString(actionName);
            if ([self respondsToSelector:action]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [self performSelector:action
                           withObject:data];
#pragma clang diagnostic pop
            }
        }
    }
}

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 0)];
    UIView* previous = nil;

    if (section == 0) {
        UILabel* detail = [UILabel new];
        detail.translatesAutoresizingMaskIntoConstraints = NO;
        detail.text = [[BHTBundle sharedBundle]
            localizedStringForKey:[self pageSubtitleKey]];
        detail.numberOfLines = 0;
        detail.font =
            [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        detail.textColor = [Palette currentSecondaryTextColor];
        [header addSubview:detail];
        [NSLayoutConstraint activateConstraints:@[
            [detail.leadingAnchor
                constraintEqualToAnchor:header.leadingAnchor
                               constant:20],
            [detail.trailingAnchor
                constraintEqualToAnchor:header.trailingAnchor
                               constant:-20],
            [detail.topAnchor constraintEqualToAnchor:header.topAnchor
                                              constant:8]
        ]];
        previous = detail;
    }

    NSString* sectionTitleKey =
        section < (NSInteger)self.visibleSections.count
            ? self.visibleSections[section][@"titleKey"]
            : nil;
    if (sectionTitleKey.length > 0) {
        UILabel* title = [UILabel new];
        title.translatesAutoresizingMaskIntoConstraints = NO;
        title.text = [[BHTBundle sharedBundle]
            localizedStringForKey:sectionTitleKey];
        title.numberOfLines = 0;
        title.font =
            [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        title.textColor = [Palette currentTextColor];
        [header addSubview:title];
        NSLayoutYAxisAnchor* topAnchor =
            previous ? previous.bottomAnchor : header.topAnchor;
        CGFloat topSpacing = previous ? 18.0 : 10.0;
        [NSLayoutConstraint activateConstraints:@[
            [title.leadingAnchor
                constraintEqualToAnchor:header.leadingAnchor
                               constant:20],
            [title.trailingAnchor
                constraintEqualToAnchor:header.trailingAnchor
                               constant:-20],
            [title.topAnchor
                constraintEqualToAnchor:topAnchor
                               constant:topSpacing]
        ]];
        previous = title;
    }

    if (previous) {
        [previous.bottomAnchor
            constraintEqualToAnchor:header.bottomAnchor
                           constant:-8]
            .active = YES;
    }
    return header;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    NSString* sectionTitleKey =
        section < (NSInteger)self.visibleSections.count
            ? self.visibleSections[section][@"titleKey"]
            : nil;
    return section == 0 || sectionTitleKey.length > 0
               ? UITableViewAutomaticDimension
               : CGFLOAT_MIN;
}

#pragma mark - Switch Handling

- (void)switchChanged:(UISwitch*)sender {
    NSString* key = BHTSettingsKeyForSwitch(sender);
    if (key) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
        [BHTSettings notePreferencesChanged];
        [self updateAndAnimateChangesForKey:key];
    }
}

- (void)updateAndAnimateChangesForKey:(NSString*)key {
    [self updateVisibleToggles];
    [UIView transitionWithView:self.tableView
                      duration:0.2
                       options:UIViewAnimationOptionTransitionCrossDissolve |
                               UIViewAnimationOptionAllowAnimatedContent
                    animations:^{
                        [self.tableView reloadData];
                    }
                    completion:nil];
}

@end
