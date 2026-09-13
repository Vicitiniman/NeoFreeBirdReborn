//
//  FeatureSwitches.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import "Sidebar/BHTSidebarNavigationUtility.h"

#import <objc/runtime.h>

// While set, the custom-navigation tab gates (below) report their real values,
// so callers can tell genuinely-held panels from ones only unlocked for the tab
// pool.
static __thread BOOL ReportGenuineTabGates = NO;

// Whether the account is genuinely a premium subscriber.  NeoFreeBird does not
// spoof subscription state; doing so breaks server-backed flows and can leak a
// fabricated tier into analytics and settings.
static BOOL AccountIsGenuinelyPremium(void) {
    Class hostClass = objc_getClass("T1HostViewController");
    id host = ((id (*)(id, SEL))objc_msgSend)(
        (id)hostClass, @selector(sharedHostViewController));
    id account = ((id (*)(id, SEL))objc_msgSend)(host, @selector(currentAccount));
    if (![account respondsToSelector:@selector(isPremiumTierUser)]) {
        return NO;
    }

    return ((BOOL (*)(id, SEL))objc_msgSend)(account,
                                             @selector(isPremiumTierUser));
}

// MARK: - Feature switch overrides

static NSNumber* FeatureSwitchOverrideValueForKey(NSString* key) {
    if (![key isKindOfClass:[NSString class]]) {
        return nil;
    }

    // Custom timelines overrides
    BOOL hideCustomTimelines = [BHTSettings boolForKey:@"hide_custom_timelines"];
    if ([key isEqualToString:@"hometimeline_pinned_tabs_topics_enabled"] ||
        [key isEqualToString:
                 @"hometimeline_pinned_tabs_generic_timelines_enabled"] ||
        [key isEqualToString:
                 @"hometimeline_pinned_tabs_sticky_warm_start_enabled"] ||
        [key
            isEqualToString:
                @"super_follow_subscriptions_home_timeline_tab_sticky_enabled"]) {
        return hideCustomTimelines ? @NO : nil;
    }

    // Keeps the selected timeline tab across sessions.
    if ([key isEqualToString:
                 @"home_timeline_non_sticky_tab_on_new_session_enabled"]) {
        return [BHTSettings boolForKey:@"remember_timeline_tab"] ? @NO : nil;
    }

    // Legacy BHTwitter feature unlocks, updated for the keyed switch funnel used
    // by X 12.9. Disabled preferences leave the account's native value intact.
    if ([key isEqualToString:@"voice_replies_enabled"] ||
        [key isEqualToString:@"voice_creation_enabled"]) {
        return [BHTSettings boolForKey:@"voice_creation_enabled"] ? @YES : nil;
    }

    if ([key isEqualToString:@"dm_reply_later_enabled"]) {
        return [BHTSettings boolForKey:@"dm_reply_later_enabled"] ? @YES : nil;
    }

    if ([key isEqualToString:@"media_upload_4k_enabled"] ||
        [key isEqualToString:@"media_upload_xlite_4k_enabled"]) {
        return [BHTSettings boolForKey:@"media_upload_4k_enabled"] ? @YES : nil;
    }

    // "Old compose bar" means disable the new XChat composer. "No voice
    // messages" likewise disables both legacy DM and XChat voice paths. These
    // were inverted in an earlier audit draft.
    if ([key isEqualToString:@"xchat_message_composer_v2"]) {
        return [BHTSettings boolForKey:@"old_compose_bar"] ? @NO : nil;
    }

    if ([key isEqualToString:@"dm_voice_creation_enabled"] ||
        [key isEqualToString:@"dm_voice_rendering_enabled"] ||
        [key isEqualToString:@"xchat_voice_messages_enabled"]) {
        return [BHTSettings boolForKey:@"no_voice_messages"] ? @NO : nil;
    }

    if ([key isEqualToString:@"hometimeline_pinned_tabs_limit"] ||
        [key isEqualToString:@"hometimeline_pinned_tabs_management_pinnedsection_"
                             @"inline_limit"] ||
        [key isEqualToString:
                 @"hometimeline_pinned_tabs_management_topics_inline_limit"]) {
        return hideCustomTimelines ? @0 : nil;
    }

    // Gates the add-tab (+) accessory button on the home tab bar.
    if ([key isEqualToString:
                 @"hometimeline_pinned_tabs_pinned_trailing_accessory_enabled"]) {
        return hideCustomTimelines ? @NO : nil;
    }

    // Edit tweet.  This only exposes the native surface; the server still
    // decides whether an account can complete the edit.
    if ([key isEqualToString:@"edit_tweet_ga_composition_enabled"] ||
        [key isEqualToString:@"edit_tweet_pdp_dialog_enabled"]) {
        return [BHTSettings boolForKey:@"enable_edit_tweet"] ? @YES : nil;
    }

    // Restore the animated launch screen (AppLifecycle.x strips its X-shaped
    // reveal mask)
    if ([key isEqualToString:@"app_launch_animated_launch_screen_enabled"]) {
        return [BHTSettings boolForKey:@"restore_launch_animation"] ? @YES : nil;
    }

    // Grok translations
    if ([key isEqualToString:
                 @"grok_translations_bio_inline_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_bio_translation_is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_post_inline_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_post_translation_is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_community_note_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_poll_translation_is_enabled"]) {
        return [BHTSettings boolForKey:@"enable_grok_translations"] ? @YES : nil;
    }

    // Checked before the per-language preference, so turning these off stops all
    // auto translation while manual translate stays.
    if ([key isEqualToString:
                 @"grok_translations_post_auto_translation_is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_bio_auto_translation_is_enabled"] ||
        [key isEqualToString:@"grok_translations_community_note_auto_translation_"
                             @"is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_notification_auto_translation_is_enabled"] ||
        [key isEqualToString:
                 @"grok_translations_immersive_auto_translate_is_enabled"]) {
        return [BHTSettings boolForKey:@"disable_auto_translate"] ? @NO : nil;
    }

    // X 12.24.1 creates a separate GrokBotSidebarUpsell, outside the
    // TwitterDash item arrays. Its failable initializer checks this exact key.
    if ([key isEqualToString:@"grok_ios_grok_bot_sidebar_enabled"]) {
        return [BHTSettings boolForKey:@"hide_grok_sidebar"] ? @NO : nil;
    }

    // Grok buttons
    if ([key isEqualToString:@"grok_ask_grok_button_under_post_focal_enabled"] ||
        [key
            isEqualToString:@"grok_ask_grok_button_under_post_preview_enabled"]) {
        return [BHTSettings boolForKey:@"hide_grok_analyze"] ? @NO : nil;
    }

    if ([key isEqualToString:
                 @"grok_edit_with_grok_button_under_post_focal_enabled"] ||
        [key isEqualToString:
                 @"grok_edit_with_grok_button_under_post_preview_enabled"]) {
        return [BHTSettings boolForKey:@"hide_grok_create"] ? @NO : nil;
    }

    // Grok creation surfaces: composer buttons, imagine menus and CTAs, Edit with
    // Grok on photo posts, and the immersive player's create-your-own button.
    if ([key isEqualToString:@"ios_composer_grok_button_enabled"] ||
        [key isEqualToString:@"grok_imagine_composer_enabled"] ||
        [key isEqualToString:@"grok_composer_imagine_is_enabled"] ||
        [key isEqualToString:
                 @"grok_composer_attachment_imagine_menu_is_enabled"] ||
        [key isEqualToString:@"grok_timeline_preview_imagine_menu_is_enabled"] ||
        [key isEqualToString:@"grok_timeline_video_imagine_menu_is_enabled"] ||
        [key
            isEqualToString:@"grok_timeline_slideshow_imagine_menu_is_enabled"] ||
        [key isEqualToString:@"grok_ios_edit_photo_post_button_enabled"] ||
        [key isEqualToString:@"grok_ios_imagine_cta_focal_enabled"] ||
        [key isEqualToString:@"grok_ios_imagine_cta_reply_enabled"] ||
        [key isEqualToString:@"grok_ios_imagine_cta_timeline_enabled"] ||
        [key isEqualToString:@"grok_ios_imagine_cta_profile_enabled"] ||
        [key isEqualToString:@"grok_immersive_create_own_button_enabled"]) {
        return [BHTSettings boolForKey:@"hide_grok_create"] ? @NO : nil;
    }

    // Disguised switch family for the Grok edit-photo and create-own buttons,
    // read only by Grok.GrokFeatureAccess.
    if ([key hasPrefix:@"ios_button_layout_fix"] && [key hasSuffix:@"_enabled"]) {
        return [BHTSettings boolForKey:@"hide_grok_create"] ? @NO : nil;
    }

    // Grok analyze: every tweet-side show decision gates on this backend switch
    // before consulting the per-tweet flag.
    if ([key isEqualToString:
                 @"grok_ios_author_view_analyze_button_via_backend_enabled"]) {
        return [BHTSettings boolForKey:@"hide_grok_analyze"] ? @NO : nil;
    }

    // The profile header's analyze (summary) button bottoms out in this switch on
    // both header variants, one of which reads it through a direct Swift call.
    if ([key isEqualToString:@"grok_ios_profile_summary_enabled"]) {
        return [BHTSettings boolForKey:@"hide_grok_analyze"] ? @NO : nil;
    }

    // Session token appended to shared/copied links (&t=)
    if ([key isEqualToString:@"rehire_share_update_url_enabled"]) {
        return [BHTSettings boolForKey:@"strip_share_tracking"] ? @NO : nil;
    }

    // The copy-profile action provider builds on the classic header. Preserve
    // X's native header redesign unless that opt-in feature actually needs the
    // older provider row.
    if ([key isEqualToString:@"ios_profile_redesign_header_rework_enabled"]) {
        return [BHTSettings boolForKey:@"copy_profile_info"] ? @NO : nil;
    }

    // Profile tabs
    if ([key isEqualToString:@"articles_timeline_profile_tab_enabled"]) {
        return [BHTSettings boolForKey:@"disable_articles"] ? @NO : nil;
    }

    if ([key isEqualToString:@"highlights_tweets_tab_ui_enabled"]) {
        return [BHTSettings boolForKey:@"disable_highlights"] ? @NO : nil;
    }

    // Age verification bypass
    if ([key hasPrefix:@"ios_age_assurance"] ||
        [key isEqualToString:@"grok_settings_age_restriction_enabled"]) {
        if ([BHTSettings boolForKey:@"bypass_age_verification"]) {
            return @NO;
        }
    }

    // Conversation / tweet detail
    if ([key isEqualToString:@"reply_sorting_enabled"] ||
        [key isEqualToString:
                 @"conversational_replies_ios_minimal_detail_enabled_v2"]) {
        return [BHTSettings boolForKey:@"reply_sorting"] ? @NO : nil;
    }

    if ([key isEqualToString:
                 @"ios_tweet_detail_conversation_context_removal_enabled"]) {
        return [BHTSettings boolForKey:@"restore_reply_context"] ? @NO : nil;
    }

    // Video captions
    if ([key isEqualToString:@"ios_tav_default_closed_captions_enabled"] ||
        [key isEqualToString:@"ios_audio_transcription_subtitles_vod_enabled"]) {
        return [BHTSettings boolForKey:@"disable_video_captions"] ? @NO : nil;
    }

    // Custom navigation: per-panel tab gates, forced on so every panel exists for
    // the editor to offer. The tab bar hook keeps them out of the bar and the
    // dash spoof (below) keeps the panels only unlocked here out of the side
    // drawer.
    if ([key isEqualToString:@"ios_tab_bar_default_show_profile"] ||
        [key isEqualToString:@"ios_tab_bar_default_show_communities"]) {
        return @YES;
    }

    // Communities, Spaces, News and Grok are enabled outright for every account.
    if ([key isEqualToString:@"ai_trends_ios_enable_news_tab"] ||
        [key isEqualToString:@"voice_rooms_consumption_enabled"] ||
        [key isEqualToString:@"communities_enable_explore_tab"] ||
        [key isEqualToString:@"subscriptions_inapp_grok"]) {
        return @YES;
    }

    // The Media tab reads its switch as an integer and shows on this sentinel.
    if ([key isEqualToString:@"media_tab_enabled"]) {
        return @99;
    }

    // 0 hides the Communities tab, 1 is contextual-only; anything else shows it.
    if ([key isEqualToString:@"c9s_tab_visibility"]) {
        return @2;
    }

    if (!ReportGenuineTabGates) {
        if ([key isEqualToString:@"subscriptions_premium_hub_enabled"] ||
            [key isEqualToString:@"recruiting_global_jobs_hub_enabled"]) {
            return @YES;
        }
    }

    // The Connect tab stays on its native gate (fresh accounts only): its drawer
    // row doesn't consult the tab bar, so forcing it would grow a row that can't
    // be hidden.

    // In-app article webview
    if ([key isEqualToString:@"ios_in_app_article_webview_enabled"]) {
        return @([BHTSettings boolForKey:@"new_inapp_webview"]);
    }

    // A negative threshold disables immersive auto-advance and removes its row
    // from the player's settings sheet.
    if ([key
            isEqualToString:@"immersive_video_auto_advance_duration_threshold"]) {
        return [BHTSettings boolForKey:@"disable_immersive_scroll"] ? @(-1) : nil;
    }

    // Reply downvote (dislike) button
    if ([key isEqualToString:@"conversational_replies_ios_downvote_enabled"]) {
        return [BHTSettings boolForKey:@"hide_downvote_button"] ? @NO : nil;
    }

    if ([key isEqualToString:@"ssp_ads_spotlight"] ||
        [key isEqualToString:@"ssp_ads_spotlight_client_only_integration"] ||
        [key isEqualToString:
                 @"ssp_ads_spotlight_client_only_integration_preload"] ||
        [key isEqualToString:@"ssp_ads_home_enabled"] ||
        [key isEqualToString:@"ssp_ads_home_client_only_integration"] ||
        [key isEqualToString:@"ssp_ads_profile"] ||
        [key isEqualToString:
                 @"ssp_ads_profile_client_only_integration_enabled"] ||
        [key isEqualToString:@"ssp_ads_immersive"] ||
        [key isEqualToString:@"ssp_ads_immersive_client_only_integration"] ||
        [key isEqualToString:@"ssp_ads_tweet_details"] ||
        [key isEqualToString:
                 @"ssp_ads_tweet_details_client_only_integration"] ||
        [key isEqualToString:@"video_configurations_dynamic_ad_enabled"] ||
        [key isEqualToString:@"unified_cards_collection_ads_is_enabled"] ||
        [key isEqualToString:@"unified_cards_poster_ads_enabled"] ||
        [key isEqualToString:
                 @"ios_in_app_article_webview_support_promoted_content"] ||
        [key isEqualToString:@"profile_user_promoted_timeline"]) {
        return [BHTSettings boolForKey:@"hide_promoted"] ? @NO : nil;
    }

    // Older and newly introduced ad experiments still follow these families.
    // This complements the exact X 12.9 keys above without changing any value
    // while the No ads toggle is off.
    if ([BHTSettings boolForKey:@"hide_promoted"] &&
        ([key hasPrefix:@"ad_formats_"] ||
         [key hasPrefix:@"ads_"] ||
         [key hasPrefix:@"ssp_ads_"] ||
         [key containsString:@"_ads_"] ||
         [key hasSuffix:@"_ads_enabled"] ||
         [key isEqualToString:@"ads_enabled"])) {
        return @NO;
    }

    // Reactive blending: likes and follows make the timeline request fresh
    // who-to-follow suggestions and splice them in; this switch turns it off.
    if ([key isEqualToString:@"wtf_device_follow_nudge_turn_off_reactive_blending_enabled"]) {
        return [BHTSettings boolForKey:@"hide_who_to_follow"] ? @YES : nil;
    }

    // Premium / verification upsells. Not all gate on !isPremiumTierUser, so
    // every upsell surface present in 12.3 is disabled here.
    if ([key isEqualToString:@"ios_profile_analytics_upsell_enabled"] ||
        [key isEqualToString:@"ios_profile_analytics_upsell_possible_enabled"] ||
        [key isEqualToString:@"ios_profile_upgrade_upsell_enabled"] ||
        [key isEqualToString:@"ios_profile_upgrade_upsell_swapper_enabled"] ||
        [key isEqualToString:@"ios_profile_visitor_upsell_enabled"] ||
        [key isEqualToString:@"subscriptions_upsells_get_verified_profile"] ||
        [key isEqualToString:@"subscriptions_upsells_reply_boost_enabled"] ||
        [key
            isEqualToString:@"subscriptions_upsells_reply_boost_popup_enabled"] ||
        [key isEqualToString:@"subscriptions_upsells_post_analytics_enabled"] ||
        [key isEqualToString:@"subscriptions_upsells_creator_support_post_"
                             @"conversation_enabled"] ||
        [key isEqualToString:@"longform_notetweets_composer_upsell_enabled"] ||
        [key isEqualToString:
                 @"longform_notetweets_composer_auto_upsell_enabled"] ||
        [key isEqualToString:@"subscriptions_cta_on_replies_enabled"] ||
        [key isEqualToString:@"super_follow_upsell_sticky_button_enabled"] ||
        [key isEqualToString:@"subscriptions_new_paywall_enabled"] ||
        [key isEqualToString:@"subscriptions_offers_promotional_enabled"] ||
        [key isEqualToString:@"subscriptions_gifting_premium_enabled"] ||
        [key isEqualToString:
                 @"subscriptions_gifting_premium_intro_copy_enabled"] ||
        [key isEqualToString:
                 @"subscriptions_ios_download_to_offline_upsell_enabled"] ||
        [key isEqualToString:
                 @"ios_notifications_blue_verified_introductory_offer_visible"] ||
        [key isEqualToString:@"ios_notifications_blue_verified_introductory_"
                             @"offer_prefix_visible"] ||
        [key isEqualToString:@"dash_items_download_grok_enabled"]) {
        return [BHTSettings boolForKey:@"hide_premium_offer"] ? @NO : nil;
    }

    // Boost (quick promote) button and its upsells. Each placement reads its own
    // switch rather than the root one, so all of them are disabled.
    if ([key isEqualToString:@"ios_tweet_promote_button_enabled"] ||
        [key isEqualToString:@"ios_tweet_promote_button_timeline_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_tweet_composer_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_overflow_menu_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_focal_top_toolbar_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_focal_bottom_toolbar_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_focal_top_analytics_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_in_post_analytics_enabled"] ||
        [key
            isEqualToString:
                @"ios_tweet_promote_button_boost_again_in_top_toolbar_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_sent_tweet_toast_enabled"] ||
        [key isEqualToString:
                 @"ios_tweet_promote_button_third_party_boost_enabled"] ||
        [key isEqualToString:@"thirdparty_boost_author_view_button_enabled"]) {
        return ([BHTSettings boolForKey:@"hide_promoted"] ||
                [BHTSettings boolForKey:@"hide_premium_offer"])
                   ? @NO
                   : nil;
    }

    // The Premium settings row is handled in the
    // -isSubscriptionsSettingsItemEnabledWithProvider: hook. Creator purchases
    // and the subscriber-only profile tab already gate on real creator
    // eligibility, which the forced tier never affects.

    // Creator Studio / Monetization entries gate purely on these switches with no
    // premium check, so follow the genuine status: a real subscriber keeps them
    // while the spoof hides them.
    if ([key isEqualToString:@"creator_studio_nav_enabled"] ||
        [key isEqualToString:@"creator_monetization_dashboard_enabled"]) {
        if ([BHTSettings boolForKey:@"hide_premium_offer"] &&
            !AccountIsGenuinelyPremium()) {
            return @NO;
        }
    }

    return nil;
}

