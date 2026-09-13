//
//  Profile.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import "Likes/BHTLikesTab.h"

static char kBHTProfilePhotosFirstKey;

static NSArray* BHTProfileMainEntriesWithPhotosFirst(NSArray* groups,
                                                    id photoEntry,
                                                    id videoEntry) {
    if (![groups isKindOfClass:NSArray.class] || !photoEntry || !videoEntry) return groups;
    for (NSUInteger index = 0; index < groups.count; index++) {
        id group = groups[index];
        if (![group isKindOfClass:NSArray.class]) continue;
        NSUInteger photoIndex = [group indexOfObjectIdenticalTo:photoEntry];
        NSUInteger videoIndex = [group indexOfObjectIdenticalTo:videoEntry];
        if (photoIndex == NSNotFound || videoIndex == NSNotFound || photoIndex == 0) continue;
        NSMutableArray* mediaGroup = [group mutableCopy];
        [mediaGroup removeObjectAtIndex:photoIndex];
        [mediaGroup insertObject:photoEntry atIndex:0];
        NSMutableArray* result = [groups mutableCopy];
        result[index] = [mediaGroup copy];
        return [result copy];
    }
    return groups;
}

// Keep the profile's native Photos/Videos tabs and account-scoped feeds.
// Only their presentation is wrapped; the native provider still decides
// whether media is accessible and performs authenticated cursor loading.
%hook T1ProfileDisplayNormalMainContentProvider

- (NSArray*)contentMainEntries {
    NSArray* groups = %orig;
    // X selects inner index zero by default. Keep this order stable for the
    // life of the provider so a settings change cannot reinterpret an active
    // Videos selection as Photos. New profiles pick up the current setting.
    NSNumber* photosFirst = objc_getAssociatedObject(self, &kBHTProfilePhotosFirstKey);
    if (!photosFirst) {
        photosFirst = @([BHTSettings boolForKey:@"profile_media_default_photos"]);
        objc_setAssociatedObject(self, &kBHTProfilePhotosFirstKey, photosFirst,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SEL photos = NSSelectorFromString(@"photoEntry");
    SEL videos = NSSelectorFromString(@"videoEntry");
    if (!photosFirst.boolValue || ![(id)self respondsToSelector:photos] ||
        ![(id)self respondsToSelector:videos]) return groups;
    id photoEntry = ((id (*)(id, SEL))objc_msgSend)(self, photos);
    id videoEntry = ((id (*)(id, SEL))objc_msgSend)(self, videos);
    return BHTProfileMainEntriesWithPhotosFirst(groups, photoEntry, videoEntry);
}

- (UIViewController*)_generatePhotoViewController {
    UIViewController* nativeController = %orig;
    return BHTProfileMediaController(nativeController, @"photos");
}

- (UIViewController*)_generateVideoViewController {
    UIViewController* nativeController = %orig;
    return BHTProfileMediaController(nativeController, @"videos");
}

%end

// MARK: - Copy profile info

static char kCopyProviderKey;

@interface ProfileCopyButtonProvider : NSObject
@property (nonatomic, weak) T1ProfileHeaderViewController* headerViewController;
@property (nonatomic, weak) id delegate;
@property (nonatomic, strong) TFNButton* infoButton;
@end

@implementation ProfileCopyButtonProvider

- (NSArray<UIMenuElement*>*)copyActions {
    T1ProfileUserViewModel* viewModel = self.headerViewController.viewModel;

    UIAction* (^copyAction)(NSString*, NSString*, NSString*) =
        ^(NSString* titleKey, NSString* iconName, NSString* value) {
            UIAction* action =
                [UIAction actionWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:titleKey]
                                    image:[UIImage tfn_vectorImageNamed:iconName
                                                               fitsSize:CGSizeMake(16.0, 16.0)
                                                              fillColor:UIColor.labelColor]
                               identifier:nil
                                  handler:^(__kindof UIAction* act) {
                                      if (value.length) {
                                          UIPasteboard.generalPasteboard.string = value;
                                      }
                                  }];
            if (!value.length) {
                action.attributes = UIMenuElementAttributesDisabled;
            }
            return action;
        };

    return @[
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_3", @"account", viewModel.fullName),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_2", @"at", viewModel.username),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_1", @"news_stroke", viewModel.bio),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_5", @"location_stroke", viewModel.location),
        copyAction(@"COPY_PROFILE_INFO_MENU_OPTION_4", @"link", viewModel.url),
    ];
}

