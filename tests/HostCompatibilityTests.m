@interface BHTAccountRemovalFixture : NSObject
- (void)removeAccount:(id)account source:(NSInteger)source withAccountRemovalCompletionHandler:(void (^)(void))completion;
- (void)legacyRemoveAccount:(id)account withAccountRemovalCompletionHandler:(id)completion;
- (void)wrongRemoveAccount:(id)account source:(id)source withAccountRemovalCompletionHandler:(id)completion;
@end
@implementation BHTAccountRemovalFixture
- (void)removeAccount:(id)account source:(NSInteger)source withAccountRemovalCompletionHandler:(void (^)(void))completion {}
- (void)legacyRemoveAccount:(id)account withAccountRemovalCompletionHandler:(id)completion {}
- (void)wrongRemoveAccount:(id)account source:(id)source withAccountRemovalCompletionHandler:(id)completion {}
@end

static void testHostCompatibility(void) {
    NSCAssert(BHTHostVersionIsSupported(@"12.40.1", @"1"), @"The audited host build is supported");
    NSCAssert(!BHTHostVersionIsSupported(@"12.40.1", @"2"), @"An unverified same-version build is rejected");
    NSCAssert(!BHTHostVersionIsSupported(@"12.24.1", @"1"), @"Older private layouts do not inherit the new port");
    NSCAssert(!BHTHostVersionIsSupported(@"12.41", @"1"), @"Future host versions fail closed");
    NSCAssert(!BHTHostVersionIsSupported(nil, @"1"), @"Malformed bundle metadata fails closed");
    Class cls = BHTAccountRemovalFixture.class;
    NSCAssert(BHTAccountRemovalMethodIsSupported(class_getInstanceMethod(cls,
                  @selector(removeAccount:source:withAccountRemovalCompletionHandler:))),
              @"Current logout takes account, integer source and completion block");
    NSCAssert(!BHTAccountRemovalMethodIsSupported(class_getInstanceMethod(cls,
                  @selector(legacyRemoveAccount:withAccountRemovalCompletionHandler:))),
              @"The old logout ABI is rejected");
    NSCAssert(!BHTAccountRemovalMethodIsSupported(class_getInstanceMethod(cls,
                  @selector(wrongRemoveAccount:source:withAccountRemovalCompletionHandler:))),
              @"An object source argument is not an NSInteger");
    NSCAssert(!BHTAccountRemovalMethodIsSupported(NULL), @"A missing method is never hooked");
}
