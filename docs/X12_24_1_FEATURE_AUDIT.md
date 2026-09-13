# X 12.24.1 compatibility update — beta 54

Target: `com.atebits.Tweetie2`, X **12.24.1 build 1**, arm64, minimum iOS 15.0.
The supplied IPA contains 61 Mach-O images; all inspected encryption flags are
zero. Input SHA-256:
`d720024ea8d9125f1554727875f7d90b211d1800108be8a1bb59c0eb67dc6ceb`.

## Hook inventory

The [machine-readable audit](X12_24_1_HOOK_AUDIT.json) records every Logos
method's source signature, native encoding, implementation address, and owning
class where available. It also inventories compatibility-report probes and
the exported Swift sidebar setters. A missing alternative diagnostic probe
does not mean the active feature's implementation is missing.

| Classification | Methods | Meaning |
| --- | ---: | --- |
| Native method found | 223 | Present on the hooked class, a parent, or an app-supplied category |
| System runtime | 30 | UIKit/Foundation and other system implementations are outside the IPA; validate at runtime |
| Tweak additions | 9 | `%new` methods supplied by the tweak |
| Guarded runtime alternative | 2 | Removed legacy profile provider and private network finalizer; constructors skip them when absent. The network diagnostic uses its verified delegate fallback |
| Guarded legacy alias | 5 | Old Home class alias absent; its constructor checks prevent registration. The current mangled Home class is present |

No remaining unguarded Logos hook references a missing app class or method.
Presence and matching metadata do **not** establish device behavior or server
acceptance. Dynamic theme-provider replacements continue checking the active
provider and method shapes at runtime.

## Follow-up fixes in beta 54

- The profile header propagates its expanded height using additional safe-area
  insets (`_t1_updateContentViewControllerSafeAreaInsets`, T1Twitter `0x58c18c`).
  Its offset bounds use the scroll view's raw `contentInset`, not UIKit's
  `adjustedContentInset` (`0x58d348`). The gallery now applies this top safe area
  explicitly and preserves `offset + topInset` when the header size changes,
  matching TFNDataViewController's offset update in TwitterSPMMigration
  (`0xcdeaa8`). It no longer overwrites the native backend's own insets.
  Image cells and full-screen photos retain Aspect Fit.
- **Profiles > Default to Photos**, enabled by default, moves the native photo
  entry to the front of its existing media group. The verified
  `contentMainEntries` method (`0x2298e8`) creates a Videos/Photos group; the
  profile chooses inner index zero by default (`_activeEntryAtGroupIndex:`,
  `0x3fc8d4`). Groups are matched by entry identity without assuming an outer
  index. Order stays fixed for each provider so changing preferences cannot
  reinterpret its active selection. New profiles pick up the saved preference.
- The sidebar editor derives its IDs from its titled/icon-bearing metadata,
  eliminating the orphan Grok tile after Follower requests. Existing stored
  layouts are sanitized against that list. The independent Grok navigation
  switch and legacy runtime row filtering remain in place.
- Native regression fixtures cover menu ordering across different group
  positions, repeated menu reads, missing tabs, and offset preservation for
  first display, header changes, rotation and pull-to-refresh. Physical-device
  layout and gestures still require an acceptance check.

The beta 52 audit corrects two beta 51 inventory errors: an unknown app
selector is no longer accepted merely because its parent is NSObject or
UIViewController, and categories discovered before their class body are no
longer overwritten. There are **268 declarations** in this source snapshot.
The corrected audit exposes optional legacy methods separately from working
hooks. In particular, the legacy Copy Profile Info provider is unavailable in
this target's catalog-based profile header; it is guarded rather than claimed
as verified functionality.

## Follow-up fixes in beta 53

- The current `GrokBotSidebarUpsell` initializer in XAppLibraries checks
  `grok_ios_grok_bot_sidebar_enabled`. It is not a normal Dash item, so
  filtering `primaryItems`/`folderItems`/`tertiaryItems` does not remove it.
  The existing feature-switch funnel now returns false for this exact key
  while `hide_grok_sidebar` is enabled. Other Grok promotion surfaces remain
  on their native gates. The existing saved preference and default survive
  moving the control to **Edit navigation bar**; it saves immediately and
  explains that X must be closed and reopened to rebuild the cached upsell.
  The duplicate sidebar tile and Grok-page switch were removed. Search routes
  directly to the new navigation-editor control.
- `T1ProfileDisplayNormalMainContentProvider` still exposes
  `_generatePhotoViewController` and `_generateVideoViewController` with
  object-returning, argument-free signatures. Their native T1URT feeds are
  wrapped with the existing waterfall, thumbnail pipeline and media viewer.
  Native profile tabs, header and Follow actions remain intact. Photos and
  Videos use separate native feeds and separate snapshot collections; no
  account, cursor or profile identity is synthesized.
