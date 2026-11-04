//
//  ImmersivePlayer.x
//  NeoFreeBird
//

#import "HookHelpers.h"

// MARK: - Immersive Player Timestamp

// Resolve declaration indexes by their reflected names. X 12.40 removed a
// field and added three more; an offset vector cannot fix a wrong ordinal.
static BOOL cardStateFieldIndex(const uint8_t* descriptor,
                                const char* fieldName,
                                uint32_t* result) {
    int32_t relative = *(const int32_t*)(descriptor + 16);
    if (!relative) return NO;
    const uint8_t* fields = descriptor + 16 + relative;
    uint16_t recordSize = *(const uint16_t*)(fields + 10);
    uint32_t count = *(const uint32_t*)(fields + 12);
    if (recordSize < 12 || recordSize > 64 || count == 0 || count > 128 ||
        count != *(const uint32_t*)(descriptor + 20)) return NO;
    for (uint32_t index = 0; index < count; index++) {
        const uint8_t* nameField = fields + 16 + index * recordSize + 8;
        int32_t nameOffset = *(const int32_t*)nameField;
        if (nameOffset && strncmp((const char*)nameField + nameOffset, fieldName, 64) == 0) {
            *result = index;
            return YES;
        }
    }
    return NO;
}

static const uint8_t* immersiveCardStateMetadata(void) {
    static const uint8_t* metadata;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const void* (*getType)(const char*, size_t, const void*,
                               const void* const*) =
            dlsym(RTLD_DEFAULT, "swift_getTypeByMangledNameInEnvironment");
        if (getType) {
            const char* mangledName = "14T1TwitterSwift18ImmersiveCardStateV";
            metadata = getType(mangledName, strlen(mangledName), NULL, NULL);
        }
    });
    return metadata;
}

// Reads a Bool field through the struct's field offset vector, the same way the
// app's own compiled accesses do, so byte offsets never have to be hardcoded.
static BOOL cardStateBoolField(const uint8_t* state,
                               const char* fieldName,
                               BOOL* outValue) {
    const uint8_t* metadata = immersiveCardStateMetadata();
    if (!metadata) {
        return NO;
    }

    const uint8_t* descriptor = *(const uint8_t* const*)(metadata + 8);
    uint32_t fieldIndex = 0;
    if (!cardStateFieldIndex(descriptor, fieldName, &fieldIndex)) return NO;
    uint32_t numFields = *(const uint32_t*)(descriptor + 20);
    uint32_t offsetVectorOffset = *(const uint32_t*)(descriptor + 24);
    if (fieldIndex >= numFields || offsetVectorOffset == 0) {
        return NO;
    }

    const int32_t* fieldOffsets =
        (const int32_t*)(metadata + offsetVectorOffset * sizeof(void*));
    *outValue = state[fieldOffsets[fieldIndex]] & 1;
    return YES;
}

// displayMode is a Swift enum stored as an 8-byte case index followed by a
// discriminator tag (0 = the repliesPanning payload case, 1 = an empty case).
// Empty cases: regular = 0, repliesOpen = 1, repliesCompletelyOpen = 2,
// controlsHidden = 3, scrubbing = 4, statusExpanded = 5.
static BOOL progressLabelAlphaFromState(id pluginView, CGFloat* outAlpha) {
    if (!BHTIsSupportedHost()) return NO;
    Ivar stateIvar = class_getInstanceVariable([pluginView class], "state");
    if (!stateIvar) {
        return NO;
    }

    uint8_t* state =
        (uint8_t*)(__bridge void*)pluginView + ivar_getOffset(stateIvar);
    uint64_t displayModeCase = *(uint64_t*)state;
    uint8_t displayModeTag = state[8];

    BOOL visible =
        displayModeTag == 1 && (displayModeCase < 1 || displayModeCase > 3);

    if (visible) {
        BOOL panning = NO, chromeFaded = NO;
        if (cardStateBoolField(state, "isPanningBetweenCards",
                               &panning) &&
            panning) {
            visible = NO;
        } else if (cardStateBoolField(state,
                                      "isChromeFadedOutWhilePanning",
                                      &chromeFaded) &&
                   chromeFaded) {
            visible = NO;
        }
    }

    *outAlpha = visible ? 1.0 : 0.0;
    return YES;
}

%hook _TtC14T1TwitterSwift32ImmersiveProgressLabelPluginView

- (void)setAlpha:(CGFloat)alpha {
    if ([BHTSettings boolForKey:@"restore_video_timestamp"]) {
        CGFloat stateAlpha;
        if (progressLabelAlphaFromState(self, &stateAlpha)) {
            alpha = stateAlpha;
        }
    }

    %orig(alpha);
}

%end

// MARK: - Disable Immersive Feed Scrolling

// The card pan drives vertical paging between videos; blocking it lets the
// swipe-down dismiss gesture take over.
static BOOL isImmersiveCardPan(id viewController,
                               UIGestureRecognizer* gesture) {
    Ivar panIvar =
        class_getInstanceVariable([viewController class], "panRecognizer");
    if (!panIvar) {
        panIvar = class_getInstanceVariable([viewController class],
                                           "$__lazy_storage_$_panRecognizer");
    }
    return panIvar && object_getIvar(viewController, panIvar) == gesture;
}

%hook T1ImmersiveViewController

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gesture {
    if ([BHTSettings boolForKey:@"disable_immersive_scroll"] &&
        isImmersiveCardPan(self, gesture)) {
        return NO;
    }

    return %orig;
}

%end

// T1ImmersiveViewControllerV2 was removed in X 12.24.1.
