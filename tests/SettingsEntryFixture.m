@class UIViewController;
@interface UINavigationController : NSObject
@property(nonatomic, copy) NSArray<UIViewController*>* viewControllers;
@end
@implementation UINavigationController @end
@interface UIViewController : NSObject
@property(nonatomic, strong) UINavigationController* navigationController;
@property(nonatomic, weak) UIViewController* parentViewController;
@end
@implementation UIViewController @end
@interface TFNItemsDataViewController : UIViewController @end
@implementation TFNItemsDataViewController @end
@interface T1GenericSettingsViewController : TFNItemsDataViewController @end
@implementation T1GenericSettingsViewController @end
@interface T1SettingsViewController : TFNItemsDataViewController @end
@implementation T1SettingsViewController @end
