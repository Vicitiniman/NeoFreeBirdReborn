static void testPostSurfaceThemePolicy(void) {
    CGRect bounds = CGRectMake(0, 0, 360, 500);
    NSCAssert(BHTPostSurfaceIsBackground(@"UIView", bounds, bounds), @"A direct leaf background may follow the theme");
    NSCAssert(BHTPostSurfaceIsBackground(@"TFNSolidColorView", bounds, bounds), @"Composable solid backgrounds need their own color setter");
    NSCAssert(BHTPostSurfaceIsBackground(@"TFNTappableHighlightView", bounds, bounds), @"The quote's unpressed background follows the theme");
    NSCAssert(!BHTPostSurfaceIsBackground(@"UIImageView", bounds, bounds), @"Photos remain untouched");
    NSCAssert(!BHTPostSurfaceIsBackground(@"T1PlayerView", bounds, bounds), @"Video surfaces remain untouched");
    NSCAssert(!BHTPostSurfaceIsBackground(@"UILabel", bounds, bounds), @"Text views do not become background planes");
    NSCAssert(!BHTPostSurfaceIsBackground(@"UIView", CGRectMake(0, 300, 360, 200), bounds), @"Partial media/content regions are excluded");
    NSCAssert(!BHTPostSurfaceIsBackground(@"UIView", bounds, CGRectZero), @"Unlaid-out posts wait for native geometry");
    NSLog(@"PASS: post background plane scope, quote/focal geometry and image/video/text isolation");
}
