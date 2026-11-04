//
//  HideUI.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Hide Blue verified checkmark

// The author-row badge (SimpleBadgeable.init(statusViewModel:)) builds from the
// merged verified flag plus identityType and ignores isBlueVerified, so both
// getters must be silenced; brand/government badges survive via identityType.
// TFNTwitterUser and TFNTwitterCanonicalUser forward here and need no hooks.

%hook TFSTwitterUser

- (id)isBlueVerified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? nil : %orig;
}

- (BOOL)verified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? NO : %orig;
}

%end

static char BHTAuxiliaryChromeOriginalStateKey;

static void BHTSetAuxiliaryControllerHidden(UIViewController* controller, BOOL hidden) {
    if (!controller.isViewLoaded) return;
    UIView* view = controller.view;
    NSDictionary* original = objc_getAssociatedObject(view, &BHTAuxiliaryChromeOriginalStateKey);
    if (hidden && !original) {
        original = @{@"hidden": @(view.hidden), @"interactive": @(view.userInteractionEnabled)};
        objc_setAssociatedObject(view, &BHTAuxiliaryChromeOriginalStateKey, original,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (hidden) {
        view.hidden = YES;
        view.userInteractionEnabled = NO;
    } else if (original) {
        view.hidden = [original[@"hidden"] boolValue];
        view.userInteractionEnabled = [original[@"interactive"] boolValue];
        objc_setAssociatedObject(view, &BHTAuxiliaryChromeOriginalStateKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// The old concrete TrendsSidebarViewController is gone. SwiftUI hosting
// subclasses may only be registered at runtime, so discover dedicated trend
// sidebar children in the navigation owner's bounded controller tree. Never
// hide a whole content/search column based on its position or visible text.
static void BHTUpdateAuxiliaryControllers(UIViewController* owner,
                                           NSUInteger depth, NSUInteger* budget) {
    if (depth > 6 || *budget == 0) return;
    (*budget)--;
    NSString* name = NSStringFromClass(owner.class);
    BOOL dedicatedTrends =
        [name rangeOfString:@"TrendsSidebar" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [name rangeOfString:@"TrendSidebar" options:NSCaseInsensitiveSearch].location != NSNotFound;
    if (dedicatedTrends) {
        BHTSetAuxiliaryControllerHidden(owner, [BHTSettings boolForKey:@"hide_trends"]);
    }
    for (UIViewController* child in owner.childViewControllers) {
        BHTUpdateAuxiliaryControllers(child, depth + 1, budget);
        if (*budget == 0) break;
    }
}

static void BHTUpdateIPadAuxiliaryChrome(UIViewController* owner) {
    if (UI_USER_INTERFACE_IDIOM() != UIUserInterfaceIdiomPad) return;
    NSUInteger budget = 64;
    BHTUpdateAuxiliaryControllers(owner, 0, &budget);
}

%hook T1TabbedAppNavigationViewController
- (void)viewDidLayoutSubviews {
    %orig;
    BHTUpdateIPadAuxiliaryChrome((UIViewController*)self);
}
%end

%hook _TtC14T1TwitterSwift34XTabbedAppNavigationViewController
- (void)viewDidLayoutSubviews {
    %orig;
    BHTUpdateIPadAuxiliaryChrome((UIViewController*)self);
}
%end

%hook T1UserRecommendationsViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        BHTSetAuxiliaryControllerHidden((UIViewController*)self,
                                        [BHTSettings boolForKey:@"hide_who_to_follow"]);
    }
}

%end

// Reaches into the wrapped user's storage directly instead of through its
// getter.
%hook TFSTwitterUserSource

- (id)isBlueVerified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? nil : %orig;
}

- (BOOL)verified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? NO : %orig;
}

%end

%hook TFSTwitterTypeaheadUser

- (id)isBlueVerified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? nil : %orig;
}

- (BOOL)verified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? NO : %orig;
}

%end

// XChat replaced TFSDirectMessageUser. Its sender adapter still supplies the
// two verified getters used by the new conversation UI.
%hook _TtC14T1TwitterSwift27XChatSenderCardSourceObject

- (id)isBlueVerified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? nil : %orig;
}

