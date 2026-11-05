@class BHTDockTestOwner;
@interface BHTDockTestBar : NSObject
@property(nonatomic, weak) BHTDockTestOwner* owner;
@property(nonatomic) NSInteger selectedIndex;
- (void)_selectTabAtIndex:(NSInteger)index sendControlAction:(BOOL)send;
@end
@interface BHTDockTestOwner : NSObject
@property(nonatomic, copy) NSArray* tabViews;
@property(nonatomic, strong) BHTDockTestBar* tabBar;
@property(nonatomic) NSUInteger taps;
@property(nonatomic) NSUInteger holds;
@property(nonatomic, strong) id source;
- (void)customTabBar:(id)bar selectTabAtIndex:(NSInteger)index withView:(id)view;
- (void)customTabBar:(id)bar longPressOnTabAtIndex:(NSInteger)index withView:(id)view;
@end
@implementation BHTDockTestBar
- (void)_selectTabAtIndex:(NSInteger)index sendControlAction:(BOOL)send {
    self.selectedIndex = index;
    if (send) [self.owner customTabBar:self selectTabAtIndex:index withView:self.owner.tabViews[index]];
}
@end
@implementation BHTDockTestOwner
- (void)customTabBar:(id)bar selectTabAtIndex:(NSInteger)index withView:(id)view {
    NSCAssert(self.tabBar.selectedIndex == index, @"Native selection is updated before its delegate action");
    self.taps++; self.source = view;
}
- (void)customTabBar:(id)bar longPressOnTabAtIndex:(NSInteger)index withView:(id)view { self.holds++; self.source = view; }
@end
static void testGlassDockRouting(void) {
    BHTDockTestOwner* owner = [BHTDockTestOwner new];
    owner.tabBar = [BHTDockTestBar new]; owner.tabBar.owner = owner;
    NSObject* home = [NSObject new]; NSObject* likes = [NSObject new];
    owner.tabViews = @[home, likes];
    NSCAssert(BHTGlassDockCanRoute(owner, NO) && BHTGlassDockRoute(owner, likes, NO), @"Custom buttons call the real native selection entry");
    NSCAssert(owner.tabBar.selectedIndex == 1 && owner.source == likes && owner.taps == 1, @"Likes retains native object identity");
    owner.tabViews = @[likes, home];
    NSCAssert(BHTGlassDockRoute(owner, likes, NO) && owner.tabBar.selectedIndex == 0, @"Reordering uses the current native index");
    BHTGlassDockRoute(owner, home, NO); BHTGlassDockRoute(owner, home, NO);
    NSCAssert(owner.taps == 4, @"A repeated Home tap is forwarded for native scroll-to-top behavior");
    NSCAssert(BHTGlassDockRoute(owner, likes, YES) && owner.holds == 1 && owner.source == likes, @"Long press keeps the native source view");
    owner.tabViews = @[[NSObject new], [NSObject new]];
    NSCAssert(!BHTGlassDockRoute(owner, home, NO) && owner.taps == 4, @"A stale button from another account/snapshot cannot navigate");
    owner.tabBar = nil;
    NSCAssert(!BHTGlassDockCanRoute(owner, NO) && !BHTGlassDockRoute(owner, owner.tabViews[0], NO), @"Missing native selection capability leaves the stock bar available");
    NSCAssert(!BHTGlassDockCanRoute([NSObject new], NO), @"An unknown owner fails closed");
    NSLog(@"PASS: dock native selection state, current order, repeat taps, long press, stale/account replacement and capability fallback");
}
