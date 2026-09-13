#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Reports whether the guarded X 12.24.1 compatibility password flow can run.
// Credentials exist only in the temporary compatibility controller and are
// cleared before the private X command starts; they are never persisted.
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

// Aggregate stages, counters, and fixed capability identifiers only.
// Credentials, tokens, URLs, response bodies, account identifiers, and raw
// errors are never included.
NSDictionary<NSString*, id>*
BHTCompatibilitySignInDiagnosticSnapshot(void);

NS_ASSUME_NONNULL_END
