void BHTRefreshComposeButtonVisibility(void);
BOOL BHTComposeButtonRequestedHidden(UIView* button, BOOL nativeHidden);
@interface TFNFloatingActionButton : UIView @end
@implementation TFNFloatingActionButton
- (void)setHidden:(BOOL)hidden { [super setHidden:BHTComposeButtonRequestedHidden(self, hidden)]; }
@end
@interface BHTComposeOwnerFixture : NSObject
@property(nonatomic, strong) TFNFloatingActionButton* floatingActionButton;
@end
@implementation BHTComposeOwnerFixture @end
