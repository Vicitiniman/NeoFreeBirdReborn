# NeoFreeBird

[![Build NeoFreeBird](https://github.com/Vicitiniman/NeoFreeBirdReborn/actions/workflows/build.yml/badge.svg)](https://github.com/Vicitiniman/NeoFreeBirdReborn/actions/workflows/build.yml)

NeoFreeBird is a modular enhancement tweak for X 12.24.1. It restores familiar
Twitter branding and adds themes, navigation controls, media tools, timeline
filters, and guarded compatibility options for modified installations.

> **Beta software:** NeoFreeBird is built for X 12.24.1 build 1. Other X
> versions may not be compatible.

NeoFreeBird does not include or distribute the X app. Sideloaded and TrollStore
builds require a decrypted X 12.24.1 IPA that you are legally authorized to use.

## Compatibility

Beta 55 updates Compatibility Sign-in to send validated verification data
from X instead of discarding it. Reports distinguish the HTTP status from
X's numeric error reason; request failures, rate limits and service failures
now have separate messages. Successful login on a device remains unverified.

Beta 54 corrects the profile waterfall's alignment below the header, adds
**Profiles > Default to Photos**, and removes the blank sidebar editor tile.
The profile keeps its native header, Follow action, loading and access states.
**Hide Try Grok Bot** now lives in **Edit navigation bar** and targets the
separate sidebar promotion in X 12.24.1. Reopen X after changing this switch.
Earlier Likes navigation, scrolling, filtering, download-label and sidebar
persistence fixes remain included.
See the [12.24.1 audit](docs/X12_24_1_FEATURE_AUDIT.md) for the static checks and
the remaining device validation.


| Component | Supported target |
| --- | --- |
| Host app | X 12.24.1 |
| Audited build | X 12.24.1 build 1 |
| Minimum iOS | iOS 15.0 |
| Architecture | arm64 |
| Packages | Sideloaded IPA, TrollStore TIPA, rootless DEB, rootful DEB |

NeoFreeBird checks version-specific app interfaces before using them. Missing
capabilities are recorded in the compatibility report, and native behavior is
preserved where possible.

## Features

### Appearance and navigation

- Nine coordinated presets, including Apollo-inspired blue, Classic Twitter,
  Midnight OLED, and Native X Blue.
- A visual theme builder with separate light and dark palettes, live previews,
  contrast checks, exact color entry, and a personal theme library.
- Theming across supported timelines, tweet details, settings, navigation
  chrome, and the custom Likes experience.
- Reorderable bottom navigation and sidebar items, including an independent
  **Likes** destination with normal navigation and swipe-back.
- Twitter bird branding for the Home title, compatible iPad rail, classic
  launch animation, display name, and alternate app icon.

### Timeline, Likes, and media

- Layered promoted-content filtering across timelines, profiles, search,
  Explore, cards, articles, and supported video paths.
- Separate **For You** filters for accounts/`@mentions` and post text. Account
  entries also catch matching handles mentioned in a post; Following is never
  filtered by either list.
- A Posts/Media selector in Likes with an adaptive, pinch-adjustable waterfall
  that respects each item's aspect ratio.
- The same waterfall and media viewer in profile Photos/Videos tabs, enabled
  under **Profiles > Profile media waterfall**. Each native profile feed stays
  separate; pull to refresh or continue scrolling to load older media.
- **Default to Photos** puts Photos first in the profile media menu while
  keeping Videos available. Enabled by default; applies to newly opened profiles.
- Full-window photo and video viewing on iPhone and iPad, original-quality
  photos, highest-available MP4 playback, zoom, paging, and swipe-down dismiss.
- Native-style photo, video, and GIF menus with configurable download and share
  actions.
- Coalesced and downsampled image loading to reduce duplicate work and memory
  pressure, especially on iPad.

### Settings and portability

- Organized settings with global search that opens or highlights the matching
  setting and supported nested editors.
- Exportable preference profiles for validated NeoFreeBird settings, layouts,
  keyword filters, and personal themes.
- Runtime compatibility reports for device-specific troubleshooting.

Profiles never include X accounts, credentials, cookies, cached media, or
compatibility-reply session data.

## Account compatibility

Native X sign-in, posting, and replies remain the defaults. Compatibility
Sign-in and the optional web reply composer are available as guarded fallback
paths. The app's own services retain account registration and credential
storage. Updating the host app does not guarantee that X's servers will accept
requests from every sideloaded installation.

The 12.24.1 update verifies the required native selectors and retains their
runtime signature checks. Detailed reply diagnostics remain opt-in and use
the existing bounded capture and expiry rules.

## Where to find things

| Feature | Location |
| --- | --- |
| Themes and theme builder | **Settings > NeoFreeBird > Appearance > Themes** |
| Preference profiles | **Settings > NeoFreeBird > Backup & restore** |
| Compatibility report | **Settings > NeoFreeBird > Debug** |
| Signed-out report | **X login screen > Share Report** |

## Build and install

Choose the package for your installation method:

| Method | Output |
| --- | --- |
| Sideloading | `.ipa` |
| TrollStore | `.tipa` |
| Rootless jailbreak | `.deb` |
| Rootful jailbreak | `.deb` |

Avoid injecting multiple X/Twitter tweaks into the same app. Overlapping hooks
can cause startup crashes and inconsistent behavior.

### GitHub Actions

Open **Actions > Build NeoFreeBird > Run workflow**, select the deployment
format, and optionally choose a commit. Sideloaded and TrollStore builds also
need a direct URL to a decrypted X 12.24.1 IPA.
Download the package from the completed run's **Artifacts** section.
The **sideload-payload** format compiles the injected libraries and resources
without uploading an IPA. It is a payload ZIP, not an installable app; combine
it with the audited local IPA using `tools/package_local_ipa.py`.

### Local build

Requirements:

- [Theos](https://github.com/theos/theos) with an iOS 16.5 SDK
- GNU Make, `dpkg`, `ldid`, and Python 3
- [cyan](https://github.com/asdfzxcvbn/pyzule-rw) for IPA/TrollStore output
- A legally obtained decrypted X 12.24.1 IPA for IPA/TrollStore builds

```bash
git clone --recursive https://github.com/Vicitiniman/NeoFreeBirdReborn.git
cd NeoFreeBirdReborn
chmod +x build.sh rebrand.sh deps/ffmpeg-kit-next/build-ffmpeg.sh
```

For a sideloaded or TrollStore build, place the IPA at:

```text
packages/com.atebits.Tweetie2.ipa
```

Then run one build command:

```bash
./build.sh --sideloaded
./build.sh --trollstore
./build.sh --rootless
./build.sh --rootfull
```

The first build takes longer because the FFmpeg stack is compiled and cached.
macOS uses `sips` for alternate-icon sizing; Linux IPA builds require
ImageMagick's `magick` or `convert` command.

## Troubleshooting

First confirm that the host app is X 12.24.1 and remove any other injected
X/Twitter tweak.

To export a report while signed out:

1. On X's login screen, tap **Share Report** beneath
   **Compatibility Sign-in**.
2. Save the generated JSON.

If X's guarded compatibility service is unavailable, its error alert includes a
**Share Report** action.

After signing in, use **Settings > NeoFreeBird > Debug > Export compatibility
report**. A copy is also stored inside the app container at:

```text
Library/Caches/BHTwitter-X12.24.1-Compatibility.json
```

For startup crashes, also attach the newest `.ips` report and include the
NeoFreeBird version, X version/build, iOS version, device model, installation
method, and reproduction steps.

## Privacy and safety

- NeoFreeBird does not bypass app attestation or spoof subscriptions.
- It does not save or log passwords, cookies, session tokens, or account data.
- Reports exclude credentials, account identifiers, post/reply text, raw URLs,
  response bodies, and web-session contents.
- Optional web-reply account labels are user-provided, local only, and never
  included in reports or shared preference profiles.
- Compatibility sign-in clears its password field before contacting X and
  delegates successful account storage entirely to X's account service.
- Missing private methods fall back to native behavior or a visible unavailable
  state.

## Contributing

Pull requests and device reports are welcome. Guard private classes and
selectors, preserve native behavior when a capability is unavailable, keep
sensitive data out of diagnostics, and never commit decrypted IPAs or generated
FFmpeg libraries.

Check formatting before opening a pull request:

```bash
./format.sh --check
```

Current implementation notes are in
[`docs/X12_24_1_FEATURE_AUDIT.md`](docs/X12_24_1_FEATURE_AUDIT.md), with the
earlier 12.9 investigation retained as historical reference.

## Credits

NeoFreeBird builds on
[BHTwitter](https://github.com/BandarHL/BHTwitter), NeoFreeBird contributors,
Theacrat's and Orion's NeoFreeBird work,
[FLEX](https://github.com/FLEXTool/FLEX),
[zxPluginsInject](https://github.com/asdfzxcvbn/zxPluginsInject), and
[ffmpeg-kit-next](https://github.com/arthenica/ffmpeg-kit-next).

NeoFreeBird is an independent community project and is not affiliated with,
endorsed by, or sponsored by X Corp., Twitter, or Apple.