- The wrapper exposes `tfn_contentScrollView` and forwards the verified native
  scroll callbacks used by the resizable profile header. Backend pagination
  scrolls do not propagate into that header. Empty/loading/error views come
  from X when no media is available. Pull to refresh uses native `loadTop:`.
  Complete section snapshots replace the old media list, including deletions
  and cleared access states, while known decoded image dimensions survive a
  refreshed snapshot. The Likes-specific page remapping and newest-position
  guard do not run for profiles.
- **Profiles > Profile media waterfall** is enabled by default and can be
  disabled for native presentation. The compatibility export includes its
  value plus per-kind factory, section-update, captured-item and visibility
  observations under `likesRuntime`; it exports no new account IDs or text.
- Native regression fixtures cover snapshot replacement, empty/access states,
  image-dimension continuity, isolated feeds and the exact Grok promotion
  switch. Device interaction remains an acceptance check, not a claim based
  on static method presence.

## Follow-up fixes in beta 52

- Activity History now calls `numberOfTabsIn:` and
  `segmentedViewController:pageViewControllerAtIndex:` / `descriptorAtIndex:`
  through `TFNUISwift.LegacySegmentedViewController`. The old unified V1/V2
  callbacks no longer exist in this IPA. The remap activates only after the
  native four-page initialization and only under the custom Likes parent.
  Bookmarks, Videos, Articles, and Likes preserve the same native page order.
  Saving a changed selection reloads the actual native controller, keeps the
  current destination when possible, and records applied pages/native count
  in the compatibility report. Unknown tab counts preserve native behavior.
- The Likes editor saves taps, reorders, and waterfall changes immediately.
- The legacy Grok row matcher was extended in beta 52; the device report
  showed that the separate current promotion still appeared. Beta 53 targets
  that promotion directly, as described below.
- The current Home container's eager and lazy providers both retain
  `homeTimelineViewController` independently from their Following/filtered
  controllers. Swift reflection reads that explicit owner; the filter compares
  it with the actual URT controller's ancestry. Unknown ownership falls back
  to the guarded legacy timeline identity path, never a selected-tab guess.
- Matching includes canonical original text and native user-mention entities
  after X removes unmentioned users. Direct status and composition rows are
  handled too. Cache keys still include the filter generation and extracted
  content. Quote-only text does not enter the primary-text candidates.
- Download progress says **Downloading…**, layout reset actions say
  **Restore defaults**, and Undo send presents **Off — send immediately** or
  a duration such as **10 seconds**, with an explanatory message.
- The native download factory now uses its current four-argument selector.
  Removed URL-factory and native-tab-sync hooks were retired.

Changes from the previous target:

- Retired six hooks on removed classes: the slideshow ad gate, slideshow heart,
  two slideshow quality actions, duplicate immersive V2 gesture hook, and old
  settings controller. Existing current immersive, media-quality, ad-filtering,
  and generic-settings paths remain.
- Updated the DM attachment class from `DMConversation.MessageAttachmentView`
  to `ChatConversation.MessageAttachmentView`; `layoutSubviews` is present.
- Retargeted guarded sign-in, reply, and diagnostic version checks to 12.24.1.
  Their method/layout checks remain active. Native account and posting flows
  remain the defaults.
- Updated the native Bookmarks carrier used for Likes to the current panel
  factory at `T1Twitter+0x69B0C4`, jump table `+0x1403730`, panel-6 case
  `+0x69B1E0`. UUID `B7626D78-E963-30FF-A7E1-C1281BC7298D` is checked before
  any offset is read, followed by the prologue, dispatch, and case signatures.
  An unknown binary returns no carrier instead of calling an old address.

## Likes layout

`TFSTwitterEntityMedia` exposes `mediaDimensions`/`imageDimensions` as CGSize;
the former width/height lookups did not obtain these dimensions. Tiles now use
this metadata immediately, with video numerator/denominator as a fallback.
Decoded images can still correct incomplete metadata.

Corrections coalesce on a one-shot display link in common run-loop modes,
including active scrolling. UIKit's invalidation-context offset adjustment
anchors the visible item without calling `setContentOffset:` during the
correction. Prepared geometry is reused until it changes. Prefetches and
visible cells use the same pixel-bucket calculation so they can share work.
The display-link target captures the controller weakly.

