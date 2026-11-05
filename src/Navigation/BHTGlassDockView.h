#import <UIKit/UIKit.h>

@interface BHTGlassDockView : UIVisualEffectView
@property(nonatomic, readonly) NSUInteger selectionUpdates;
@property(nonatomic, readonly) NSUInteger buttonCount;
- (void)updateTabs:(NSArray<UIView*>*)tabs owner:(UIViewController*)owner vertical:(BOOL)vertical
        showLabels:(BOOL)labels textColor:(UIColor*)text accent:(UIColor*)accent;
@end
