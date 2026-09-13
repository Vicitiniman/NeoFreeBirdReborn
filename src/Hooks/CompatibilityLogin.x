#import "Login/BHTCompatibilityLogin.h"
#import "Sidebar/BHTSidebarNavigationUtility.h"

// X creates its signed-out onboarding controller asynchronously. Attach the
// opt-in compatibility entry without replacing X's normal sign-in controls.
%group BHTCompatibilityLoginHooks

%hook T1HostViewController

- (void)makeOnboardingViewControllerWithCompletion:
    (void (^)(UIViewController* controller))completion {
    if (!completion) {
        %orig;
        return;
    }

    void (^wrappedCompletion)(UIViewController*) =
        ^(UIViewController* controller) {
            BHTInstallCompatibilitySignInEntry(controller);
            completion(controller);
        };
    %orig(wrappedCompletion);
}

%end

%end

// The signed-in account manager uses a different controller. Its compatibility
// action opens the same dedicated flow with an Add Account handoff context.
%group BHTCompatibilityAddAccountHooks

%hook T1AccountsViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BHTInstallCompatibilityAddAccountSignInEntry(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // Reconcile once more after X finishes configuring its navigation
    // items so a late native update cannot hide the compatibility action.
    BHTInstallCompatibilityAddAccountSignInEntry(self);
    // X also republishes its TwitterDash rows as the account manager settles.
    // Rebuild the registered drawers once, then let the sidebar hook reapply
    // the saved hidden/order configuration after that native transition.
    BHTRecordSidebarAddAccountRefreshRequested();
    [BHTSidebarNavigationUtility
        refreshRegisteredDashContentControllers];
}

%end

%end

%ctor {
    NSString* version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if ([version isEqualToString:@"12.24.1"]) {
        %init(BHTCompatibilityLoginHooks);

        Class accountsController =
            NSClassFromString(@"T1AccountsViewController");
        if (accountsController &&
            [accountsController instancesRespondToSelector:
                @selector(viewWillAppear:)] &&
            [accountsController instancesRespondToSelector:
                @selector(viewDidAppear:)]) {
            %init(BHTCompatibilityAddAccountHooks);
        }
    }
}
