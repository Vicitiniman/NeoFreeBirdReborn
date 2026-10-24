#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

// Reports whether the user-confirmed X 12.24.1 web-session bridge can run.
// X owns the visible password form; NeoFreeBird never receives the password.
BOOL BHTCompatibilitySignInIsAvailable(void);
void BHTPresentCompatibilitySignIn(
    UIViewController* _Nullable presenter);
void BHTPresentCompatibilitySignInForAddingAccount(
    UIViewController* _Nullable accountsController);

// Adds the dedicated compatibility sign-in and privacy-safe report actions to
// X's signed-out onboarding surface. X's normal sign-in remains unchanged.
void BHTInstallCompatibilitySignInEntry(
    UIViewController* _Nullable onboardingController);

// Adds the dedicated compatibility action to X's signed-in account manager.
// Successful accounts are registered and switched through X's account APIs.
void BHTInstallCompatibilityAddAccountSignInEntry(
    UIViewController* _Nullable accountsController);

typedef void (^BHTCompatibilityWebSessionAccountCompletion)(
    BOOL success,
    NSString* _Nullable failureCategory);

// Narrow account-shell handoff used by the secure web-session bridge. The
// shell receives fixed non-secret placeholders; web session values never enter
// X's native credential persistence.
BOOL BHTCompatibilityWebSessionAccountRuntimeIsAvailable(void);
BOOL BHTCompatibilityInstallWebSessionAccount(
    NSString* screenName,
    uint64_t userID,
    UIViewController* flowController,
    UIViewController* _Nullable addAccountController,
    BHTCompatibilityWebSessionAccountCompletion _Nullable completion);
BOOL BHTCompatibilityRemoveWebSessionAccount(NSString* screenName);
BOOL BHTCompatibilityRemoveWebSessionAccountWithUserID(uint64_t userID);
BOOL BHTCompatibilityRestoreWebSessionAccount(NSString* screenName, uint64_t userID);
void BHTShareCompatibilitySignInReport(UIViewController* presenter, id _Nullable sender);

// Aggregate stages, counters, and fixed capability identifiers only.
// Credentials, tokens, URLs, response bodies, account identifiers, and raw
// errors are never included.
NSDictionary<NSString*, id>*
BHTCompatibilitySignInDiagnosticSnapshot(void);

NS_ASSUME_NONNULL_END
