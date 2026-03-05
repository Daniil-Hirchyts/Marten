# Development

## Requirements

- Xcode with the macOS 26, iOS 26 and watchOS 26 SDKs.
- An Apple developer account for signing, CloudKit and App Groups.

## Swift packages

| Package | Products |
| --- | --- |
| `MartenCore` | `MartenCore`: data model, asset store, search, item operations, CloudKit sync |
| `MartenMac` | `MartenMacServices` library and the `MartenMac` executable |
| `MartenIOS` | `MartenIOSApp` and `MartenWatchApp` libraries |

```bash
swift build --package-path MartenCore
swift build --package-path MartenMac
swift build --package-path MartenIOS
swift run --package-path MartenMac MartenMac
```

`swift run` starts the macOS app without a signed host. Sync and anything else that needs entitlements only
works from a signed Xcode host.

## Xcode hosts

`*.xcodeproj` is in `.gitignore`, so the repository has the host sources, Info.plists, entitlements and
assets but not the projects. `Marten.xcworkspace` expects `MartenMacWrapper/MartenMacWrapper.xcodeproj` and
`MartenIOSWrapper/MartenIOSWrapper.xcodeproj`.

To recreate them, add an app target for each host folder, link the local packages, and set your team,
bundle identifiers, iCloud container and App Group:

| Host | Links |
| --- | --- |
| macOS app | `MartenCore`, `MartenMacServices` |
| iOS app, keyboard, share, action and widget extensions | `MartenCore`, `MartenIOSApp` |
| watchOS app | `MartenCore`, `MartenWatchApp` |

The entitlement files use `iCloud.com.hirchyts.marten` and `group.com.hirchyts.marten`. Replace them with
identifiers from your own account.

## Permissions

| Permission | Used for |
| --- | --- |
| Accessibility | Pasting into the frontmost app and the global shortcut event tap |
| Input Monitoring | Global keyboard shortcuts |
| Screen Recording | OCR region capture |
| iCloud (CloudKit) | Sync and shared pinboards |
| App Groups | Storage shared between the iOS app and its extensions |
| Local Authentication | Locked pinboards |

## Tests

```bash
swift test --package-path MartenCore
swift test --package-path MartenMac
swift test --package-path MartenIOS
```

Some tests need the matching platform SDK or a host app.
