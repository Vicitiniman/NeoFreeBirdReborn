#import "Login/BHTCompatibilityLogin.h"
#import "Sidebar/BHTSidebarNavigationUtility.h"
#import "Login/BHTSecureWebSession.h"
#import "Login/BHTWebSessionSecurity.h"
#import <objc/runtime.h>

// Use the working web sign-in as the primary entry on the audited build,
// retaining native onboarding when the bridge is unavailable.
%group BHTCompatibilityLoginHooks

%hook T1HostViewController

- (void)makeOnboardingViewControllerWithCompletion:
    (void (^)(UIViewController* controller))completion {
    if (!completion) {
        %orig;
        return;
    }

    UIViewController* primary = BHTSecureWebSessionOnboardingController();
    if (primary) { completion(primary); return; }

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

%group BHTCompatibilityPrimaryAddAccountHook
%hook T1AccountsViewController
- (void)private_startLoginFlowWithSender:(id)sender {
    if (BHTSecureWebSessionSignInIsAvailable()) {
        BHTPresentCompatibilitySignInForAddingAccount(self); return;
    }
    %orig;
}
%end
%end

%group BHTCompatibilityAccountSelectionHook
%hook T1HostViewController
- (void)viewAccount:(id)account animated:(BOOL)animated {
    %orig;
    BHTSecureWebSessionDidSelectAccount(account);
}
%end
%end

%group BHTCompatibilityAccountRemovalHook
%hook T1AccountController
- (void)removeAccount:(id)account withAccountRemovalCompletionHandler:(id)completion {
    // This is X's explicit account-removal command, not its account-state
    // checks or network-error callbacks. Removed accounts must stay removed.
    BHTSecureWebSessionForgetAccount(account);
    %orig;
}
%end
%end

%group BHTCompatibilityLegacyMarkerHook
%hook TFNTwitterAccount
- (id)oAuthToken {
    id token = %orig;
    // Upgrade old saved account shells before their very first boot-time
    // request is built. Resolve from the account's own numeric ID, never
    // from whichever session happens to be selected in the UI.
    if ([token isKindOfClass:NSString.class] && [token isEqualToString:@"neofreebird_web_session"]) {
        NSString* marker = BHTWebSessionAccountMarker(BHTWebSessionNativeAccountUserID(self));
        if (marker.length) return marker;
    }
    return token;
}
%end
%end

%ctor {
    NSString* version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if ([version isEqualToString:@"12.24.1"]) {
        %init(BHTCompatibilityLoginHooks);
        if (class_getInstanceMethod(NSClassFromString(@"TFNTwitterAccount"), @selector(oAuthToken))) {
            %init(BHTCompatibilityLegacyMarkerHook);
        }
        Class host = NSClassFromString(@"T1HostViewController");
        if (class_getInstanceMethod(host, @selector(viewAccount:animated:))) {
            %init(BHTCompatibilityAccountSelectionHook);
        }
        Class removal = NSClassFromString(@"T1AccountController");
        if (class_getInstanceMethod(removal, @selector(removeAccount:withAccountRemovalCompletionHandler:))) {
            %init(BHTCompatibilityAccountRemovalHook);
        }

        Class accountsController =
            NSClassFromString(@"T1AccountsViewController");
        if (accountsController &&
            [accountsController instancesRespondToSelector:
                @selector(viewWillAppear:)] &&
            [accountsController instancesRespondToSelector:
                @selector(viewDidAppear:)]) {
            %init(BHTCompatibilityAddAccountHooks);
        }
        if (class_getInstanceMethod(accountsController, @selector(private_startLoginFlowWithSender:))) {
            %init(BHTCompatibilityPrimaryAddAccountHook);
        }
    }
}