- (BOOL)verified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? NO : %orig;
}

%end

// Status view models cache these flags at init, beyond the user model hooks;
// the author row badge reads isFromUserVerified, and other view models forward
// here.
%hook T1TwitterCoreStatusViewModelAdapter

- (BOOL)isFromUserBlueVerified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? NO : %orig;
}

- (BOOL)isFromUserVerified {
    return [BHTSettings boolForKey:@"hide_blue_verified"] ? NO : %orig;
}

%end

// MARK: - No search history

// Every recent-search write funnels through _tse_setRecentSearch: and every
// read through recentSearches; the separate saved-searches feature stays
// untouched.

%hook TTSRecentSearchesDatastore

- (void)_tse_setRecentSearch:(__unsafe_unretained id)item {
    if (![BHTSettings boolForKey:@"no_history"]) {
        %orig;
    }
}

- (NSArray*)recentSearches {
    return [BHTSettings boolForKey:@"no_history"] ? @[] : %orig;
}

%end

// MARK: - Hide trending content on the Explore tab

// Trending content lives in the child URT chrome view controller, whose
// property has no ObjC getter in 12.3, so find it among the children. The page
// tab strip arrives separately through tfn_navigationBarAccessoryView.

%hook _TtC14T1TwitterSwift28GuideContainerViewController

- (void)viewDidLoad {
    %orig;

    if ([BHTSettings boolForKey:@"hide_trends"]) {
        for (UIViewController* child in
             [(UIViewController*)self childViewControllers]) {
            if ([child isKindOfClass:
                           %c(_TtC14T1TwitterSwift23URTChromeViewController)]) {
                child.view.hidden = YES;
            }
        }
    }
}

- (UIView*)tfn_navigationBarAccessoryView {
    return [BHTSettings boolForKey:@"hide_trends"] ? nil : %orig;
}

%end

// MARK: - No Subscribe button

// Every Subscribe surface — the profile button provider (and its answers that
// demote or hide the Follow button) and the tweet author row — shows only when
// the relationship's eligible state is 1, so reporting "not eligible" (2) is
// enough to keep the plain Follow button everywhere. Relationships that are
// actively super-following stay genuine, so a real subscription keeps its
// Subscribed button and subscriber timeline.

%hook TFSTwitterRelationship

- (NSInteger)superFollowEligibleState {
    if ([BHTSettings boolForKey:@"restore_follow_button"] &&
        self.superFollowingState != 1) {
        return 2;
    }
    return %orig;
}

%end

// MARK: - Hide Follow button on Tweets

// The conversation focal tweet and the immersive player both render their
// author row through TTAStatusAuthorView, so forcing the flag here covers every
// surface.

%hook TTAStatusAuthorView

- (void)setFollowControlHidden:(BOOL)hidden {
    %orig([BHTSettings boolForKey:@"hide_follow_button"] ? YES : hidden);
}

%end

// MARK: - Hide inline action buttons

%hook TTAStatusInlineActionsView

+ (NSArray*)_t1_inlineActionViewClassesForViewModel:(id)arg1
                                            options:(NSUInteger)arg2
                                        displayType:(NSUInteger)arg3
                                            account:(id)arg4 {
    NSArray* origClasses = %orig;
    if (![origClasses isKindOfClass:NSArray.class]) {
        return origClasses;
    }

    NSMutableArray* newClasses = [origClasses mutableCopy];

    Class analyticsButtonClass = %c(TTAStatusInlineAnalyticsButton);
    if (analyticsButtonClass && [BHTSettings boolForKey:@"hide_view_count"]) {
        [newClasses removeObject:analyticsButtonClass];
    }

    Class bookmarkButtonClass = %c(TTAStatusInlineBookmarkButton);
    if (bookmarkButtonClass && [BHTSettings boolForKey:@"hide_bookmark_button"]) {
        [newClasses removeObject:bookmarkButtonClass];
    }

    Class downvoteButtonClass = %c(TTAStatusInlineDownvoteButton);
    if (downvoteButtonClass && [BHTSettings boolForKey:@"hide_downvote_button"]) {
        [newClasses removeObject:downvoteButtonClass];
    }

    return [newClasses copy];
}

%end
