<div align="center">

<img src="MartenMacWrapper/MartenMacWrapper/Assets.xcassets/Alpha.appiconset/AppIcon-256.png" alt="Marten icon" width="96"/>

# Marten

A native clipboard workspace for the Apple ecosystem: remember what you copied, find it instantly,
organise it into pinboards and bring it back to the app where you need it.

[Overview](#overview) · [Demo](#demo) · [What it shows](#what-this-project-shows) · [Workflow](#the-workflow) · [Engineering decisions](#engineering-decisions) · [Architecture](#architecture) · [Development](#development)

</div>

## Overview

Marten was built around a daily problem: useful clipboard content disappeared as soon as something else was copied.
The macOS application kept a searchable history and a keyboard-driven overlay, while pinboards turned frequently
used clips into reusable collections.

The implementation preserved different clipboard representations instead of reducing everything to a string.
Text, rich text, images, files, URLs, code and colours could share the same storage and synchronisation model,
with content-specific cards and editors in the interface.

The project also included an iOS application, share and action extensions, a custom keyboard, widgets, Shortcuts
actions and a watchOS companion. The shared Swift package contained the data model, item operations, asset storage
and CloudKit synchronisation used by the platform hosts.

## Demo

Every image and clip below comes from the running app with synthetic sample clips in an isolated local store.
None of it is a mock-up. [How the media was captured](docs/demo/README.md).

### macOS

![Marten clipboard history with file, image, formatted text, colour, link and code cards](docs/screenshots/macos-history-content-types.jpg)

The main overlay keeps copied content in one place. Each card is drawn for its content type: a file, image,
formatted text, colour, link or code. Pinboard tabs switch between reusable collections.

<p align="center">
  <a href="docs/demo/native-workflow.mp4"><img src="docs/demo/native-workflow.gif" alt="Real Marten capture: browse history, open the Work pinboard and search for Sprint" width="360"/></a>
</p>

<p align="center"><a href="docs/demo/native-workflow.mp4">Watch the macOS demo</a>: browse <b>All Items</b>, open <b>Work</b>, type <b>Sprint</b>.</p>

#### Layouts and selection

The overlay can sit on the bottom or top edge (horizontal), on the left or right edge (vertical), or open as a
compact panel at the cursor.

| Vertical edge layout | Multiple selection | Compact pinboard | Compact search |
| :---: | :---: | :---: | :---: |
| [<img src="docs/screenshots/macos-vertical-history.jpg" alt="Marten vertical history list on the left screen edge" width="190"/>](docs/screenshots/macos-vertical-history.jpg) | [<img src="docs/screenshots/macos-multiple-selection.jpg" alt="Two clips selected as a range in the vertical list" width="190"/>](docs/screenshots/macos-multiple-selection.jpg) | [<img src="docs/screenshots/macos-compact-pinboard.jpg" alt="Compact overlay showing the Work pinboard" width="190"/>](docs/screenshots/macos-compact-pinboard.jpg) | [<img src="docs/screenshots/macos-compact-search.jpg" alt="Compact overlay filtered by the Sprint search" width="190"/>](docs/screenshots/macos-compact-search.jpg) |
| Full-height list on the left edge | Shift + ↓ extends a range selection | A pinboard in the cursor panel | Live filtering in the cursor panel |

#### Content-specific editors

| Rich text | Code | Image | Colour | Link |
| :---: | :---: | :---: | :---: | :---: |
| [<img src="docs/screenshots/macos-rich-text-editor.jpg" alt="Rich-text editor with formatting toolbar" width="160"/>](docs/screenshots/macos-rich-text-editor.jpg) | [<img src="docs/screenshots/macos-code-editor.jpg" alt="Monospaced code editor" width="160"/>](docs/screenshots/macos-code-editor.jpg) | [<img src="docs/screenshots/macos-image-editor.jpg" alt="Image editor with rotate, copy and export controls" width="160"/>](docs/screenshots/macos-image-editor.jpg) | [<img src="docs/screenshots/macos-color-editor.jpg" alt="Colour editor showing #6366F1 with RGB values" width="160"/>](docs/screenshots/macos-color-editor.jpg) | [<img src="docs/screenshots/macos-url-editor.jpg" alt="Link editor" width="160"/>](docs/screenshots/macos-url-editor.jpg) |
| Bold, italic, underline, strikethrough, fonts | Monospaced, with counts | Rotate, flip, copy, export | Swatch, RGB, hex validation | Editable URL |

More macOS captures: [horizontal history](docs/screenshots/macos-history.jpg) ·
[Work pinboard](docs/screenshots/macos-pinboard.jpg) · [search](docs/screenshots/macos-search.jpg) ·
[compact history](docs/screenshots/macos-compact-history.jpg).

### iOS

<p align="center">
  <a href="docs/demo/ios-workflow.mp4"><img src="docs/demo/ios-workflow.gif" alt="Real Marten iPhone recording: copy a clip, search for Sprint, switch to the Design pinboard" width="260"/></a>
</p>

<p align="center"><a href="docs/demo/ios-workflow.mp4">Watch the iPhone demo</a>: tap a clip to copy it (it moves to the top), search
for <b>Sprint</b>, then switch to the <b>Design</b> pinboard.</p>

| Library | Work pinboard | Pinboard picker | Search |
| :---: | :---: | :---: | :---: |
| [<img src="docs/screenshots/ios-home.png" alt="iPhone library with seven clips across pinboards" width="180"/>](docs/screenshots/ios-home.png) | [<img src="docs/screenshots/ios-work.png" alt="Work pinboard with four clips" width="180"/>](docs/screenshots/ios-work.png) | [<img src="docs/screenshots/ios-pinboards.png" alt="Pinboard picker sheet: All, Work, Design, Learning" width="180"/>](docs/screenshots/ios-pinboards.png) | [<img src="docs/screenshots/ios-search.png" alt="Search for Sprint showing two matching clips" width="180"/>](docs/screenshots/ios-search.png) |
| **New pinboard** | **Quick Add** | **Search filters** | **Design pinboard** |
| [<img src="docs/screenshots/ios-new-pinboard.png" alt="New pinboard sheet with colours and emoji" width="180"/>](docs/screenshots/ios-new-pinboard.png) | [<img src="docs/screenshots/ios-quick-add.png" alt="Quick Add sheet: New Text, Paste, Scan" width="180"/>](docs/screenshots/ios-quick-add.png) | [<img src="docs/screenshots/ios-filters.png" alt="Search filters by date and content type" width="180"/>](docs/screenshots/ios-filters.png) | [<img src="docs/screenshots/ios-design.png" alt="Design pinboard with image and colour clips" width="180"/>](docs/screenshots/ios-design.png) |

The iPhone app also has its own preview and edit screens for each content type:

| Text preview | Rich-text editor | Code preview | Code editor | Image editor | Colour editor |
| :---: | :---: | :---: | :---: | :---: | :---: |
| [<img src="docs/screenshots/ios-text.png" alt="Text clip preview" width="120"/>](docs/screenshots/ios-text.png) | [<img src="docs/screenshots/ios-rich-text.png" alt="Rich-text edit screen" width="120"/>](docs/screenshots/ios-rich-text.png) | [<img src="docs/screenshots/ios-code.png" alt="Code preview with syntax colouring" width="120"/>](docs/screenshots/ios-code.png) | [<img src="docs/screenshots/ios-code-edit.png" alt="Code edit screen" width="120"/>](docs/screenshots/ios-code-edit.png) | [<img src="docs/screenshots/ios-image.png" alt="Image edit screen with rotate and flip" width="120"/>](docs/screenshots/ios-image.png) | [<img src="docs/screenshots/ios-color.png" alt="Colour edit screen for #6366F1" width="120"/>](docs/screenshots/ios-color.png) |

### watchOS

<p align="center">
  <a href="docs/demo/watchos-navigation.mp4"><img src="docs/demo/watchos-navigation.gif" alt="Real Apple Watch recording: open the Work pinboard and return" width="180"/></a>
</p>

<p align="center"><a href="docs/demo/watchos-navigation.mp4">Watch the short Apple Watch clip</a>: open <b>Work</b> from the pinboard list and go back.</p>

| Pinboards | Work clips | Text preview | Colour preview | Move to pinboard |
| :---: | :---: | :---: | :---: | :---: |
| [<img src="docs/screenshots/watchos-pinboards.png" alt="Watch pinboard list: All, Work, Design" width="140"/>](docs/screenshots/watchos-pinboards.png) | [<img src="docs/screenshots/watchos-work.png" alt="Watch Work pinboard clips with add button" width="140"/>](docs/screenshots/watchos-work.png) | [<img src="docs/screenshots/watchos-text-preview.png" alt="Watch preview of the Sprint checklist" width="140"/>](docs/screenshots/watchos-text-preview.png) | [<img src="docs/screenshots/watchos-color-preview.png" alt="Watch colour preview for #6366F1" width="140"/>](docs/screenshots/watchos-color-preview.png) | [<img src="docs/screenshots/watchos-move.png" alt="Watch move sheet listing Work, Design, Learning" width="140"/>](docs/screenshots/watchos-move.png) |

### What the media does and does not demonstrate

**Shown running:** macOS history, pinboards, search, layouts, range selection and editors. iOS library,
pinboards, search, filters, Quick Add, pinboard creation, copy on tap, and the preview and edit screens.
watchOS pinboards, clip lists, previews and the move sheet.

**Described from source only, not shown running:** CloudKit sync and sharing, phone and watch sync, paste
into another app, OCR, Apple Intelligence text tools, and the iOS keyboard, share and action extensions,
widgets and Shortcuts.

## What this project shows

- **A native clipboard workflow.** Menu-bar access, a global shortcut, keyboard navigation, quick-paste actions,
  plain-text pasting and a paste stack connected history browsing to the active application.
- **Content-aware history.** The model retained multiple representations per clip, with dedicated text, rich-text,
  link, image, file, code and colour handling. Source-app metadata and thumbnails supported scanning the history.
- **Reusable pinboards.** Named and coloured collections organised clips around a task or context. Protected
  pinboards used local authentication and a configurable unlock duration.
- **Local persistence and explicit sync.** Core Data stored the local model, while file-backed asset storage kept
  larger payloads outside the relational records. Separate inbound and outbound CloudKit engines handled changes,
  assets, retries, conflict resolution and sharing.
- **Privacy controls inside the product.** Ignored applications, confidential/transient-content filtering,
  configurable history retention and screen-sharing visibility let the user control capture behaviour.
- **Apple platform integrations.** The iOS hosts exposed share/action extensions, keyboard insertion, widgets and
  App Intents. WatchConnectivity connected the phone and watch experiences.
- **Optional system intelligence.** Vision supported screen-region OCR. Foundation Models supplied on-device
  summarising, proofreading, rewriting and shortening when Apple Intelligence was available.

## The workflow

```mermaid
flowchart LR
    C[Copy content<br/>text, image, link or file] --> F[Apply capture filters<br/>source app and content rules]
    F --> N[Normalise representations<br/>classify and hash the payload]
    N --> L[Store locally<br/>Core Data and file-backed assets]
    L --> O[Open the native overlay<br/>search, preview and select]
    O --> P[Organise into pinboards<br/>edit or reuse a clip]
    P --> A[Paste or drag content<br/>into the destination app]
    L --> S[Optional CloudKit sync<br/>other devices and shared pinboards]
```

The default macOS shortcut was **Command + Shift + V**. **Command + Shift + O** opened OCR capture, and
**Command + 1–9** were the default quick-paste bindings. Shortcuts could be changed in settings.

## Engineering decisions

| Decision | Why |
| --- | --- |
| Preserve representations alongside an item's semantic type | A rich-text, image or file clip needed more information than its searchable text preview |
| Separate persistence from asset storage | Binary payloads and thumbnails could be managed without expanding every Core Data record |
| Share domain code through `MartenCore` | The platform hosts used the same model, business rules and sync behaviour |
| Keep macOS services separate from the overlay UI | Pasteboard monitoring, hotkeys, paste automation and OCR could be tested and evolved independently |
| Use separate inbound and outbound sync engines | Record mapping, history processing, retries, downloaded assets and conflicts had explicit responsibilities |
| Route private and shared CloudKit data separately | Personal history and shared pinboards used distinct sync paths and permission rules |
| Express capture and paste operations through coordinators and protocols | The app could connect real system services while tests supplied controlled dependencies |
| Check system capabilities before enabling integrations | CloudKit, local authentication, OCR and Apple Intelligence depended on the host's entitlements, permissions and availability |

Implementation: [clipboard monitoring](MartenMac/Sources/MartenMacServices/Services/PasteboardMonitor/),
[item operations](MartenCore/Sources/BusinessRules/), [persistence](MartenCore/Sources/Persistence/) and
[synchronisation](MartenCore/Sources/Sync/).

## Architecture

```mermaid
flowchart TB
    MAC[macOS host<br/>SwiftUI overlay and settings, AppKit integration]
    SERVICES[MartenMacServices<br/>capture, hotkeys, paste and OCR]
    IOS[iOS host and extensions<br/>share, actions, keyboard, widgets and Shortcuts]
    WATCH[watchOS companion<br/>recent content and pinboards]
    CORE[MartenCore<br/>models, business rules and synchronisation]
    DB[(Core Data<br/>local persistent store)]
    ASSETS[File-backed assets<br/>images, files and thumbnails]
    CLOUD[CloudKit<br/>private and shared data]

    MAC --> SERVICES
    MAC --> CORE
    SERVICES --> CORE
    IOS --> CORE
    IOS <-->|WatchConnectivity| WATCH
    WATCH --> CORE
    CORE --> DB
    CORE --> ASSETS
    CORE <-->|change records and assets| CLOUD
```

**Stack:** Swift, SwiftUI, AppKit and UIKit · Core Data, CloudKit, App Groups and WatchConnectivity · Vision,
LocalAuthentication, App Intents, WidgetKit and Foundation Models · Swift Package Manager and Xcode.

### Platform scope

| Platform | Implementation |
| --- | --- |
| **macOS** | Clipboard monitoring, overlay, pinboards, editors, paste workflow, settings and OCR integration |
| **iOS** | Library and editors, shared storage, share/action extensions, custom keyboard, widgets and Shortcuts |
| **watchOS** | Companion views and phone/watch content updates |

The package deployment targets were **macOS 26, iOS 26 and watchOS 26**. CloudKit required a signed host with the
corresponding capabilities and an iCloud account. Apple Intelligence features depended on device and model
availability. iOS used its app and extension entry points rather than macOS-style continuous background capture.

## Development

The Swift packages used local dependencies:

```bash
swift build --package-path MartenCore
swift build --package-path MartenMac
swift run --package-path MartenMac MartenMac
```

The macOS application requested Accessibility and Input Monitoring for its global keyboard and paste workflow.
Screen Recording was an additional permission for OCR capture.

The [development guide](docs/development.md) covers the package targets, Xcode-host setup, capabilities and test
commands. It also records the validation performed for this presentation, including the existing core-test failure.

**Validation:** the native macOS host built successfully. The core suite ran **281 tests: 280 passed and 1 failed**
in the capture environment. The iOS and watchOS media came from documentation-only capture hosts. These were built
from the repository packages with Xcode 27.2 and run on iOS 27.0 and watchOS 27.0 simulators with CloudKit
disabled. Repository application code was left unchanged. See the [development guide](docs/development.md#validation-performed-for-this-presentation).

## Repository layout

| Path | Contents |
| --- | --- |
| [`MartenCore/`](MartenCore/) | Shared model, persistence, item operations, assets, sync and core tests |
| [`MartenMac/`](MartenMac/) | macOS application, native services, overlay, editors, settings and tests |
| [`MartenIOS/`](MartenIOS/) | iOS and watchOS app modules, views, services and integration logic |
| [`MartenMacWrapper/`](MartenMacWrapper/) | Desktop host source, entitlements and app assets |
| [`MartenIOSWrapper/`](MartenIOSWrapper/) | iOS, watchOS, keyboard, share, action and widget host source |
| [`Marten.xcworkspace`](Marten.xcworkspace/) | Workspace references for locally configured Xcode hosts |
| [`docs/`](docs/) | Native macOS, iOS and watchOS captures, demo recordings and development notes |

## Author

[Daniil Hirchyts](https://github.com/Daniil-Hirchyts).
