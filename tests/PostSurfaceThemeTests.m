@interface BHTRecordingSurface : UIView
@property(nonatomic) NSUInteger colorWrites;
@end
@implementation BHTRecordingSurface
- (void)setBackgroundColor:(UIColor*)color {
    self.colorWrites++;
    [super setBackgroundColor:color];
}
@end

@interface BHTNativeThemedSurface : BHTRecordingSurface @end
@implementation BHTNativeThemedSurface
- (void)setBackgroundColor:(UIColor*)color {
    [super setBackgroundColor:BHTThemedSurfaceBackground(self, color, YES)];
}
@end

static void testPostSurfaceThemePolicy(void) {
    BHTRecordingSurface* root = [[BHTRecordingSurface alloc] initWithFrame:CGRectMake(0, 0, 360, 500)];
    BHTRecordingSurface* highlight = [[BHTRecordingSurface alloc] initWithFrame:root.bounds];
    UIImageView* photo = [[UIImageView alloc] initWithFrame:root.bounds];
    UIView* player = [[UIView alloc] initWithFrame:root.bounds];
    highlight.backgroundColor = UIColor.clearColor;
    [root addSubview:photo];
    [root addSubview:player];
    [root addSubview:highlight]; // Native touch overlay is above the media.
    NSArray* order = root.subviews;
    UIColor* theme = [UIColor new];
    NSUInteger highlightWrites = highlight.colorWrites;
    NSCAssert(BHTApplySurfaceBackingColor(root, theme), @"The known root receives its backing color");
    NSCAssert(root.backgroundColor == theme, @"Root color updates before display");
    NSCAssert(highlight.backgroundColor == UIColor.clearColor && highlight.colorWrites == highlightWrites,
        @"The full-size touch overlay remains transparent");
    NSCAssert(!photo.backgroundColor && !player.backgroundColor, @"Image and player surfaces retain native colors");
    NSCAssert([root.subviews isEqual:order] && CGRectEqualToRect(photo.frame, root.bounds),
        @"Theme application never changes media geometry, visibility or stacking");
    for (NSUInteger pass = 0; pass < 1000; pass++)
        NSCAssert(!BHTApplySurfaceBackingColor(root, theme), @"Repeat refresh is idempotent");
    NSCAssert(root.colorWrites == 1, @"Navigation refreshes do not repeatedly repaint the same backing color");
    NSCAssert(BHTApplySurfaceBackingColor(root, nil) && !root.backgroundColor, @"A native nil background is restorable");
    NSCAssert(!BHTApplySurfaceBackingColor(root, nil), @"An already-clear native root stays unchanged");
    BHTNativeThemedSurface* native = [BHTNativeThemedSurface new];
    UIColor* original = [UIColor new];
    native.backgroundColor = original;
    BHTTestSurfaceColor = theme;
    BHTApplyPostSurfaceTheme(native);
    NSCAssert(native.backgroundColor == theme, @"A newly attached known surface follows the active theme");
    NSUInteger writes = native.colorWrites;
    BHTApplyPostSurfaceTheme(native);
    NSCAssert(native.colorWrites == writes, @"The production state skips unchanged assignments");
    native.backgroundColor = UIColor.clearColor;
    NSCAssert(native.backgroundColor == theme, @"A native refresh resolves the theme before its setter paints");
    BHTTestSurfaceColor = nil;
    BHTApplyPostSurfaceTheme(native);
    NSCAssert(native.backgroundColor == UIColor.clearColor, @"Theme writes never overwrite the latest saved native color");
    native.backgroundColor = nil;
    BHTTestSurfaceColor = theme;
    BHTApplyPostSurfaceTheme(native);
    BHTTestSurfaceColor = nil;
    BHTApplyPostSurfaceTheme(native);
    NSCAssert(!native.backgroundColor, @"A saved native nil is restored through the real hooked-setter path");
    UIView* otherBar = [UIView new];
    BHTTestSurfaceColor = theme;
    NSCAssert(BHTThemedSurfaceBackground(otherBar, original, NO) == original,
        @"Unregistered segmented bars preserve their native appearance");
    BHTApplyPostSurfaceTheme(otherBar);
    NSCAssert(BHTThemedSurfaceBackground(otherBar, original, NO) == theme,
        @"The profile owner can register its own segmented bar without affecting other bars");
    native.window = native;
    UIColor* nextTheme = [UIColor new];
    BHTTestSurfaceColor = nextTheme;
    [NSNotificationCenter.defaultCenter postNotificationName:BHTThemeDidChangeNotification object:nil];
    NSCAssert(native.backgroundColor == nextTheme, @"Visible surfaces respond to an actual theme-change notification");
    BHTTestSurfaceHostSupported = NO;
    NSCAssert(BHTThemedSurfaceBackground(native, original, YES) == original, @"Unsupported hosts remain native");
    BHTTestSurfaceHostSupported = YES;
    BHTTestSurfaceColor = nil;
    NSLog(@"PASS: production surface updates preserve transparent overlays, media colors/geometry/stacking, nil restoration and repeat-refresh stability");
    NSLog(@"PASS: production theme state applies before paint, preserves original/native nil, scopes profile registration and refreshes on theme notification");
}
