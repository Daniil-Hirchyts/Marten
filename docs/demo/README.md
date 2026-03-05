# Native macOS walkthrough

[Animated walkthrough](macos-walkthrough.gif) · [MP4 version](macos-walkthrough.mp4)

The GIF and MP4 present a paced sequence of screenshots from Marten's running native macOS host. They show the configuration and first-launch interface. Each screen was captured directly from the app, with no generated interface artwork or simulated controls.

| Position | Screen | What it shows |
| --- | --- | --- |
| 1 | [Welcome](../screenshots/macos-onboarding.jpg) | First-launch introduction |
| 2 | [General](../screenshots/macos-general.jpg) | Startup, plain-text paste, sounds and menu-bar visibility |
| 3 | [Overlay and OCR](../screenshots/macos-overlay-options.jpg) | Overlay placement, capture mode, OCR language and notifications |
| 4 | [Shortcuts](../screenshots/macos-shortcuts.jpg) | Global commands and numbered quick-paste bindings |
| 5 | [Privacy](../screenshots/macos-privacy.jpg) | Screen-sharing visibility and clipboard-content filters |

The capture host used the repository's application source with a separate sandboxed bundle identity, local storage and no CloudKit entitlement. The screenshot files preserve the captured screens; the walkthrough resizes them to fit a consistent frame and holds each screen for readability.

The media covers macOS onboarding and settings. Clipboard-history interactions, device synchronisation, iOS and watchOS are described from the source and are outside this walkthrough's scope. Build and test results are recorded in the [development guide](../development.md).
