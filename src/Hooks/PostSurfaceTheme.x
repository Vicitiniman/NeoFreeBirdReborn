#import "HookHelpers.h"
#import "ThemeColor/BHTPostSurfaceTheme.h"

@interface T1QuotedStandardStatusView : UIView @end
@interface _TtC11TwitterDash21DashHostingController : UIViewController @end
@interface _TtC10TFNUISwift25LegacySegmentedTabBarView : UIView @end

%hook T1QuotedStandardStatusView
- (void)setBackgroundColor:(UIColor*)color {
    %orig(BHTThemedSurfaceBackground((UIView*)self, color, YES));
}
- (void)didMoveToWindow {
    %orig;
    BHTApplyPostSurfaceTheme((UIView*)self);
}
%end

%hook T1ConversationFocalStatusView
- (void)setBackgroundColor:(UIColor*)color {
    %orig(BHTThemedSurfaceBackground((UIView*)self, color, YES));
}
- (void)didMoveToWindow {
    %orig;
    BHTApplyPostSurfaceTheme((UIView*)self);
}
%end

%hook T1ProfileHeaderView
- (void)setBackgroundColor:(UIColor*)color {
    %orig(BHTThemedSurfaceBackground((UIView*)self, color, YES));
}
- (void)didMoveToWindow {
    %orig;
    BHTApplyPostSurfaceTheme((UIView*)self);
}
%end

%hook T1ProfileSummaryView
- (void)setBackgroundColor:(UIColor*)color {
    %orig(BHTThemedSurfaceBackground((UIView*)self, color, YES));
}
- (void)didMoveToWindow {
    %orig;
    BHTApplyPostSurfaceTheme((UIView*)self);
}
%end

%hook T1ProfileUserInfoView
- (void)setBackgroundColor:(UIColor*)color {
    %orig(BHTThemedSurfaceBackground((UIView*)self, color, YES));
}
- (void)didMoveToWindow {
    %orig;
    BHTApplyPostSurfaceTheme((UIView*)self);
}
%end

%hook _TtC10TFNUISwift25LegacySegmentedTabBarView
- (void)setBackgroundColor:(UIColor*)color {
    // Only the instance registered by the profile owner receives a fill.
    %orig(BHTThemedSurfaceBackground((UIView*)self, color, NO));
}
%end

%hook T1ProfileViewController
- (void)viewDidLoad {
    %orig;
    BHTApplyProfileContainerTheme((UIViewController*)self);
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BHTApplyProfileContainerTheme((UIViewController*)self);
}
%end

%hook T1ProfileHeaderViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if ([(UIViewController*)self isViewLoaded]) BHTApplyPostSurfaceTheme([(UIViewController*)self view]);
}
%end

%hook T1ProfileUserInfoViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if ([(UIViewController*)self isViewLoaded]) BHTApplyPostSurfaceTheme([(UIViewController*)self view]);
}
%end

%hook T1ProfileFollowStatsViewController
- (void)viewDidLoad {
    %orig;
    BHTApplyProfileStatsTheme((UIViewController*)self);
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BHTApplyProfileStatsTheme((UIViewController*)self);
}
%end

%hook T1ProfileFriendsFollowingViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BHTApplyProfileStatsTheme((UIViewController*)self);
}
%end

%hook T1ProfileActionButtonsSubheaderViewController
- (void)viewDidLoad {
    %orig;
    BHTApplyAppContainerTheme((UIViewController*)self);
}
%end

%hook T1HostViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BHTApplyAppContainerTheme((UIViewController*)self);
}
%end

%hook _TtC11TwitterDash21DashHostingController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BHTApplyAppContainerTheme((UIViewController*)self);
}
%end
