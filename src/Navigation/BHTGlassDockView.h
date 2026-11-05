#import <UIKit/UIKit.h>

@interface BHTGlassDockView : UIVisualEffectView
@property(nonatomic, readonly) NSUInteger selectionUpdates;
@property(nonatomic, readonly) NSUInteger buttonCount;
@property(nonatomic, readonly, getter=isCollapsed) BOOL collapsed;
@property(nonatomic, copy) void (^expansionHandler)(void);
// Keep the reusable target even when the clear endpoint renders effect=nil.
@property(nonatomic, strong) UIVisualEffect* materialEffect;
@property(nonatomic, readonly) CGFloat materialFraction;
@property(nonatomic, readonly) CGFloat tintFraction;
- (void)setGlassOpacity:(CGFloat)opacity surfaceColor:(UIColor*)color;
- (void)presentExpandedFrame:(CGRect)frame collapsed:(BOOL)collapsed rightToLeft:(BOOL)rightToLeft animated:(BOOL)animated;
- (void)updateTabs:(NSArray<UIView*>*)tabs owner:(UIViewController*)owner vertical:(BOOL)vertical
        showLabels:(BOOL)labels textColor:(UIColor*)text accent:(UIColor*)accent;
@end
