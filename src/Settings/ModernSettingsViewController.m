//
//  ModernSettingsViewController.m
//  NeoFreeBird
//
//  Created by BandarHelal on 25/11/2021.
//

#import "Settings/ModernSettingsViewController.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "CustomTabBar/CustomTabBarUtility.h"
#import "CustomTabBar/CustomTabBarViewController.h"
#import "Likes/BHTLikesNavigationUtility.h"
#import "Likes/BHTLikesNavigationViewController.h"
#import "MediaActions/BHTMediaActionEditorViewController.h"
#import "MediaActions/BHTMediaActionUtility.h"
#import "Settings/ModernSettingsCells.h"
#import "Settings/ModernSettingsPageViewController.h"
#import "Settings/Pages/AppearanceSettingsViewController.h"
#import "Settings/Pages/BackupSettingsViewController.h"
#import "Settings/Pages/BHTForYouKeywordFiltersViewController.h"
#import "Settings/Pages/DebugSettingsViewController.h"
#import "Settings/Pages/MediaDownloadsSettingsViewController.h"
#import "Settings/Pages/ProfilesSettingsViewController.h"
#import "Settings/Pages/PresetSettingsViewController.h"
#import "Settings/Pages/TimelinesSettingsViewController.h"
#import "Settings/Pages/TweetsSettingsViewController.h"
#import "Settings/Pages/WebSettingsViewController.h"
#import "Sidebar/BHTSidebarNavigationUtility.h"
#import "Sidebar/BHTSidebarNavigationViewController.h"
#import "ThemeColor/BHTThemePresets.h"
#import "ThemeColor/Palette.h"

static char kBHTRepresentedAvatarURLKey;
static char kBHTAvatarTaskKey;
static char kBHTAvatarRequestTokenKey;

static NSCache<NSString*, UIImage*>* BHTDeveloperAvatarCache(void) {
    static NSCache<NSString*, UIImage*>* cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 32;
    });
    return cache;
}

@interface ModernSettingsViewController ()
    <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating,
     UISearchControllerDelegate>
@property (nonatomic, strong) TFNTwitterAccount* account;
@property (nonatomic, strong) UITableView* tableView;
@property (nonatomic, strong) NSArray* sections;
@property (nonatomic, strong) UISearchController* settingsSearchController;
@property (nonatomic, copy) NSArray<NSDictionary*>* settingsSearchIndex;
@property (nonatomic, copy) NSArray<NSDictionary*>* filteredSettingsResults;
// Keep the selected result alive while UISearchController finishes its own
// dismissal transition. Pushing during that transition is unreliable on the
// native settings navigation controller used by newer X builds.
@property (nonatomic, copy, nullable)
    NSDictionary* pendingSettingsSearchResult;
@property (nonatomic, assign) BOOL settingsSearchRowsVisible;
@property (nonatomic, assign) BOOL settingsSearchDismissalPending;
@property (nonatomic, assign) NSUInteger
    settingsSearchDismissalFallbackAttempts;
@property (nonatomic, strong) NSArray* developerCells;
@property (nonatomic, strong) NSArray* coolKidsCells;
@property (nonatomic, strong) NSArray* specialThanksCells;
@property (nonatomic, strong) NSArray* officialPageCells;
- (void)themeDidChange:(NSNotification*)notification;
- (void)queueSettingsSearchResult:(NSDictionary*)result;
- (void)scheduleSettingsSearchDismissalFallback;
- (void)consumePendingSettingsSearchResultIfPossible;
- (void)openSettingsSearchResult:(NSDictionary*)result;
@end

@implementation ModernSettingsViewController

#pragma mark - Section Headers

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    if ([self isSettingsSearchActive]) {
        return nil;
    }
    if (section == 0) {
        UIView* headerView = [[UIView alloc] init];
        headerView.backgroundColor = [Palette currentBackgroundColor];

        UILabel* subtitleLabel = [[UILabel alloc] init];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.text = [[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_DETAIL"];
        subtitleLabel.numberOfLines = 0;
        subtitleLabel.textAlignment = NSTextAlignmentLeft;

        id fontGroup = [BHTManager sharedFontGroup];
        subtitleLabel.font = [fontGroup performSelector:@selector(subtext2Font)];

        subtitleLabel.textColor = [Palette currentSecondaryTextColor];

        [headerView addSubview:subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [subtitleLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor
                                                        constant:20],
            [subtitleLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor
                                                         constant:-20],
            [subtitleLabel.topAnchor constraintEqualToAnchor:headerView.topAnchor
                                                    constant:16],
            [subtitleLabel.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor
                                                       constant:-16]
        ]];

        return headerView;
    } else if (section == 1) {
        return [self headerViewWithTitle:[[BHTBundle sharedBundle]
                                             localizedStringForKey:@"DEVELOPER_SECTION_HEADER_TITLE"]];
    } else if (section == 2) {
        return [self headerViewWithTitle:[[BHTBundle sharedBundle]
                                             localizedStringForKey:@"COOL_KIDS_SECTION_HEADER_TITLE"]];
    } else if (section == 3) {
        return [self
            headerViewWithTitle:[[BHTBundle sharedBundle]
                                    localizedStringForKey:@"SPECIAL_THANKS_SECTION_HEADER_TITLE"]];
    } else if (section == 4) {
        return [self headerViewWithTitle:
                         [[BHTBundle sharedBundle]
                             localizedStringForKey:@"FOLLOW_OFFICIAL_PAGE_SECTION_HEADER_TITLE"]];
    }
    return nil;
}

- (UIView*)headerViewWithTitle:(NSString*)title {
    UIView* headerView = [[UIView alloc] init];
    headerView.backgroundColor = [Palette currentBackgroundColor];

    UILabel* titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = title;

    id fontGroup = [BHTManager sharedFontGroup];
    titleLabel.font = [fontGroup performSelector:@selector(headline1BoldFont)];

    titleLabel.textColor = [Palette currentTextColor];

    [headerView addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor
                                                 constant:20],
        [titleLabel.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor
                                                  constant:-20],
        [titleLabel.topAnchor constraintEqualToAnchor:headerView.topAnchor
                                             constant:32],
        [titleLabel.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor
                                                constant:-16]
    ]];

    return headerView;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    if ([self isSettingsSearchActive]) {
        return CGFLOAT_MIN;
    }
    if (section == 0 || section == 1 || section == 2 || section == 3 || section == 4) {
        return UITableViewAutomaticDimension;
    }
    return 0;
}

#pragma mark - Section Footers

- (UIView*)tableView:(UITableView*)tableView viewForFooterInSection:(NSInteger)section {
    if ([self isSettingsSearchActive]) {
        return nil;
    }
    if (section == 0) {
        UIView* separator = [[UIView alloc] initWithFrame:CGRectZero];
        separator.backgroundColor = [Palette currentSeparatorColor];
        return separator;
    }
    return nil;
}