- (TFNButton*)buttonView {
    if (!self.infoButton) {
        // Style 2 in size class 2 is the bordered round icon style the other
        // header buttons use.
        TFNButton* button = [%c(TFNButton) buttonWithTitle:nil
                                                    imageNamed:@"copy_stroke"
                                                         style:2
                                                     sizeClass:2];
        button.accessibilityLabel =
            [[BHTBundle sharedBundle] localizedStringForKey:@"COPY_PROFILE_INFO_TITLE"];
        button.showsMenuAsPrimaryAction = YES;

        // Deferred so each open rebuilds the actions with the loaded profile
        // data and the current theme's icon color.
        __weak ProfileCopyButtonProvider* weakSelf = self;
        void (^actionsProvider)(void (^)(NSArray<UIMenuElement*>*)) =
            ^(void (^completion)(NSArray<UIMenuElement*>*)) {
                completion([weakSelf copyActions] ?: @[]);
            };
        UIDeferredMenuElement* deferredActions;
        if (@available(iOS 15.0, *)) {
            deferredActions = [UIDeferredMenuElement elementWithUncachedProvider:actionsProvider];
        } else {
            deferredActions = [UIDeferredMenuElement elementWithProvider:actionsProvider];
        }
        button.menu = [UIMenu menuWithTitle:@"" children:@[deferredActions]];

        self.infoButton = button;
    }
    return self.infoButton;
}

- (NSArray*)buttonSpecs {
    // Native positions run from 2 (follow) to 10 (mute), so 100 lands at the
    // far end; priority 1 lets every native button win the width fight.
    __weak ProfileCopyButtonProvider* weakSelf = self;
    T1ProfileActionButtonSpec* spec = [[%c(T1ProfileActionButtonSpec) alloc] initWithPosition:100
        priority:1
        visibilityBlock:^BOOL(double availableWidth) {
            return YES;
        }
        buttonCreationBlock:^UIView* {
            return [weakSelf buttonView];
        }];
    return spec ? @[spec] : @[];
}

@end

%group BHTLegacyProfileActionProviders

%hook T1ProfileHeaderViewController

- (NSArray*)actionButtonProviders {
    NSArray* providers = %orig;

    if (![BHTSettings boolForKey:@"copy_profile_info"]) {
        return providers;
    }

    ProfileCopyButtonProvider* copyProvider = objc_getAssociatedObject(self, &kCopyProviderKey);
    if (!copyProvider) {
        copyProvider = [ProfileCopyButtonProvider new];
        copyProvider.headerViewController = self;
        objc_setAssociatedObject(self, &kCopyProviderKey, copyProvider,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return [providers arrayByAddingObject:copyProvider];
}

%end

%end

// MARK: - Native profile bio translation

// X 12.9 exposes this selector. Let X render and perform its own translation;
// no credentials or out-of-process requests are involved. Do not add the older
// isProfileTranslationEnabled selector to builds where it is absent, because a
// disabled preference would have no native implementation to call through to.
%hook TFNTwitterCanonicalUser

- (BOOL)isProfileBioTranslatable {
    return [BHTSettings boolForKey:@"enable_grok_translations"] ? YES : %orig;
}

%end

// MARK: - Hide premium offer

%hook T1ProfileSummaryView

- (BOOL)shouldShowGetVerifiedButton {
    return [BHTSettings boolForKey:@"hide_premium_offer"] ? NO : %orig;
}

%end

// MARK: - Show unrounded follower/following counts

%hook T1ProfileFriendsFollowingViewModel

- (id)_t1_followCountTextWithLabel:(__unsafe_unretained id)label
                     singularLabel:(__unsafe_unretained id)singularLabel
                             count:(NSNumber*)count
                       highlighted:(BOOL)highlighted {
    id original = %orig;

    if (![BHTSettings boolForKey:@"full_profile_counts"]) {
        return original;
    }

    if (![count isKindOfClass:[NSNumber class]] ||
        ![original isKindOfClass:[NSAttributedString class]]) {
        return original;
    }

    NSString* abbreviated = [count tfs_twitterAbbreviated];
    NSNumberFormatter* formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    NSString* fullCount = [formatter stringFromNumber:count];

    if (!abbreviated.length || !fullCount.length || [abbreviated isEqualToString:fullCount]) {
        return original;
    }

    NSRange range = [[original string] rangeOfString:abbreviated];
    if (range.location == NSNotFound) {
        return original;
    }

    NSMutableAttributedString* expanded = [original mutableCopy];
    [expanded replaceCharactersInRange:range withString:fullCount];
    return [expanded copy];
}

%end

// Older profile layouts expose this provider list. Do not create a replacement
// method with no native implementation on the current catalog-based header.
%ctor {
    %init;
    Class header = NSClassFromString(@"T1ProfileHeaderViewController");
    if (class_getInstanceMethod(header, @selector(actionButtonProviders))) {
        %init(BHTLegacyProfileActionProviders);
    }
}
