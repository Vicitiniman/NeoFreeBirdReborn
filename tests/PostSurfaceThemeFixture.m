NSString* const BHTThemeDidChangeNotification = @"TestSurfaceThemeChanged";
NSString* const BHTThemeColorBackgroundKey = @"background";
static UIColor* BHTTestSurfaceColor;
static BOOL BHTTestSurfaceHostSupported = YES;
static BOOL BHTTestSurfaceSupportedHost(void) { return BHTTestSurfaceHostSupported; }
@interface Palette (BHTSurfaceFixture)
+ (UIColor*)customThemeColorForRole:(NSString*)role;
@end
@implementation Palette (BHTSurfaceFixture)
+ (UIColor*)customThemeColorForRole:(NSString*)role { return BHTTestSurfaceColor; }
@end
void BHTApplyPostSurfaceTheme(UIView* view);