- (CGFloat)tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section {
    if ([self isSettingsSearchActive]) {
        return CGFLOAT_MIN;
    }
    if (section == 0) {
        return 1.0 / UIScreen.mainScreen.scale;
    }
    return CGFLOAT_MIN;
}

#pragma mark - Lifecycle & Setup

- (instancetype)initWithAccount:(TFNTwitterAccount*)account {
    self = [super init];
    if (self) {
        _account = account;
        [self setupSections];
        [self setupDeveloperCells];
    }
    return self;
}

- (void)setupSections {
    self.sections = @[
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAYOUT_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_LAYOUT_SUBTITLE"],
            @"icon": @"settings_stroke",
            @"action": @"showLayoutSettings",
            @"pageKey": @"general"
        },
        @{
            @"title":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_APPEARANCE_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_APPEARANCE_SUBTITLE"],
            @"icon": @"paintbrush_stroke",
            @"action": @"showAppearanceSettings",
            @"pageKey": @"appearance"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_GROK_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_GROK_SUBTITLE"],
            @"icon": @"grok_icon_stroke",
            @"action": @"showGrokSettings",
            @"pageKey": @"grok"
        },
        @{
            @"title":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TIMELINES_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TIMELINES_SUBTITLE"],
            @"icon": @"home_stroke",
            @"action": @"showTimelinesSettings",
            @"pageKey": @"timelines"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWEETS_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_TWEETS_SUBTITLE"],
            @"icon": @"quill",
            @"action": @"showTweetsSettings",
            @"pageKey": @"tweets"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MEDIA_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_MEDIA_SUBTITLE"],
            @"icon": @"media_tab_stroke",
            @"action": @"showDownloadsSettings",
            @"pageKey": @"media_downloads"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PROFILES_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_PROFILES_SUBTITLE"],
            @"icon": @"account",
            @"action": @"showProfilesSettings",
            @"pageKey": @"profiles"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_SEARCH_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_SEARCH_SUBTITLE"],
            @"icon": @"search_stroke",
            @"action": @"showSearchSettings",
            @"pageKey": @"search"
        },
        @{
            @"title": [[BHTBundle sharedBundle]
                localizedStringForKey:@"MODERN_SETTINGS_BACKUP_TITLE"],
            @"subtitle": [[BHTBundle sharedBundle]
                localizedStringForKey:@"MODERN_SETTINGS_BACKUP_SUBTITLE"],
            @"icon": @"settings_stroke",
            @"action": @"showBackupSettings",
            @"pageKey": @"backup"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_WEB_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_WEB_SUBTITLE"],
            @"icon": @"globe_stroke",
            @"action": @"showWebSettings",
            @"pageKey": @"web"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_BRANDING_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_BRANDING_SUBTITLE"],
            @"icon": @"hash_stroke",
            @"action": @"showBrandingSettings",
            @"pageKey": @"branding"
        },
        @{
            @"title": [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_DEBUG_TITLE"],
            @"subtitle":
                [[BHTBundle sharedBundle] localizedStringForKey:@"MODERN_SETTINGS_DEBUG_SUBTITLE"],
            @"icon": @"code",
            @"action": @"showDebugSettings",
            @"pageKey": @"debug"
        }
    ];
}

- (void)setupDeveloperCells {
    self.developerCells = @[
        @{
            @"title": @"aridan",
            @"username": @"actuallyaridan",
            @"avatarURL": @"https://unavatar.io/x/actuallyaridan?fallback=https://neofreebird.com/"
                          @"images/actuallyaridan.png",
            @"userID": @"1351218086649720837"
        },
        @{
            @"title": @"Thea 🐾",
            @"username": @"nyaathea",
            @"avatarURL": @"https://unavatar.io/github/nyathea?fallback=https://neofreebird.com/images/"
                          @"theameoww.png",
            @"userID": @"1541742676009226241"
        },
        @{
            @"title": @"timi2506",
            @"username": @"timi2506",
            @"avatarURL": @"https://unavatar.io/github/timi2506?fallback=https://neofreebird.com/images/"
                          @"timi2506.png",
            @"userID": @"1684856685486063616"
        }
    ];

    self.coolKidsCells = @[
        @{
            @"title": @"Eevee",
            @"username": @"whoeevee1",
            @"avatarURL": @"https://unavatar.io/github/whoeevee?fallback=https://neofreebird.com/images/"
                          @"whoeevee.png",
            @"userID": @"1547956497342115844"
        },
        @{
            @"title": @"zxcvbn",
            @"username": @"zxxvbn0",
            @"avatarURL":
                @"https://unavatar.io/x/zxxvbn0?fallback=https://neofreebird.com/images/zxxvbn0.png",
            @"userID": @"1678444396717514760"
        }
    ];

    self.specialThanksCells = @[
        @{
            @"title": @"BandarHelal",
            @"username": @"BandarHL",
            @"avatarURL":
                @"https://unavatar.io/x/BandarHL?fallback=https://neofreebird.com/images/BandarHL.png",
            @"userID": @"827842200708853762"
        },
        @{
            @"title": @"YouGottaBillieve",
            @"username": @"ugottabillieve",
            @"avatarURL": @"https://unavatar.io/x/ugottabillieve?fallback=https://neofreebird.com/"
                          @"images/ugottabillieve.png",
            @"userID": @"1616194182187732992"
        }
    ];

    self.officialPageCells = @[@{
        @"title": @"NeoFreeBird",
        @"username": @"NeoFreeBird",
        @"avatarURL": @"https://unavatar.io/x/NeoFreeBird?fallback=https://neofreebird.com/images/"
                      @"NeoFreeBird.png",
        @"userID": @"1878595268255297537"
    }];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupNavigationBar];
    [self setupSettingsSearch];
    [self setupTableView];
    [self setupLayout];
    [self setupFooterLabel];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentSizeCategoryDidChange:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(themeDidChange:)
               name:BHTThemeDidChangeNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(themeDidChange:)
                name:BHTSettingsProfileDidApplyNotification
              object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(themeLibraryDidChange:)
               name:BHTThemeLibraryDidChangeNotification
             object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self buildSettingsSearchIndex];
    [self themeDidChange:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)contentSizeCategoryDidChange:(NSNotification*)notification {
    [self.tableView reloadData];
}

- (void)themeDidChange:(NSNotification*)notification {
    [Palette invalidateCustomAccentColorCache];
    self.view.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.tableFooterView.backgroundColor =
        [Palette currentBackgroundColor];
    [self setupFooterLabel];
    [self.tableView reloadData];
}

- (void)themeLibraryDidChange:(NSNotification*)notification {
    [self buildSettingsSearchIndex];
}

- (void)setupNavigationBar {
    self.view.backgroundColor = [Palette currentBackgroundColor];
    if (self.account) {
        self.navigationItem.titleView = [objc_getClass("TFNTitleView")
            titleViewWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_TITLE"]
                      subtitle:self.account.displayUsername];
    } else {
        self.title = [[BHTBundle sharedBundle] localizedStringForKey:@"NFB_SETTINGS_TITLE"];
    }
}

