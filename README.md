<div align="center">

<img src="docs/assets/marten-icon.png" alt="Marten icon" width="96"/>

# Marten

Clipboard history and pinboards for macOS, iOS and watchOS.

</div>

Marten records what you copy on the Mac and keeps it searchable from a keyboard-driven overlay. Clips you
want to keep go into pinboards. History and pinboards sync through iCloud to the iPhone and Apple Watch apps.

Requires macOS 26, iOS 26 or watchOS 26.

## macOS

![Clipboard history with file, image, rich-text, colour, link and code clips](docs/screenshots/macos-history-content-types.jpg)

<p align="center">
  <a href="docs/demo/native-workflow.mp4"><img src="docs/demo/native-workflow.gif" alt="Browse history, open the Work pinboard and search for Sprint" width="360"/></a>
</p>

| Vertical layout | Compact panel | Rich-text editor |
| :---: | :---: | :---: |
| [<img src="docs/screenshots/macos-vertical-history.jpg" alt="History list on the left screen edge" width="200"/>](docs/screenshots/macos-vertical-history.jpg) | [<img src="docs/screenshots/macos-compact-search.jpg" alt="Compact panel filtered by search" width="200"/>](docs/screenshots/macos-compact-search.jpg) | [<img src="docs/screenshots/macos-rich-text-editor.jpg" alt="Rich-text editor with formatting toolbar" width="280"/>](docs/screenshots/macos-rich-text-editor.jpg) |

- **⌘⇧V** opens the overlay. It docks to any screen edge or opens as a compact panel at the cursor.
- Type to search. Filter by date, content type or source app.
- Paste into the frontmost app, paste as plain text, or drag a clip out. **⌘1–⌘9** paste the first nine
  clips. Select several clips to paste them in order.
- Edit a clip before pasting it, with editors for text, rich text, code, images, colours and links.
- **⌘⇧O** captures text from a screen region using Vision OCR.
- Clips from ignored apps aren't recorded, and neither are private keys, API keys, card numbers or one-time
  codes. History is pruned after a configurable period.
- Pinboards can be locked and opened with Touch ID or the Mac password.

## iOS

<p align="center">
  <a href="docs/demo/ios-workflow.mp4"><img src="docs/demo/ios-workflow.gif" alt="Copy a clip, search for Sprint and switch to the Design pinboard" width="260"/></a>
</p>

| Library | Quick Add | Search filters | Image editor |
| :---: | :---: | :---: | :---: |
| [<img src="docs/screenshots/ios-home.png" alt="Library with clips from several pinboards" width="180"/>](docs/screenshots/ios-home.png) | [<img src="docs/screenshots/ios-quick-add.png" alt="Quick Add: New Text, Paste, Scan" width="180"/>](docs/screenshots/ios-quick-add.png) | [<img src="docs/screenshots/ios-filters.png" alt="Search filters by date and content type" width="180"/>](docs/screenshots/ios-filters.png) | [<img src="docs/screenshots/ios-image.png" alt="Image editor with rotate and flip" width="180"/>](docs/screenshots/ios-image.png) |

- Tap a clip to copy it. Search, filter and edit work as on the Mac.
- Add clips from the share sheet, the action extension, Shortcuts, or Quick Add (new text, paste, document
  scan).
- The Marten keyboard inserts clips into any text field.
- Widgets show pinboards on the Home Screen and the latest clip on the Lock Screen.
- Pinboards can be shared with other iCloud users.

## watchOS

| Pinboards | Clip preview | Move to pinboard |
| :---: | :---: | :---: |
| [<img src="docs/screenshots/watchos-pinboards.png" alt="Pinboard list" width="150"/>](docs/screenshots/watchos-pinboards.png) | [<img src="docs/screenshots/watchos-text-preview.png" alt="Preview of a checklist clip" width="150"/>](docs/screenshots/watchos-text-preview.png) | [<img src="docs/screenshots/watchos-move.png" alt="Move sheet listing pinboards" width="150"/>](docs/screenshots/watchos-move.png) |

The watch app shows pinboards and their clips. You can preview a clip, move it to another pinboard, or add a
text clip.

## How it works

```mermaid
flowchart LR
    PB[Pasteboard change] --> FIL{Ignored app or<br/>sensitive content?}
    FIL -- yes --> DROP[Discard]
    FIL -- no --> CLS[Keep every representation<br/>detect type, SHA-256 dedupe]
    CLS --> STORE[(Core Data<br/>+ asset files)]
    STORE --> UI[Overlay: search, edit,<br/>pin, paste or drag]
    STORE <--> CK[CloudKit]
```

A clip stores every type the source app wrote to the pasteboard, for example RTF, plain text and a file URL,
so pasting it back keeps the original formatting. Marten also assigns a content type (text, rich text, code,
link, image, file, colour or mixed), which picks the clip's card and editor. A SHA-256 hash of the payload
removes duplicates. Images, files and thumbnails are written to an asset directory next to the Core Data
store rather than into the database.

```mermaid
flowchart TB
    subgraph Hosts
        MAC[macOS app]
        IOS[iOS app, keyboard,<br/>share/action extensions, widgets]
        WATCH[watchOS app]
    end
    MACSVC[MartenMacServices<br/>pasteboard, hotkeys, paste, OCR]
    IOSAPP[MartenIOSApp]
    WATCHAPP[MartenWatchApp]
    CORE[MartenCore<br/>model, storage, search, sync]
    CK[(CloudKit<br/>private and shared databases)]

    MAC --> MACSVC --> CORE
    IOS --> IOSAPP --> CORE
    WATCH --> WATCHAPP --> CORE
    CORE <--> CK
    IOSAPP -. WatchConnectivity:<br/>sync and lock-state signals .-> WATCHAPP
```

Each device syncs with CloudKit directly. Separate inbound and outbound engines handle record changes and
assets. For conflicts, pinboard edits go to the latest writer, and a clip keeps its earliest version.
Shared pinboards live in the CloudKit shared database. WatchConnectivity carries no clip data. The phone
uses it to tell the watch that a sync finished, or that a pinboard was locked or unlocked.

Where Apple Intelligence is available, the editors can summarise, proofread, rewrite or shorten text with the
on-device Foundation Models framework.

## Repository layout

| Path | Contents |
| --- | --- |
| [`MartenCore/`](MartenCore/) | Shared Core Data model, asset store, search, item operations, CloudKit sync |
| [`MartenMac/`](MartenMac/) | macOS app UI and `MartenMacServices` (pasteboard monitor, hotkeys, paste engine, OCR) |
| [`MartenIOS/`](MartenIOS/) | `MartenIOSApp` and `MartenWatchApp` modules |
| [`MartenMacWrapper/`](MartenMacWrapper/) | macOS app host: entitlements, Info.plist, icon |
| [`MartenIOSWrapper/`](MartenIOSWrapper/) | iOS, watchOS, keyboard, share, action and widget hosts |

## Building

```bash
swift build --package-path MartenCore
swift run --package-path MartenMac MartenMac
```

The macOS app needs Accessibility and Input Monitoring for the global shortcut and pasting, plus Screen
Recording for OCR. iCloud sync needs a signed host with the CloudKit and App Group capabilities. The Xcode
projects aren't committed; [docs/development.md](docs/development.md) covers setting up the hosts and running
the tests.

## Author

[Daniil Hirchyts](https://github.com/Daniil-Hirchyts)