// Every feature switch facade bottoms out in TFSFeatureSwitches, but instances
// can be wrapped in TFSInstrumentedFeatureSwitches, which implements its own
// typed getters, so both classes need the same hooks.

%hook TFSFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.boolValue : %orig;
}

- (NSInteger)integerForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.integerValue : %orig;
}

- (NSNumber*)numberForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ?: %orig;
}

- (id)rawValueForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ?: %orig;
}

- (BOOL)unsafePeekBoolForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.boolValue : %orig;
}

- (NSInteger)unsafePeekIntegerForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.integerValue : %orig;
}

// Some reads, like the default captions setup, only consult the value when the
// switch reports a non-default one.
- (BOOL)hasNonDefaultValueForKey:(NSString*)key {
    return FeatureSwitchOverrideValueForKey(key) ? YES : %orig;
}

%end

%hook TFSInstrumentedFeatureSwitches

- (BOOL)boolForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.boolValue : %orig;
}

- (NSInteger)integerForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.integerValue : %orig;
}

- (NSNumber*)numberForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ?: %orig;
}

- (id)rawValueForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ?: %orig;
}

- (BOOL)unsafePeekBoolForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.boolValue : %orig;
}

- (NSInteger)unsafePeekIntegerForKey:(NSString*)key {
    NSNumber* override = FeatureSwitchOverrideValueForKey(key);
    return override ? override.integerValue : %orig;
}