- (void)setupSettingsSearch {
    UISearchController* search =
        [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.delegate = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.autocapitalizationType =
        UITextAutocapitalizationTypeNone;
    search.searchBar.placeholder = [[BHTBundle sharedBundle]
        localizedStringForKey:@"SETTINGS_SEARCH_PLACEHOLDER"];
    self.settingsSearchController = search;
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    [self buildSettingsSearchIndex];
}

- (void)buildSettingsSearchIndex {
    BHTBundle* bundle = [BHTBundle sharedBundle];
    NSMutableArray<NSDictionary*>* index = [NSMutableArray array];
    NSMutableDictionary<NSString*, NSDictionary*>* pagesByKey =
        [NSMutableDictionary dictionary];

    for (NSDictionary* page in self.sections) {
        NSString* pageKey = page[@"pageKey"];
        if (pageKey) pagesByKey[pageKey] = page;
        NSString* searchText =
            [@[page[@"title"] ?: @"", page[@"subtitle"] ?: @"",
               pageKey ?: @""]
                componentsJoinedByString:@" "];
        [index addObject:@{
            @"kind": @"page",
            @"pageKey": pageKey ?: @"",
            @"identifier": pageKey ?: @"",
            @"title": page[@"title"] ?: @"",
            @"subtitle": page[@"subtitle"] ?: @"",
            @"icon": page[@"icon"] ?: @"settings_stroke",
            @"searchText": searchText
        }];
    }

    for (NSDictionary* setting in [BHTSettings allSearchableSettings]) {
        NSString* sourcePageKey = setting[@"pageKey"];
        NSString* pageKey =
            setting[@"searchPageKey"] ?: sourcePageKey;
        NSDictionary* page = pagesByKey[sourcePageKey];
        if (!page) continue;

        NSString* key = setting[@"key"];
        NSString* titleKey = setting[@"titleKey"];
        if (!titleKey && key.length > 0) {
            titleKey =
                [NSString stringWithFormat:@"%@_TITLE", key.uppercaseString];
        }
        NSString* title = [bundle localizedStringForKey:titleKey];
        if (title.length == 0 || [title isEqualToString:titleKey]) continue;

        NSString* detail = @"";
        if (key.length > 0) {
            NSString* detailKey =
                [NSString stringWithFormat:@"%@_DETAIL",
                                           key.uppercaseString];
            NSString* localized = [bundle localizedStringForKey:detailKey];
            if (![localized isEqualToString:detailKey]) detail = localized;
        }
        NSString* sectionTitle = @"";
        NSString* sectionKey = setting[@"sectionKey"];
        if (sectionKey.length > 0) {
            sectionTitle = [bundle localizedStringForKey:sectionKey];
        }
        NSString* categoryTitle = page[@"title"] ?: @"";
        NSString* categorySubtitle = page[@"subtitle"] ?: @"";
        NSString* resultSubtitle =
            detail.length > 0
                ? [NSString stringWithFormat:@"%@ — %@", categoryTitle,
                                             detail]
                : categoryTitle;
        NSString* identifier =
            setting[@"searchTargetIdentifier"] ?:
            (key ?: setting[@"titleKey"]);
        NSString* searchText =
            [@[title ?: @"", detail ?: @"", sectionTitle ?: @"",
               categoryTitle ?: @"", categorySubtitle ?: @"", key ?: @""]
                componentsJoinedByString:@" "];
        NSMutableDictionary* result = [@{
            @"kind": @"setting",
            @"pageKey": pageKey,
            @"sourcePageKey": sourcePageKey ?: pageKey,
            @"identifier": identifier ?: @"",
            @"title": title,
            @"subtitle": resultSubtitle,
            @"icon": page[@"icon"] ?: @"settings_stroke",
            @"searchText": searchText
        } mutableCopy];
        if (setting[@"type"]) result[@"type"] = setting[@"type"];
        if (setting[@"searchAutoOpen"]) {
            result[@"autoOpen"] = setting[@"searchAutoOpen"];
        }
        [index addObject:[result copy]];
    }

    NSDictionary* timelinesPage = pagesByKey[@"timelines"];
    NSString* forYouFiltersTitle =
        [bundle localizedStringForKey:@"FOR_YOU_KEYWORD_FILTERS_TITLE"];
    for (NSDictionary* filterSection in @[
             @{
                 @"identifier": BHTForYouFiltersUsernamesSearchTarget,
                 @"titleKey": @"FOR_YOU_FILTERS_USERNAMES_SECTION_TITLE",
                 @"detailKey": @"FOR_YOU_FILTERS_USERNAMES_SECTION_FOOTER",
                 @"synonyms":
                     @"author account handle username display name user "
                      @"mention mentioned @mention"
             },
             @{
                 @"identifier": BHTForYouFiltersPostTextSearchTarget,
                 @"titleKey": @"FOR_YOU_FILTERS_POST_TEXT_SECTION_TITLE",
                 @"detailKey": @"FOR_YOU_FILTERS_POST_TEXT_SECTION_FOOTER",
                 @"synonyms":
                     @"post tweet text content word phrase keyword"
             }
         ]) {
        NSString* title =
            [bundle localizedStringForKey:filterSection[@"titleKey"]];
        NSString* detail =
            [bundle localizedStringForKey:filterSection[@"detailKey"]];
        [index addObject:@{
            @"kind": @"deepSetting",
            @"route": @"forYouKeywordFilters",
            @"pageKey": @"timelines",
            @"identifier": filterSection[@"identifier"],
            @"title": title,
            @"subtitle":
                [NSString stringWithFormat:@"%@ — %@", forYouFiltersTitle,
                                           detail],
            @"icon": timelinesPage[@"icon"] ?: @"timeline_stroke",
            @"searchText":
                [@[title, detail, forYouFiltersTitle,
                   timelinesPage[@"title"] ?: @"",
                   filterSection[@"synonyms"], @"for you filter"]
                    componentsJoinedByString:@" "]
        }];
    }

    NSDictionary* appearancePage = pagesByKey[@"appearance"];
    NSString* themesCategory =
        [bundle localizedStringForKey:@"MODERN_SETTINGS_PRESETS_TITLE"];
    NSString* themesSubtitle =
        [bundle localizedStringForKey:@"MODERN_SETTINGS_PRESETS_SUBTITLE"];
    NSString* themesIcon =
        appearancePage[@"icon"] ?: @"paintbrush_stroke";
    [index addObject:@{
        @"kind": @"page",
        @"pageKey": @"themes",
        @"identifier": @"themes.current",
        @"title": themesCategory,
        @"subtitle": themesSubtitle,
        @"icon": themesIcon,
        @"searchText":
            [@[themesCategory, themesSubtitle,
               @"theme themes appearance color palette"]
                componentsJoinedByString:@" "]
    }];
    NSString* themeSection =
        [bundle localizedStringForKey:@"THEME_PRESETS_SECTION_TITLE"];
    for (NSDictionary* preset in [BHTThemePresets allThemes]) {
        NSString* title =
            [BHTThemePresets displayNameForPreset:preset];
        NSString* detail =
            [BHTThemePresets displayDetailForPreset:preset];
        [index addObject:@{
            @"kind": @"theme",
            @"pageKey": @"themes",
            @"identifier": preset[@"identifier"],
            @"title": title,
            @"subtitle":
                [NSString stringWithFormat:@"%@ — %@", themesCategory,
                                           detail],
            @"icon": themesIcon,
            @"searchText":
                [@[title, detail, themeSection, themesCategory]
                    componentsJoinedByString:@" "]
        }];
    }
    for (NSDictionary* themeAction in @[
             @{
                 @"identifier": @"themes.create",
                 @"titleKey": @"THEME_LIBRARY_CREATE",
                 @"detailKey": @"THEME_LIBRARY_CREATE_DETAIL",
                 @"autoOpen": @YES
             },
             @{
                 @"identifier": @"themes.accent_only",
                 @"titleKey": @"THEME_ACCENT_ONLY_TITLE",
                 @"detailKey": @"THEME_ACCENT_ONLY_DETAIL",
                 @"autoOpen": @YES
             }
         ]) {
        NSString* title =
            [bundle localizedStringForKey:themeAction[@"titleKey"]];
        NSString* detail =
            [bundle localizedStringForKey:themeAction[@"detailKey"]];
        [index addObject:@{
            @"kind": @"theme",
            @"pageKey": @"themes",
            @"identifier": themeAction[@"identifier"],
            @"title": title,
            @"subtitle":
                [NSString stringWithFormat:@"%@ — %@", themesCategory,
                                           detail],
            @"icon": themesIcon,
            @"autoOpen": themeAction[@"autoOpen"],
            @"searchText":
                [@[title, detail, themeSection, themesCategory,
                   @"accent only color colours palette builder"]
                    componentsJoinedByString:@" "]
        }];
    }

    NSString* navigationCategory =
        [bundle localizedStringForKey:@"MODERN_SETTINGS_APPEARANCE_TITLE"];
    NSString* mainNavigationTitle =
        [bundle localizedStringForKey:@"CUSTOM_TAB_BAR_OPTION_TITLE"];
    [index addObject:@{
        @"kind": @"deepSetting", @"route": @"mainNavigation",
        @"pageKey": @"appearance", @"identifier": @"hide_grok_sidebar",
        @"title": [bundle localizedStringForKey:@"NAV_HIDE_GROK_BOT_TITLE"],
        @"subtitle": mainNavigationTitle,
        @"icon": appearancePage[@"icon"] ?: @"paintbrush_stroke",
        @"searchText": @"hide try grok bot sidebar promotion edit navigation bar"
    }];
    for (NSDictionary* entry in [CustomTabBarUtility availableTabs]) {
        NSString* identifier = entry[TabPageKey];
        NSString* title = entry[TabTitleKey];
        if (identifier.length == 0 || title.length == 0) continue;
        [index addObject:@{
            @"kind": @"deepSetting",
            @"route": @"mainNavigation",
            @"pageKey": @"appearance",
            @"identifier": identifier,
            @"title": title,
            @"subtitle":
                [NSString stringWithFormat:@"%@ — %@", navigationCategory,
                                           mainNavigationTitle],
            @"icon": appearancePage[@"icon"] ?: @"paintbrush_stroke",
            @"searchText":
                [@[title, identifier, mainNavigationTitle,
                   navigationCategory,
                   @"tab tabs bottom navigation home explore likes"]
                    componentsJoinedByString:@" "]
        }];
    }

    NSString* likesNavigationTitle =
        [bundle localizedStringForKey:@"LIKES_NAVIGATION_EDITOR_TITLE"];
    for (NSDictionary* entry in
         [BHTLikesNavigationUtility availableTabs]) {
        NSString* identifier = entry[TabPageKey];
        NSString* title = entry[TabTitleKey];
        if (identifier.length == 0 || title.length == 0) continue;
        [index addObject:@{
            @"kind": @"deepSetting",
            @"route": @"likesNavigation",
            @"pageKey": @"appearance",
            @"identifier": identifier,
            @"title": title,
            @"subtitle":
                [NSString stringWithFormat:@"%@ — %@", navigationCategory,
                                           likesNavigationTitle],
            @"icon": appearancePage[@"icon"] ?: @"paintbrush_stroke",
            @"searchText":
                [@[title, identifier, likesNavigationTitle,
                   navigationCategory,
                   @"likes bookmarks videos articles posts tab"]
                    componentsJoinedByString:@" "]
        }];
    }
    NSString* waterfallTitle =
        [bundle localizedStringForKey:@"LIKES_MEDIA_WATERFALL_TITLE"];
    NSString* waterfallDetail =
        [bundle localizedStringForKey:@"LIKES_MEDIA_WATERFALL_DETAIL"];
    [index addObject:@{
        @"kind": @"deepSetting",
        @"route": @"likesNavigation",
        @"pageKey": @"appearance",
        @"identifier": @"waterfall",
        @"title": waterfallTitle,
        @"subtitle":
            [NSString stringWithFormat:@"%@ — %@", likesNavigationTitle,
                                       waterfallDetail],
        @"icon": appearancePage[@"icon"] ?: @"paintbrush_stroke",
        @"searchText":
            [@[waterfallTitle, waterfallDetail, likesNavigationTitle,
               @"likes media gallery grid selector"]
                componentsJoinedByString:@" "]
    }];

    NSString* sidebarTitle =
        [bundle localizedStringForKey:@"SIDEBAR_NAVIGATION_EDITOR_TITLE"];
    for (NSDictionary* entry in
         [BHTSidebarNavigationUtility availableItems]) {
        NSString* identifier = entry[TabPageKey];
        NSString* title = entry[TabTitleKey];
        if (identifier.length == 0 || title.length == 0) continue;
        [index addObject:@{
            @"kind": @"deepSetting",
            @"route": @"sidebarNavigation",
            @"pageKey": @"appearance",
            @"identifier": identifier,
            @"title": title,
            @"subtitle":
                [NSString stringWithFormat:@"%@ — %@", navigationCategory,
                                           sidebarTitle],
            @"icon": appearancePage[@"icon"] ?: @"paintbrush_stroke",
            @"searchText":
                [@[title, identifier, sidebarTitle, navigationCategory,
                   @"sidebar side menu drawer ipad profile history lists"]
                    componentsJoinedByString:@" "]
        }];
    }

    NSDictionary* mediaPage = pagesByKey[@"media_downloads"];
    NSString* mediaMenusTitle =
        [bundle localizedStringForKey:@"MEDIA_ACTION_MENU_EDITOR_TITLE"];
    for (NSDictionary* mediaKind in @[
             @{
                 @"kind": @(BHTMediaActionKindPhoto),
                 @"titleKey": @"MEDIA_ACTION_PHOTOS_TITLE",
                 @"detailKey": @"MEDIA_ACTION_PHOTOS_DETAIL",
                 @"identifier": @"photo"
             },
             @{
                 @"kind": @(BHTMediaActionKindVideo),
                 @"titleKey": @"MEDIA_ACTION_VIDEOS_TITLE",
                 @"detailKey": @"MEDIA_ACTION_VIDEOS_DETAIL",
                 @"identifier": @"video"
             },
             @{
                 @"kind": @(BHTMediaActionKindGIF),
                 @"titleKey": @"MEDIA_ACTION_GIFS_TITLE",
                 @"detailKey": @"MEDIA_ACTION_GIFS_DETAIL",
                 @"identifier": @"gif"
             }
         ]) {
        NSString* mediaTitle =
            [bundle localizedStringForKey:mediaKind[@"titleKey"]];
        NSString* mediaDetail =
            [bundle localizedStringForKey:mediaKind[@"detailKey"]];
        [index addObject:@{
            @"kind": @"deepSetting",
            @"route": @"mediaActionEditor",
            @"pageKey": @"media_downloads",
            @"mediaKind": mediaKind[@"kind"],
            @"identifier": mediaKind[@"identifier"],
            @"title": mediaTitle,
            @"subtitle":
                [NSString stringWithFormat:@"%@ — %@", mediaMenusTitle,
                                           mediaDetail],
            @"icon": mediaPage[@"icon"] ?: @"media_tab_stroke",
            @"searchText":
                [@[mediaTitle, mediaDetail, mediaMenusTitle,
                   mediaKind[@"identifier"], @"actions download share copy"]
                    componentsJoinedByString:@" "]
        }];

        for (NSDictionary* action in
             [BHTMediaActionUtility
                 availableActionsForKind:
                     [mediaKind[@"kind"] integerValue]]) {
            NSString* actionIdentifier = action[TabPageKey];
            NSString* actionTitle = action[TabTitleKey];
            if (actionIdentifier.length == 0 ||
                actionTitle.length == 0) {
                continue;
            }
            [index addObject:@{
                @"kind": @"deepSetting",
                @"route": @"mediaActionEditor",
                @"pageKey": @"media_downloads",
                @"mediaKind": mediaKind[@"kind"],
                @"identifier": actionIdentifier,
                @"title": actionTitle,
                @"subtitle":
                    [NSString stringWithFormat:@"%@ — %@", mediaMenusTitle,
                                               mediaTitle],
                @"icon": mediaPage[@"icon"] ?: @"media_tab_stroke",
                @"searchText":
                    [@[actionTitle, actionIdentifier, mediaTitle,
                       mediaDetail, mediaMenusTitle,
                       @"media menu action download share copy"]
                        componentsJoinedByString:@" "]
            }];
        }
    }
    self.settingsSearchIndex = [index copy];
    self.filteredSettingsResults = @[];
}

- (BOOL)isSettingsSearchActive {
    return self.settingsSearchRowsVisible;
}

- (void)updateSearchResultsForSearchController:
    (UISearchController*)searchController {
    NSString* query =
        [searchController.searchBar.text
            stringByTrimmingCharactersInSet:
                NSCharacterSet.whitespaceAndNewlineCharacterSet];
    // Deactivating UISearchController flips isActive before its table/layout
    // transition finishes. Keep serving the captured result rows until
    // didDismissSearchController: atomically resets and reloads the table.
    if (self.settingsSearchDismissalPending) return;
    // Once search is presented, keep the result-table data source in place
    // until didDismissSearchController:. This also prevents an empty query
    // from exposing tappable normal rows underneath the active search UI.
    if (searchController.isActive || query.length > 0) {
        self.settingsSearchRowsVisible = YES;
    }
    if (query.length == 0) {
        self.filteredSettingsResults = @[];
    } else {
        NSMutableArray<NSDictionary*>* matches = [NSMutableArray array];
        for (NSDictionary* result in self.settingsSearchIndex) {
            NSRange match =
                [result[@"searchText"]
                    rangeOfString:query
                         options:NSCaseInsensitiveSearch |
                                 NSDiacriticInsensitiveSearch];
            if (match.location != NSNotFound) {
                [matches addObject:result];
            }
        }
        [matches sortUsingComparator:^NSComparisonResult(
                     NSDictionary* left, NSDictionary* right) {
            NSString* leftTitle =
                [left[@"title"] lowercaseString] ?: @"";
            NSString* rightTitle =
                [right[@"title"] lowercaseString] ?: @"";
            NSString* normalizedQuery = query.lowercaseString;
            NSInteger (^rank)(NSDictionary*, NSString*) =
                ^NSInteger(NSDictionary* result, NSString* title) {
                    if ([title isEqualToString:normalizedQuery]) return 0;
                    if ([title hasPrefix:normalizedQuery]) return 1;
                    return [result[@"kind"] isEqualToString:@"page"] ? 3
                                                                    : 2;
                };
            NSInteger leftRank = rank(left, leftTitle);
            NSInteger rightRank = rank(right, rightTitle);
            if (leftRank < rightRank) return NSOrderedAscending;
            if (leftRank > rightRank) return NSOrderedDescending;
            return [leftTitle localizedCaseInsensitiveCompare:rightTitle];
        }];
        self.filteredSettingsResults = [matches copy];
    }
    [self.tableView reloadData];
    if (query.length > 0 && self.filteredSettingsResults.count == 0) {
        UILabel* emptyLabel = [UILabel new];
        emptyLabel.text = [[BHTBundle sharedBundle]
            localizedStringForKey:@"SETTINGS_SEARCH_NO_RESULTS"];
        emptyLabel.textAlignment = NSTextAlignmentCenter;
        emptyLabel.textColor = [Palette currentSecondaryTextColor];
        emptyLabel.font =
            [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        emptyLabel.numberOfLines = 0;
        self.tableView.backgroundView = emptyLabel;
    } else {
        self.tableView.backgroundView = nil;
    }
}

- (void)willPresentSearchController:
    (UISearchController*)searchController {
    // Rebuild immediately before searching so renamed personal themes and
    // navigation entries discovered during this app session are searchable.
    [self buildSettingsSearchIndex];
    self.settingsSearchRowsVisible = YES;
    self.filteredSettingsResults = @[];
    self.tableView.backgroundView = nil;
    [self.tableView reloadData];
}

- (void)didDismissSearchController:(UISearchController*)searchController {
    self.settingsSearchDismissalPending = NO;
    self.settingsSearchRowsVisible = NO;
    self.settingsSearchDismissalFallbackAttempts = 0;
    self.filteredSettingsResults = @[];
    self.tableView.backgroundView = nil;
    [self.tableView reloadData];
    // UISearchController has now completed its presentation transition, so it
    // is safe to push the exact destination on X's native settings stack.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self consumePendingSettingsSearchResultIfPossible];
    });
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = [Palette currentBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.estimatedRowHeight = 80;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedSectionHeaderHeight = 50;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;
    [self.tableView registerClass:[ModernSettingsTableViewCell class]
           forCellReuseIdentifier:@"SettingsCell"];
    [self.view addSubview:self.tableView];
}

- (void)setupLayout {
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)setupFooterLabel {
    UIView* footerView =
        [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 60)];
    footerView.backgroundColor = [Palette currentBackgroundColor];

    UILabel* footerLabel = [[UILabel alloc] init];
    footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    footerLabel.text = @NFB_VERSION_STRING " (" NFB_COMMIT_STRING ")";
    footerLabel.numberOfLines = 0;
    footerLabel.textAlignment = NSTextAlignmentLeft;

    footerLabel.font = TwitterChirpFont(TwitterFontStyleRegular);

    footerLabel.textColor = [Palette currentSecondaryTextColor];

    [footerView addSubview:footerLabel];

    [NSLayoutConstraint activateConstraints:@[
        [footerLabel.leadingAnchor constraintEqualToAnchor:footerView.leadingAnchor
                                                  constant:20], // match table cell padding
        [footerLabel.trailingAnchor constraintEqualToAnchor:footerView.trailingAnchor
                                                   constant:-20],
        [footerLabel.topAnchor constraintEqualToAnchor:footerView.topAnchor
                                              constant:8],
        [footerLabel.bottomAnchor constraintEqualToAnchor:footerView.bottomAnchor
                                                 constant:-8]
    ]];

    self.tableView.tableFooterView = footerView;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    if ([self isSettingsSearchActive]) {
        return 1;
    }
    return 5;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isSettingsSearchActive]) {
        return self.filteredSettingsResults.count;
    }
    if (section == 0) {
        return self.sections.count;
    } else if (section == 1) {
        return self.developerCells.count;
    } else if (section == 2) {
        return self.coolKidsCells.count;
    } else if (section == 3) {
        return self.specialThanksCells.count;
    } else if (section == 4) {
        return self.officialPageCells.count;
    }
    return 0;
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    if ([self isSettingsSearchActive]) {
        ModernSettingsTableViewCell* cell =
            [tableView dequeueReusableCellWithIdentifier:@"SettingsCell"
                                            forIndexPath:indexPath];
        NSDictionary* result = self.filteredSettingsResults[indexPath.row];
        [cell configureWithTitle:result[@"title"]
                        subtitle:result[@"subtitle"]
                        iconName:result[@"icon"]];
        return cell;
    }
    if (indexPath.section == 0) {
        ModernSettingsTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsCell"
                                                                            forIndexPath:indexPath];
        NSDictionary* sectionData = self.sections[indexPath.row];
        [cell configureWithTitle:sectionData[@"title"]
                        subtitle:sectionData[@"subtitle"]
                        iconName:sectionData[@"icon"]];
        return cell;
    } else if (indexPath.section == 1) {
        return [self developerCellForTableView:tableView
                                   atIndexPath:indexPath
                                     fromArray:self.developerCells];
    } else if (indexPath.section == 2) {
        return [self developerCellForTableView:tableView
                                   atIndexPath:indexPath
                                     fromArray:self.coolKidsCells];
    } else if (indexPath.section == 3) {
        return [self developerCellForTableView:tableView
                                   atIndexPath:indexPath
                                     fromArray:self.specialThanksCells];
    } else if (indexPath.section == 4) {
        return [self developerCellForTableView:tableView
                                   atIndexPath:indexPath
                                     fromArray:self.officialPageCells];
    }

    return nil;
}

