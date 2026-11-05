#import <UIKit/UIKit.h>

BOOL BHTSettingsEntryIsContainer(UIViewController* controller);
BOOL BHTSettingsEntryIsRootController(UIViewController* controller);
void BHTInstallModernSettingsEntry(UIViewController* controller);
void BHTLayoutModernSettingsEntry(UIViewController* controller);
void BHTPresentSettingsFromController(UIViewController* controller);
NSDictionary* BHTModernSettingsEntryDiagnosticSnapshot(void);
