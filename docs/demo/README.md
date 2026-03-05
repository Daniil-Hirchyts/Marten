# How the Marten media was captured

All screenshots and recordings in this repository show the running Marten interface. Nothing is a mock-up,
HTML recreation or generated image. Every clip shown is synthetic sample data in an isolated local store, never
a personal clipboard or iCloud account. Recordly was not used.

## Recordings

| Recording | Platform | What happens | Files |
| --- | --- | --- | --- |
| Native workflow | macOS | Browse **All Items**, open **Work**, type **S → Sp → Spri → Sprint** and watch the history filter | [MP4](native-workflow.mp4) · [GIF](native-workflow.gif) |
| iPhone workflow | iOS 27.0 simulator | Tap a clip to copy it (the "Copied" badge appears and it moves to the top), open search and type **Sprint**, close search, open the pinboard picker and choose **Design** | [MP4](ios-workflow.mp4) · [GIF](ios-workflow.gif) |
| Watch navigation | watchOS 27.0 simulator | Open **Work** from the pinboard list, then go back | [MP4](watchos-navigation.mp4) · [GIF](watchos-navigation.gif) |

**macOS.** The macOS video was built from 43 timestamped app-window captures taken during scripted
Accessibility and keyboard interactions. Playback follows the captured timing.

**iOS and watchOS.** These were recorded continuously with `xcrun simctl io recordVideo`, while real taps and
typed text were sent to the simulator. The only edit was cutting idle gaps between steps; each kept segment
plays at its original speed. The raw iPhone recording ran 98 s and the published cut runs 29 s. The raw watch
recording ran 85 s and the cut runs 16 s. The watch simulator redraws only every few seconds, so its clip is
short and shows navigation only.

## Screenshots

| Platform | Screens |
| --- | --- |
| macOS | [Mixed content history](../screenshots/macos-history-content-types.jpg) · [History](../screenshots/macos-history.jpg) · [Work pinboard](../screenshots/macos-pinboard.jpg) · [Search](../screenshots/macos-search.jpg) · [Vertical layout](../screenshots/macos-vertical-history.jpg) · [Multiple selection](../screenshots/macos-multiple-selection.jpg) · [Compact history](../screenshots/macos-compact-history.jpg) · [Compact pinboard](../screenshots/macos-compact-pinboard.jpg) · [Compact search](../screenshots/macos-compact-search.jpg) · [Rich-text editor](../screenshots/macos-rich-text-editor.jpg) · [Code editor](../screenshots/macos-code-editor.jpg) · [Image editor](../screenshots/macos-image-editor.jpg) · [Colour editor](../screenshots/macos-color-editor.jpg) · [Link editor](../screenshots/macos-url-editor.jpg) |
| iOS | [Library](../screenshots/ios-home.png) · [Work](../screenshots/ios-work.png) · [Design](../screenshots/ios-design.png) · [Pinboard picker](../screenshots/ios-pinboards.png) · [New pinboard](../screenshots/ios-new-pinboard.png) · [Quick Add](../screenshots/ios-quick-add.png) · [Filters](../screenshots/ios-filters.png) · [Search](../screenshots/ios-search.png) · [Text preview](../screenshots/ios-text.png) · [Rich-text editor](../screenshots/ios-rich-text.png) · [Code preview](../screenshots/ios-code.png) · [Code editor](../screenshots/ios-code-edit.png) · [Image editor](../screenshots/ios-image.png) · [Colour editor](../screenshots/ios-color.png) |
| watchOS | [Pinboards](../screenshots/watchos-pinboards.png) · [Work](../screenshots/watchos-work.png) · [Text preview](../screenshots/watchos-text-preview.png) · [Colour preview](../screenshots/watchos-color-preview.png) · [Move to pinboard](../screenshots/watchos-move.png) |

## Capture environment

- **macOS:** the repository's macOS application source, built as a separately identified, sandboxed bundle
  with its own local store and no CloudKit entitlement.
- **iOS and watchOS:** the repository's original Xcode wrapper projects use a WatchKit extension product type
  that Xcode 27 no longer supports. So minimal capture-only host apps were built from copies of the
  repository's Swift packages. Those copies differed from the repository in only a few places:
  - two small compiler-compatibility shims for the newer SDK;
  - CloudKit and watch sync switched off when running in the Simulator, because unsigned hosts can't create a
    CloudKit container;
  - a documentation-only launch hook that opens an existing screen or sheet so some stills could be captured.
    The hook dismisses the integrations onboarding banner through the app's own
    `dismissIntegrationsOnboarding()` call. It does not redraw or replace any view.

  Quick Add, Filters, Search and every step of the iPhone and watch recordings were driven with real simulator
  taps and typing.
- The copies and hooks lived only in a temporary capture workspace. **Application code in this repository is
  unchanged.**

## Not demonstrated

These captures don't show CloudKit sync or sharing, phone and watch synchronisation, pasting into another app,
OCR, Apple Intelligence text tools, or the iOS keyboard, share and action extensions, widgets and Shortcuts.
Those features are documented from the source in the main [README](../../README.md). Build and test results are
recorded in the [development guide](../development.md).