- (UITableViewCell*)developerCellForTableView:(UITableView*)tableView
                                  atIndexPath:(NSIndexPath*)indexPath
                                    fromArray:(NSArray*)array {
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"DeveloperCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"DeveloperCell"];
        [self setupDeveloperCell:cell];
    }
    NSDictionary* developer = array[indexPath.row];
    [self configureDeveloperCell:cell withDeveloper:developer];
    return cell;
}

#pragma mark - Developer Cell Setup

- (void)setupDeveloperCell:(UITableViewCell*)cell {
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.imageView.image = nil;
    UIImageView* avatarImageView = [[UIImageView alloc] init];
    avatarImageView.translatesAutoresizingMaskIntoConstraints = NO;
    avatarImageView.layer.cornerRadius = 26;
    avatarImageView.clipsToBounds = YES;
    avatarImageView.contentMode = UIViewContentModeScaleAspectFill;
    avatarImageView.tag = 100;
    [cell.contentView addSubview:avatarImageView];
    UILabel* nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.tag = 101;
    nameLabel.adjustsFontForContentSizeCategory = YES;
    [cell.contentView addSubview:nameLabel];
    UILabel* usernameLabel = [[UILabel alloc] init];
    usernameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    usernameLabel.tag = 102;
    usernameLabel.adjustsFontForContentSizeCategory = YES;
    [cell.contentView addSubview:usernameLabel];
    UIImageView* devChevron = [[UIImageView alloc] init];
    devChevron.translatesAutoresizingMaskIntoConstraints = NO;
    devChevron.tag = 103;
    devChevron.contentMode = UIViewContentModeScaleAspectFit;
    [cell.contentView addSubview:devChevron];
    [NSLayoutConstraint activateConstraints:@[
        [avatarImageView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor
                                                      constant:20],
        [avatarImageView.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [avatarImageView.widthAnchor constraintEqualToConstant:52],
        [avatarImageView.heightAnchor constraintEqualToConstant:52],
        [nameLabel.leadingAnchor constraintEqualToAnchor:avatarImageView.trailingAnchor
                                                constant:12],
        [nameLabel.trailingAnchor constraintEqualToAnchor:devChevron.leadingAnchor
                                                 constant:-12],
        [nameLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor
                                            constant:16],
        [usernameLabel.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [usernameLabel.trailingAnchor constraintEqualToAnchor:devChevron.leadingAnchor
                                                     constant:-12],
        [usernameLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor
                                                constant:2],
        [usernameLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor
                                                   constant:-16],
        [devChevron.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor
                                                  constant:-20],
        [devChevron.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [devChevron.widthAnchor constraintEqualToConstant:18],
        [devChevron.heightAnchor constraintEqualToConstant:18]
    ]];
    cell.backgroundColor = [Palette currentSurfaceColor];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
}

- (void)configureDeveloperCell:(UITableViewCell*)cell withDeveloper:(NSDictionary*)developer {
    UIImageView* avatarImageView = [cell.contentView viewWithTag:100];
    UILabel* nameLabel = [cell.contentView viewWithTag:101];
    UILabel* usernameLabel = [cell.contentView viewWithTag:102];
    id fontGroup = [BHTManager sharedFontGroup];
    UIColor* textColor = [Palette currentTextColor];
    UIColor* subtitleColor = [Palette currentSecondaryTextColor];
    cell.backgroundColor = [Palette currentSurfaceColor];
    nameLabel.text = developer[@"title"];
    nameLabel.font = [fontGroup performSelector:@selector(bodyBoldFont)];
    nameLabel.textColor = textColor;
    usernameLabel.text = [NSString stringWithFormat:@"@%@", developer[@"username"]];
    usernameLabel.font = [fontGroup performSelector:@selector(subtext2Font)];
    usernameLabel.textColor = subtitleColor;
    UIImageView* devChevron = [cell.contentView viewWithTag:103];
    devChevron.image = [UIImage tfn_vectorImageNamed:@"chevron_right"
                                            fitsSize:CGSizeMake(18, 18)
                                           fillColor:subtitleColor];
    NSString* avatarURL = developer[@"avatarURL"];
    UIImage* placeholder = [UIImage systemImageNamed:@"person.circle.fill"];
    NSURLSessionDataTask* previousTask =
        objc_getAssociatedObject(avatarImageView, &kBHTAvatarTaskKey);
    [previousTask cancel];
    objc_setAssociatedObject(avatarImageView, &kBHTAvatarTaskKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(avatarImageView, &kBHTAvatarRequestTokenKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    avatarImageView.image = placeholder;
    objc_setAssociatedObject(
        avatarImageView, &kBHTRepresentedAvatarURLKey, avatarURL,
        OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (avatarURL.length == 0) return;

    UIImage* cached = [BHTDeveloperAvatarCache() objectForKey:avatarURL];
    if (cached) {
        avatarImageView.image = cached;
        return;
    }

    NSURL* url = [NSURL URLWithString:avatarURL];
    if (!url) return;
    NSString* requestToken = NSUUID.UUID.UUIDString;
    objc_setAssociatedObject(avatarImageView, &kBHTAvatarRequestTokenKey,
                             requestToken,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    NSURLSessionDataTask* task =
        [[NSURLSession sharedSession]
        dataTaskWithURL:url
      completionHandler:^(NSData* data, NSURLResponse* response,
                          NSError* error) {
          UIImage* image =
              error ? nil : [UIImage imageWithData:data];
          if (image) {
              [BHTDeveloperAvatarCache() setObject:image
                                            forKey:avatarURL];
          }
          dispatch_async(dispatch_get_main_queue(), ^{
              NSString* represented = objc_getAssociatedObject(
                  avatarImageView, &kBHTRepresentedAvatarURLKey);
              NSString* activeToken = objc_getAssociatedObject(
                  avatarImageView, &kBHTAvatarRequestTokenKey);
              if ([represented isEqualToString:avatarURL] &&
                  [activeToken isEqualToString:requestToken]) {
                  avatarImageView.image = image ?: placeholder;
                  objc_setAssociatedObject(
                      avatarImageView, &kBHTAvatarTaskKey, nil,
                      OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                  objc_setAssociatedObject(
                      avatarImageView, &kBHTAvatarRequestTokenKey, nil,
                      OBJC_ASSOCIATION_RETAIN_NONATOMIC);
              }
          });
      }];
    objc_setAssociatedObject(avatarImageView, &kBHTAvatarTaskKey, task,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [task resume];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    // Capture the result before dismissing search. Search-controller state can
    // change during the selection callback, while the result rows are still
    // visible in this table.
    if ([self isSettingsSearchActive]) {
        if (indexPath.section == 0 && indexPath.row >= 0 &&
            indexPath.row <
                (NSInteger)self.filteredSettingsResults.count) {
            NSDictionary* result =
                self.filteredSettingsResults[indexPath.row];
            [self queueSettingsSearchResult:result];
        }
        // Never reinterpret a stale search index path as a row from the
        // underlying settings/developer sections during dismissal.
        return;
    }

    if (indexPath.section == 0) {
        NSDictionary* sectionData = self.sections[indexPath.row];
        NSString* action = sectionData[@"action"];
        SEL selector = NSSelectorFromString(action);
        if ([self respondsToSelector:selector]) {
            IMP imp = [self methodForSelector:selector];
            void (*func)(id, SEL) = (void*)imp;
            func(self, selector);
        }
    } else if (indexPath.section == 1) {
        NSDictionary* developer = self.developerCells[indexPath.row];
        [self openTwitterProfileWithUserID:developer[@"userID"]];
    } else if (indexPath.section == 2) {
        NSDictionary* developer = self.coolKidsCells[indexPath.row];
        [self openTwitterProfileWithUserID:developer[@"userID"]];
    } else if (indexPath.section == 3) {
        NSDictionary* developer = self.specialThanksCells[indexPath.row];
        [self openTwitterProfileWithUserID:developer[@"userID"]];
    } else if (indexPath.section == 4) {
        NSDictionary* developer = self.officialPageCells[indexPath.row];
        [self openTwitterProfileWithUserID:developer[@"userID"]];
    }
}

- (void)openTwitterProfileWithUserID:(NSString*)userID {
    if (!userID.length) return;
    NSString* twitterURL = [NSString stringWithFormat:@"twitter://user?id=%@", userID];
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:twitterURL]
                                       options:@{}
                             completionHandler:nil];
}

#pragma mark - Navigation to Sub-pages

- (void)queueSettingsSearchResult:(NSDictionary*)result {
    if (!result || self.pendingSettingsSearchResult) return;
    self.pendingSettingsSearchResult = [result copy];
    self.settingsSearchDismissalPending = YES;
    self.settingsSearchDismissalFallbackAttempts = 0;
    [self.settingsSearchController.searchBar resignFirstResponder];

    if (self.settingsSearchController.isActive) {
        self.settingsSearchController.active = NO;

        // didDismissSearchController: is the primary handoff. Some native
        // settings hosts omit it, so retry a bounded fallback instead of
        // abandoning the selected result after one timing check.
        [self scheduleSettingsSearchDismissalFallback];
        return;
    }

    self.settingsSearchDismissalPending = NO;
    self.settingsSearchRowsVisible = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self consumePendingSettingsSearchResultIfPossible];
    });
}

- (void)scheduleSettingsSearchDismissalFallback {
    if (!self.pendingSettingsSearchResult) return;
    __weak typeof(self) weakSelf = self;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(0.2 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.pendingSettingsSearchResult) {
                return;
            }

            strongSelf.settingsSearchDismissalFallbackAttempts += 1;
            BOOL transitionActive =
                strongSelf.settingsSearchController.isActive ||
                strongSelf.settingsSearchController.transitionCoordinator !=
                    nil ||
                strongSelf.settingsSearchController.presentingViewController !=
                    nil;
            if (!transitionActive) {
                strongSelf.settingsSearchDismissalPending = NO;
                strongSelf.settingsSearchRowsVisible = NO;
                strongSelf.filteredSettingsResults = @[];
                [strongSelf.tableView reloadData];
                [strongSelf
                    consumePendingSettingsSearchResultIfPossible];
                return;
            }

            if (strongSelf.settingsSearchDismissalFallbackAttempts < 12) {
                [strongSelf scheduleSettingsSearchDismissalFallback];
            } else {
                // Do not push over a transition that never completed, but
                // release the pending state so a later search remains usable.
                strongSelf.pendingSettingsSearchResult = nil;
                strongSelf.settingsSearchDismissalPending = NO;
                strongSelf.settingsSearchRowsVisible = NO;
                strongSelf.filteredSettingsResults = @[];
                [strongSelf.tableView reloadData];
            }
        });
}

- (void)consumePendingSettingsSearchResultIfPossible {
    NSDictionary* result = self.pendingSettingsSearchResult;
    if (!result) return;
    self.pendingSettingsSearchResult = nil;
    self.settingsSearchDismissalPending = NO;
    self.settingsSearchDismissalFallbackAttempts = 0;
    if (self.navigationController &&
        self.navigationController.topViewController != self) {
        return;
    }
    [self openSettingsSearchResult:result];
}

- (UIViewController*)settingsControllerForPageKey:(NSString*)pageKey {
    if ([pageKey isEqualToString:@"appearance"]) {
        return [[AppearanceSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"timelines"]) {
        return [[TimelinesSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"tweets"]) {
        return [[TweetsSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"media_downloads"]) {
        return [[MediaDownloadsSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"profiles"]) {
        return [[ProfilesSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"web"]) {
        return [[WebSettingsViewController alloc] initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"debug"]) {
        return [[DebugSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"presets"] ||
        [pageKey isEqualToString:@"themes"]) {
        return [[PresetSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([pageKey isEqualToString:@"backup"]) {
        return [[BackupSettingsViewController alloc]
            initWithAccount:self.account];
    }
    if ([[BHTSettings allPageKeys] containsObject:pageKey]) {
        return [[ModernSettingsPageViewController alloc]
            initWithAccount:self.account
                    pageKey:pageKey];
    }
    return nil;
}

- (void)openSettingsSearchResult:(NSDictionary*)result {
    NSString* route = result[@"route"];
    // Category results intentionally open at the top of their page. Only
    // concrete setting/theme/deep results participate in exact-row reveal.
    NSString* targetIdentifier =
        [result[@"kind"] isEqualToString:@"page"]
            ? nil
            : result[@"identifier"];
    UIViewController* directController = nil;
    if ([route isEqualToString:@"mainNavigation"]) {
        CustomTabBarViewController* editor =
            [CustomTabBarViewController new];
        editor.settingsSearchTargetIdentifier = targetIdentifier;
        editor.title = [[BHTBundle sharedBundle]
            localizedStringForKey:
                @"CUSTOM_TAB_BAR_SETTINGS_NAVIGATION_TITLE"];
        directController = editor;
    } else if ([route isEqualToString:@"likesNavigation"]) {
        BHTLikesNavigationViewController* editor =
            [BHTLikesNavigationViewController new];
        editor.settingsSearchTargetIdentifier = targetIdentifier;
        editor.title = [[BHTBundle sharedBundle]
            localizedStringForKey:
                @"LIKES_NAVIGATION_SETTINGS_TITLE"];
        directController = editor;
    } else if ([route isEqualToString:@"sidebarNavigation"]) {
        BHTSidebarNavigationViewController* editor =
            [BHTSidebarNavigationViewController new];
        editor.settingsSearchTargetIdentifier = targetIdentifier;
        editor.title = [[BHTBundle sharedBundle]
            localizedStringForKey:
                @"SIDEBAR_NAVIGATION_SETTINGS_TITLE"];
        directController = editor;
    } else if ([route isEqualToString:@"mediaActionEditor"]) {
        BHTMediaActionEditorViewController* editor =
            [[BHTMediaActionEditorViewController alloc]
                initWithKind:[result[@"mediaKind"] integerValue]
                     account:self.account];
        // A media-kind result opens the editor itself. An action result uses
        // a stable action ID and is focused after the grid appears.
        if (![targetIdentifier isEqualToString:@"photo"] &&
            ![targetIdentifier isEqualToString:@"video"] &&
            ![targetIdentifier isEqualToString:@"gif"]) {
            editor.settingsSearchTargetIdentifier =
                targetIdentifier;
        }
        directController = editor;
    } else if ([route isEqualToString:@"forYouKeywordFilters"]) {
        BHTForYouKeywordFiltersViewController* editor =
            [[BHTForYouKeywordFiltersViewController alloc]
                initWithAccount:self.account];
        editor.settingsSearchTargetIdentifier = targetIdentifier;
        directController = editor;
    }
    if (directController) {
        [self.navigationController pushViewController:directController
                                             animated:YES];
        return;
    }

    NSString* pageKey = result[@"pageKey"];
    UIViewController* controller =
        [self settingsControllerForPageKey:pageKey];
    if (!controller) return;

    BOOL shouldOpenTarget = [result[@"autoOpen"] boolValue];
    if ([controller
            isKindOfClass:ModernSettingsPageViewController.class]) {
        ModernSettingsPageViewController* page =
            (ModernSettingsPageViewController*)controller;
        page.settingsSearchTargetIdentifier = targetIdentifier;
        page.settingsSearchShouldOpenTarget = shouldOpenTarget;
    } else if ([controller
                   isKindOfClass:PresetSettingsViewController.class]) {
        PresetSettingsViewController* themes =
            (PresetSettingsViewController*)controller;
        themes.settingsSearchTargetIdentifier = targetIdentifier;
        themes.settingsSearchShouldOpenTarget = shouldOpenTarget;
    }
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)showLayoutSettings {
    UIViewController* vc = [self settingsControllerForPageKey:@"general"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showAppearanceSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"appearance"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showTimelinesSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"timelines"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showGrokSettings {
    UIViewController* vc = [self settingsControllerForPageKey:@"grok"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showDownloadsSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"media_downloads"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showProfilesSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"profiles"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showTweetsSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"tweets"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showBrandingSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"branding"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showDebugSettings {
    UIViewController* vc =
        [self settingsControllerForPageKey:@"debug"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showSearchSettings {
    UIViewController* vc = [self settingsControllerForPageKey:@"search"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showWebSettings {
    UIViewController* vc = [self settingsControllerForPageKey:@"web"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showBackupSettings {
    UIViewController* vc = [self settingsControllerForPageKey:@"backup"];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)showPresetSettings {
    // Compatibility alias for saved/deep links from the former top-level
    // "Themes & profiles" destination.
    UIViewController* vc = [self settingsControllerForPageKey:@"themes"];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