The scheduling and offset APIs follow Apple's
[CADisplayLink documentation](https://developer.apple.com/documentation/quartzcore/cadisplaylink)
and [layout invalidation context documentation](https://developer.apple.com/documentation/uikit/uicollectionviewlayoutinvalidationcontext).

## Sidebar persistence

Taps and reorders save immediately; leaving through Back no longer discards
the selection. The editor uses Done. Empty selection remains a valid saved
value rather than reverting to defaults.

The runtime observes the source's `ObservableObject` changes and reapplies the
saved selection after a native publication commits. It coalesces updates and
ignores publications from its own setters. Cached hidden rows are refreshed
when X supplies newer rows, preserving current badges and action values when
unhidden. Duplicate/unknown saved IDs are sanitized before ranking. Known icon
names supplement English titles when identifying localized primary rows;
unknown X-owned rows are preserved.

All three native array setters remain exported from XAppLibraries:
`primaryItems` at `0x2CF872C`, `folderItems` at `0x2CF8A7C`, and `tertiaryItems`
at `0x2CF8DCC`. Runtime calls continue resolving their names with `dlsym`;
these addresses are audit evidence, not additional hard-coded calls.

## Validation and package

### Compatibility Sign-in, beta 55

The beta 54 device report records three unsuccessful password commands with
no model payload. The last error is HTTP 404 in
`com.twitter.TFSTwitterAPICommand.error`; earlier statuses were not retained.
There was no account registration or challenge handoff. These facts do not
establish an incorrect password or prove that the route has been removed.

The supplied 12.24.1 binary still builds `xauth_password.json` with URL-base
type 17 (`https://api.twitter.com/auth/1/`). An empty, unauthenticated request
to that exact route on September 13, 2026 returned HTTP 403 and API reason 239
(bad guest token). This verifies a responding route, not credentialed login.
The app's guest manager already acquires and refreshes guest authentication.
`T1OnboardingAuthTokenStorage` delegates to the native shared token store;
allocating this wrapper does not discard the native timeline token.

Beta 55 changes the request candidate by supplying the fresh JSON verification
result from X's existing ephemeral `js_inst` collector. Beta 54 always discarded
this value to reproduce an older X 12.9 workaround. Empty, malformed, non-object
or oversized results remain nil, and the 12-second minimum preflight is retained
to isolate the request change. This is an experiment requiring device validation;
metrics changes did not resolve all earlier X 12.9 failures either. Neither
native onboarding nor a browser session establishes working native account
credentials on its own.

Error handling now distinguishes 404/410 request failures, 429 rate limits,
5xx service failures and network errors. The native command's
`APICommandErrorFromAPIResponse:` stores the API reason separately under
`TFSTwitterAPICommandError.apiErrorCode`; reports include only that bounded
integer (-1 means unavailable) and whether the last command used valid metrics.
Raw error dictionaries, messages, credentials, metrics and account data are
not exported. Duplicate command callbacks cannot register an account twice,
and starting a new attempt clears the previous failure category.

Native regression coverage uses the production metrics validator, numeric API
reason reader and error classifier with synthetic input. Device acceptance is
still required: attempt Compatibility Sign-in once, complete any challenge,
verify the account opens and survives relaunch, or share the resulting report
if rejected. No working-login claim is made by this patch.

The corrected local hook audit and source checks passed. Executable regression
checks cover sidebar republication/Grok Bot, eager/lazy Home ownership,
canonical leading mentions, mention entities, changing cached text, quoted
post isolation, filter removal, and every Likes destination mapping. The
beta 52 macOS build and these native checks are tracked in
[Actions](https://github.com/Vicitiniman/NeoFreeBirdReborn/actions/runs/34293645854)
for source commit `a1efbfb`.

The local packager validates the input hash, injected library dependencies and
Mach-O layouts, unchanged instruction sections, ZIP CRCs, and bundle resources.
Its output is unsigned and requires the user's normal sideload signer.

The supplied beta 51 device report confirms X 12.24.1/iOS 18.7.2 and the old
Activity History wrapper. Filters were cleared before that report, so zero
filter counters cannot identify an observed match failure. The beta 52 report confirms the current Likes page remap was applied and
shows the Grok promotion issue addressed above. No beta 53 device execution
is claimed. The remaining acceptance checks are:

- Pick each Likes destination, return via Back, and verify Posts shows it.
- In Edit navigation bar, hide Try Grok Bot and fully reopen X. Test both
  visibility choices across another relaunch.
- Open two different profiles, switch between Photos and Videos, scroll past
  the first page, refresh, pinch columns, view media and return. Verify the
  header and Follow action, native empty/error states, and no mixed accounts.
- Add `grok` to either For You filter and check explicit @grok posts disappear;
  switch to Following and verify it stays unfiltered. Keep filters enabled if
  exporting a report to diagnose a remaining failure.
- Download a photo, GIF, and video; inspect the progress and restore/Undo labels.

Reproduce the inventory with Python 3.11+ and `lief` installed:

```sh
python tools/audit_ipa_hooks.py /path/to/input.ipa --output docs/X12_24_1_HOOK_AUDIT.json
```

For local packaging, install `lief` and Pillow, download the **sideload-payload**
Actions artifact, and supply an authorized arm64 substrate-compatible runtime:

```sh
python tools/package_local_ipa.py /path/to/input.ipa /path/to/NeoFreeBird-sideload-payload.zip --substrate /path/to/libsubstrate.dylib --output /path/to/NeoFreeBird.ipa
```

The original 12.9 investigation is retained in
[X12_9_FEATURE_AUDIT.md](X12_9_FEATURE_AUDIT.md) as historical reference.