- (BOOL)hasNonDefaultValueForKey:(NSString*)key {
    return FeatureSwitchOverrideValueForKey(key) ? YES : %orig;
}

%end

// MARK: - Typed feature switch accessors

%hook TFSAccountFeatureSwitches

// Sets the scroll indicator in -[TFNDataViewController loadView]; the read
// bypasses the boolForKey: funnels above via a Swift access-once provider.
+ (BOOL)isShowsVerticalScrollIndicatorEnabled {
    return [BHTSettings boolForKey:@"show_scroll_indicator"] ? YES : %orig;
}

// Premium row in Settings. Its gate (subscriptions_enabled || gating_bypass &&
// isPremiumTierUser) is on for everyone as an upsell, so %orig can't hide
// it — short-circuit to NO unless the account (the provider) is genuinely
// premium.
- (BOOL)isSubscriptionsSettingsItemEnabledWithProvider:(id)provider {
    if (![provider respondsToSelector:@selector(isPremiumTierUser)]) {
        return %orig;
    }

    BOOL genuinePremium = ((BOOL (*)(id, SEL))objc_msgSend)(
        provider, @selector(isPremiumTierUser));

    if ([BHTSettings boolForKey:@"hide_premium_offer"] && !genuinePremium) {
        return NO;
    }
    return %orig;
}

