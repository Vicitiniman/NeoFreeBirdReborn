#import <UIKit/UIKit.h>

@interface BHTGlassDockView : UIVisualEffectView
@property(nonatomic, readonly) NSUInteger selectionUpdates;
@property(nonatomic, readonly) NSUInteger buttonCount;
@property(nonatomic, readonly, getter=isCollapsed) BOOL collapsed;
@property(nonatomic, copy) void (^expansionHandler)(void);
- (void)presentExpandedFrame:(CGRect)frame collapsed:(BOOL)collapsed rightToLeft:(BOOL)rightToLeft animated:(BOOL)animated;
- (void)updateTabs:(NSArray<UIView*>*)tabs owner:(UIViewController*)owner vertical:(BOOL)vertical
        showLabels:(BOOL)labels textColor:(UIColor*)text accent:(UIColor*)accent;
@end
