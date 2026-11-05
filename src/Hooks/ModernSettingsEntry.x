#import "HookHelpers.h"
#import "Settings/BHTSettingsEntry.h"

@interface _TtC9XSettings26SettingsListViewController : UIViewController @end
@interface _TtC14T1TwitterSwift28SettingsChromeViewController : UIViewController @end

%hook _TtC9XSettings26SettingsListViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BHTInstallModernSettingsEntry((UIViewController*)self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    BHTInstallModernSettingsEntry((UIViewController*)self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    BHTLayoutModernSettingsEntry((UIViewController*)self);
}
%end

%hook _TtC14T1TwitterSwift28SettingsChromeViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BHTInstallModernSettingsEntry((UIViewController*)self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    BHTInstallModernSettingsEntry((UIViewController*)self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    BHTLayoutModernSettingsEntry((UIViewController*)self);
}
%end