// Custom navigation: tab gates read as typed accessors instead of through the
// keyed funnels, forced on like the keyed gates so their panels' entries build.
- (BOOL)birdwatchHomePageIsEnabled {
    if (ReportGenuineTabGates) {
        return %orig;
    }
    return YES;
}

- (BOOL)birdwatchHistoryIsEnabled {
    if (ReportGenuineTabGates) {
        return %orig;
    }
    return YES;
}

// Expose the native video cache only while downloading is enabled.
- (BOOL)isVideoCacheEnabled {
    return [BHTSettings boolForKey:@"download_videos"] ? YES : %orig;
}

%end

// MARK: - High quality images

%hook T1ImageDisplayView

- (BOOL)_tfn_shouldUseHighestQualityImage {
    return [BHTSettings boolForKey:@"auto_highest_load"] ? YES : %orig;
}

- (BOOL)_tfn_shouldUseHighQualityImage {
    return [BHTSettings boolForKey:@"auto_highest_load"] ? YES : %orig;
}

%end

// T1SlideshowViewController was removed in X 12.24.1.

// MARK: - Highest available video quality

static char kBHTSortedVideoVariantsKey;

static long long BHTVideoVariantScore(id variant) {
    @try {
        id bitrate = [variant valueForKey:@"bitrate"];
        if ([bitrate respondsToSelector:@selector(longLongValue)] &&
            [bitrate longLongValue] > 0) {
            return [bitrate longLongValue];
        }
    } @catch (__unused NSException* exception) {
    }

    NSString* url = [variant respondsToSelector:@selector(url)]
                        ? ((id (*)(id, SEL))objc_msgSend)(variant, @selector(url))
                        : nil;
    static NSRegularExpression* resolution;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        resolution =
            [NSRegularExpression regularExpressionWithPattern:@"/(\\d+)x(\\d+)/"
                                                      options:0
                                                        error:nil];
    });
    NSTextCheckingResult* match =
        [resolution firstMatchInString:url ?: @""
                               options:0
                                 range:NSMakeRange(0, url.length)];
    if (match.numberOfRanges == 3) {
        long long width = [[url substringWithRange:[match rangeAtIndex:1]] longLongValue];
        long long height = [[url substringWithRange:[match rangeAtIndex:2]] longLongValue];
        return width * height;
    }
    return 0;
}

