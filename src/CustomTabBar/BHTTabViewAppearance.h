#import <UIKit/UIKit.h>

// X 12.40's T1TabView has a title string but no titleLabel or title refresh
// method. Keep our label separate from the host's icon and badge internals.
void BHTSetTabViewTitleOverride(UIView* tabView, NSString* title);
void BHTRefreshTabViewAppearance(UIView* tabView);
void BHTPrepareTabViewLayout(UIView* tabView);
void BHTLayoutTabViewAppearance(UIView* tabView);
