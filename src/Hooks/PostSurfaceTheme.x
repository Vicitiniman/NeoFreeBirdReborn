#import "HookHelpers.h"
#import "ThemeColor/BHTPostSurfaceTheme.h"

@interface T1QuotedStandardStatusView : UIView @end
@interface _TtC11TwitterDash21DashHostingController : UIViewController @end

%hook T1QuotedStandardStatusView
- (void)layoutSubviews { %orig; BHTApplyPostSurfaceTheme((UIView*)self, YES); }
%end

%hook T1ConversationFocalStatusView
- (void)layoutSubviews { %orig; BHTApplyPostSurfaceTheme((UIView*)self, YES); }
%end

%hook T1StandardStatusView
- (void)layoutSubviews { %orig; BHTApplyPostSurfaceTheme((UIView*)self, NO); }
%end

%hook T1HostViewController
- (void)viewDidLayoutSubviews { %orig; BHTApplyAppContainerTheme((UIViewController*)self); }
%end

%hook _TtC11TwitterDash21DashHostingController
- (void)viewDidLayoutSubviews { %orig; BHTApplyAppContainerTheme((UIViewController*)self); }
%end