%hook TFSTwitterEntityMediaVideoInfo

- (NSArray*)variants {
    NSArray* variants = %orig;
    if (![BHTSettings boolForKey:@"force_highest_video_quality"] ||
        variants.count < 2) {
        return variants;
    }

    // Video info is queried repeatedly while cells are measured and reused.
    // Keep a result only while X returns the exact same immutable source array,
    // avoiding repeated KVC, regular-expression work, and sorting on scroll.
    NSArray* cached =
        objc_getAssociatedObject(self, &kBHTSortedVideoVariantsKey);
    if (cached.count == 2 && cached.firstObject == variants) {
        return cached.lastObject;
    }

    NSArray* sorted =
        [variants sortedArrayUsingComparator:^NSComparisonResult(id left,
                                                                 id right) {
        long long leftScore = BHTVideoVariantScore(left);
        long long rightScore = BHTVideoVariantScore(right);
        if (leftScore > rightScore) return NSOrderedAscending;
        if (leftScore < rightScore) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    objc_setAssociatedObject(self, &kBHTSortedVideoVariantsKey,
                             @[ variants, sorted ],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return sorted;
}

- (NSString*)primaryUrl {
    NSString* original = %orig;
    if (![BHTSettings boolForKey:@"force_highest_video_quality"]) {
        return original;
    }
    for (id variant in [self variants]) {
        NSString* contentType = [variant respondsToSelector:@selector(contentType)]
                                    ? ((id (*)(id, SEL))objc_msgSend)(variant,
                                                                     @selector(contentType))
                                    : nil;
        NSString* url = [variant respondsToSelector:@selector(url)]
                            ? ((id (*)(id, SEL))objc_msgSend)(variant, @selector(url))
                            : nil;
        if ([contentType isEqualToString:@"video/mp4"] && url.length > 0) {
            return url;
        }
    }
    return original;
}

%end

// MARK: - Promoted content

// API commands copy this off their context when building requests.
%hook TFNTwitterAPICommandContext

- (BOOL)allowPromotedContent {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

%end

// MARK: - Account feature gates

%hook TFNTwitterAccount

- (BOOL)isSensitiveTweetWarningsComposeEnabled {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? NO
               : %orig;
}

- (BOOL)isSensitiveTweetWarningsConsumeEnabled {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? NO
               : %orig;
}

- (BOOL)isAgeAssuranceAgeVerificationFlowEnabled {
    return [BHTSettings boolForKey:@"bypass_age_verification"] ? NO : %orig;
}

- (BOOL)isVideoDynamicAdEnabled {
    return [BHTSettings boolForKey:@"hide_promoted"] ? NO : %orig;
}

- (BOOL)isDoubleMaxZoomFor4KImagesEnabled {
    return [BHTSettings boolForKey:@"auto_highest_load"] ? YES : %orig;
}

- (BOOL)photoUploadHighQualityImagesSettingIsVisible {
    return [BHTSettings boolForKey:@"auto_highest_load"] ? YES : %orig;
}

- (BOOL)isLoadingHighestQualityImageVariantPermitted {
    return [BHTSettings boolForKey:@"auto_highest_load"] ? YES : %orig;
}

// Custom navigation: the Money tab's gate, granted per account/region by the
// server, forced on like the switch-keyed tab gates so the panel's entry
// builds.
- (BOOL)canAccessXPayments {
    if (ReportGenuineTabGates) {
        return %orig;
    }
    return YES;
}

%end

// MARK: - Custom navigation - genuine panel availability

// Whether a panel would be tab-eligible without the forced gates: the tab bar
// editor only offers genuine panels, and the dash spoof keeps the rest out of
// the drawer.

static id accountFeatureSwitches(void) {
    Class switchesClass = objc_getClass("TFSAccountFeatureSwitches");
    if (![(id)switchesClass
            respondsToSelector:@selector(lastUsedAccountFeatureSwitches)]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(
        (id)switchesClass, @selector(lastUsedAccountFeatureSwitches));
}

static BOOL genuineTabGateFlag(id receiver, SEL selector) {
    if (![receiver respondsToSelector:selector]) {
        return NO;
    }

    BOOL saved = ReportGenuineTabGates;
    ReportGenuineTabGates = YES;
    BOOL value = ((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector);
    ReportGenuineTabGates = saved;
    return value;
}

static id featureSwitchesProvider(void) {
    id accountSwitches = accountFeatureSwitches();
    if (![accountSwitches respondsToSelector:@selector(provider)]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(accountSwitches, @selector(provider));
}

static BOOL genuineSwitchBool(NSString* key) {
    id provider = featureSwitchesProvider();
    if (![provider respondsToSelector:@selector(boolForKey:)]) {
        return NO;
    }

    BOOL saved = ReportGenuineTabGates;
    ReportGenuineTabGates = YES;
    BOOL value = ((BOOL (*)(id, SEL, NSString*))objc_msgSend)(
        provider, @selector(boolForKey:), key);
    ReportGenuineTabGates = saved;
    return value;
}

BOOL panelIsGenuinelyAvailable(long long panelID) {
    switch (panelID) {
        case 13: { // Community Notes
            id switches = accountFeatureSwitches();
            return genuineTabGateFlag(switches,
                                      @selector(birdwatchHomePageIsEnabled)) &&
                   genuineTabGateFlag(switches, @selector(birdwatchHistoryIsEnabled));
        }
        case 16: // Premium hub
            return genuineSwitchBool(@"subscriptions_premium_hub_enabled");
        case 17: // Jobs
            return genuineSwitchBool(@"recruiting_global_jobs_hub_enabled") ||
                   genuineSwitchBool(@"recruiting_jetfuel_jobs_hub_enabled");
        case 18: { // Money
            id host =
                ((id (*)(id, SEL))objc_msgSend)(objc_getClass("T1HostViewController"),
                                                @selector(sharedHostViewController));
            id account =
                ((id (*)(id, SEL))objc_msgSend)(host, @selector(currentAccount));
            return genuineTabGateFlag(account, @selector(canAccessXPayments));
        }
        default: // Panels the app builds, or the unlock enables, for everyone
            return YES;
    }
}

// MARK: - Custom navigation - side drawer rows

// The drawer builds a row for each panel absent from the tab bar, reading a
// snapshot taken in updateVisiblePanelIDs. Extra panels are injected only
// there, scoped by a flag — other visiblePanelIDs readers must see the real tab
// state. Premium is claimed for a non-premium account, for whom it's just an
// upsell.

static __thread BOOL DashPanelIDQuery = NO;
static char BHTSidebarDeferredApplyScheduledKey;

static void BHTScheduleSidebarConfigurationReapply(id controller) {
    if (!controller) return;
    if ([objc_getAssociatedObject(
            controller,
            &BHTSidebarDeferredApplyScheduledKey) boolValue]) {
        BHTRecordSidebarDeferredApplyCoalesced();
        return;
    }

    objc_setAssociatedObject(
        controller, &BHTSidebarDeferredApplyScheduledKey, @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BHTRecordSidebarDeferredApplyScheduled();
    __weak id weakController = controller;
    dispatch_async(dispatch_get_main_queue(), ^{
        id strongController = weakController;
        if (!strongController) return;
        BHTRecordSidebarDeferredApplyExecuted();
        @try {
            // Keep the marker set while the Swift @Published setters notify
            // observers. A synchronous updateVisiblePanelIDs re-entry must not
            // enqueue another next-turn apply.
            [BHTSidebarNavigationUtility
                applyConfigurationToDashContentController:
                    strongController];
        } @finally {
            objc_setAssociatedObject(
                strongController,
                &BHTSidebarDeferredApplyScheduledKey, nil,
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    });
}

%hook T1DashContentController

- (id)initWithAccount:(id)account
    interactionsTimelineBridge:(id)interactionsTimelineBridge {
    id controller = %orig(account, interactionsTimelineBridge);
    [BHTSidebarNavigationUtility
        registerDashContentController:controller];
    [BHTSidebarNavigationUtility
        applyConfigurationToDashContentController:controller];
    return controller;
}

- (void)updateVisiblePanelIDs {
    DashPanelIDQuery = YES;
    %orig;
    DashPanelIDQuery = NO;
    [BHTSidebarNavigationUtility
        applyConfigurationToDashContentController:self];
    // Account and drawer transitions can publish a replacement Swift array
    // after updateVisiblePanelIDs returns. Reapply on the next main turn
    // without recursively asking X to rebuild its panels again.
    BHTScheduleSidebarConfigurationReapply(self);
}

%end

%hook T1DashNavigationViewFactory

+ (id)buildDashViewControllerForAccount:(id)account
                  dashContentController:(id)dashContentController {
    // This is the last point before TwitterDash snapshots its Swift data
    // source into the SwiftUI drawer. Applying here covers controllers whose
    // private data source is populated after T1DashContentController's init.
    [BHTSidebarNavigationUtility
        registerDashContentController:dashContentController];
    [BHTSidebarNavigationUtility
        applyConfigurationToDashContentController:dashContentController];
    id controller =
        %orig(account, dashContentController);
    // The factory may repopulate TwitterDash's @Published arrays while
    // constructing the drawer, so enforce the saved layout after it finishes
    // as well as before it snapshots the data source.
    [BHTSidebarNavigationUtility
        applyConfigurationToDashContentController:dashContentController];
    BHTScheduleSidebarConfigurationReapply(
        dashContentController);
    return controller;
}

%end

%hook T1TabbedAppNavigationViewController

- (NSArray*)visiblePanelIDsForAppNavigation:(id)appNavigation {
    NSArray* panelIDs = %orig;
    if (!DashPanelIDQuery) {
        return panelIDs;
    }

    NSMutableArray* spoofed = [panelIDs mutableCopy];
    void (^claim)(NSNumber*) = ^(NSNumber* panelID) {
        if (![spoofed containsObject:panelID]) {
            [spoofed addObject:panelID];
        }
    };

    for (NSNumber* panelID in @[@13, @16, @17, @18]) {
        if (!panelIsGenuinelyAvailable(panelID.longLongValue)) {
            claim(panelID);
        }
    }

    if ([BHTSettings boolForKey:@"hide_grok_sidebar"]) {
        claim(@14);
    }

    if (!AccountIsGenuinelyPremium()) {
        claim(@16);
    }

    return spoofed;
}

%end

// MARK: - Grok creation - photo editor

// The photo editor's Edit with Grok entry has no feature switch of its own;
// both delegates hardcode YES.

%hook T1TweetComposeViewController

- (BOOL)photoEditorCanEditWithGrok:(id)photoEditor {
    return [BHTSettings boolForKey:@"hide_grok_create"] ? NO : %orig;
}

%end

%hook T1StatusPhotoEditorHandler

- (BOOL)photoEditorCanEditWithGrok:(id)photoEditor {
    return [BHTSettings boolForKey:@"hide_grok_create"] ? NO : %orig;
}

%end

// MARK: - Sensitive media warnings

%hook TFNTwitterStatus

- (BOOL)hasImageInterstitial {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? NO
               : %orig;
}

- (id)imageInterstitial {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? nil
               : %orig;
}

- (id)innerImageInterstitial {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? nil
               : %orig;
}

%end

%hook HFHealthSafetyFeature

+ (BOOL)isTweetMedialInterstitialEnabled:(id)featureSwitches {
    return [BHTSettings boolForKey:@"disable_sensitive_tweet_warnings"]
               ? NO
               : %orig;
}

%end
