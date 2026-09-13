//
//  Confirmations.x
//  NeoFreeBird
//

#import "Compatibility/BHTCompatibilityReporter.h"
#import "HookHelpers.h"

static void ShowConfirmation(void (^confirmed)(void)) {
    [%c(FLEXAlert)
        makeAlert:^(FLEXAlert* make) {
            make.message([[BHTBundle sharedBundle]
                localizedStringForKey:@"CONFIRM_ALERT_MESSAGE"]);
            make.button([[BHTBundle sharedBundle]
                            localizedTwitterStringForKey:@"YES_ACTION_LABEL"])
                .handler(^(NSArray<NSString*>* strings) {
                    confirmed();
                });
            make.button([[BHTBundle sharedBundle]
                            localizedTwitterStringForKey:@"NO_ACTION_LABEL"])
                .cancelStyle();
        }
         showFrom:topMostController()];
}

// MARK: - Tweet confirm

// All send paths funnel through this. Some callers send no argument, so the
// button register can hold garbage and must not be retained.
%hook T1TweetComposeViewController

- (void)_t1_didTapSendButton:(__unsafe_unretained UIButton*)sendButton {
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticSendButtonTapped);

    if (![BHTSettings boolForKey:@"tweet_confirm"]) {
        BHTRecordReplyWorkflowDiagnostic(
            BHTReplyWorkflowDiagnosticSendForwardedToX);
        return %orig;
    }

    ShowConfirmation(^{
        BHTRecordReplyWorkflowDiagnostic(
            BHTReplyWorkflowDiagnosticSendForwardedToX);
        %orig;
    });
}

%end

// MARK: - Follow confirm

%hook TUIFollowControl

- (void)_followUser:(id)sender event:(id)event {
    if (![BHTSettings boolForKey:@"follow_confirm"]) {
        return %orig;
    }

    ShowConfirmation(^{
        %orig;
    });
}

%end

// MARK: - Like confirm

// X 12.9 handles the inline action at the button itself. Hooking the former
// actions-view delegate would either miss this path or prompt twice.
%hook TTAStatusInlineActionButton

- (void)didTap {
    if (![BHTSettings boolForKey:@"like_confirm"] ||
        ![self isKindOfClass:%c(TTAStatusInlineFavoriteButton)]) {
        return %orig;
    }

    ShowConfirmation(^{
        %orig;
    });
}

%end

// The fullscreen media viewer's heart has its own action path.
// T1SlideshowStatusView was removed in X 12.24.1.

// Double tap to like in the immersive video player; the gesture never unlikes.
%hook _TtC14T1TwitterSwift32ImmersiveDoubleTapLikePluginView

- (void)handleDoubleTap:(id)gesture {
    if (![BHTSettings boolForKey:@"like_confirm"]) {
        return %orig;
    }

    ShowConfirmation(^{
        %orig;
    });
}

%end

// MARK: - Undo tweet

// A timeout of 0 disables undo; any positive value is the delay in seconds.
static BOOL UndoTweetEnabled(void) {
    return [BHTSettings integerForKey:@"undo_tweet_timeout"] > 0;
}

// Force every composition onto the premium undo path (outbox timer, no cap) —
// the free path is just a toast, capped at 10s. Forcing config access and the
// per-type toggles marks it undoable; the forced undoTimeInterval becomes the
// real send delay.
%hook T1UndoSendConfig

- (BOOL)hasAccessToUndoSend {
    return UndoTweetEnabled() ? YES : %orig;
}

- (double)undoTimeInterval {
    return UndoTweetEnabled()
               ? (double)[BHTSettings integerForKey:@"undo_tweet_timeout"]
               : %orig;
}

- (BOOL)isUndoSendTurnedOnForOriginalTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

- (BOOL)isUndoSendTurnedOnForReplyTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

- (BOOL)isUndoSendTurnedOnForQuoteTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

- (BOOL)isUndoSendTurnedOnForTweetstormTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

- (BOOL)isUndoSendTurnedOnForPollTweets {
    return UndoTweetEnabled() ? YES : %orig;
}

%end

// The composer bakes the config's interval onto the composition; override the
// read too so the coordinator's send timer uses the chosen value.
%hook TFNTwitterComposition

- (double)undoTimeInterval {
    return UndoTweetEnabled()
               ? (double)[BHTSettings integerForKey:@"undo_tweet_timeout"]
               : %orig;
}

// The original computes this from the interval directly, bypassing the getter.
- (NSDate*)undoableSendDate {
    if (!UndoTweetEnabled()) {
        return %orig;
    }
    NSDate* added = [self undoableAddedDate];
    return added ? [added dateByAddingTimeInterval:[self undoTimeInterval]] : nil;
}

%end
