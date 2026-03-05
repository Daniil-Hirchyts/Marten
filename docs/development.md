# Development

## Requirements

- macOS 26 or later for the desktop application and host-side Swift package builds.
- An Xcode toolchain with the required Apple platform SDKs.
- iOS 26 and watchOS 26 SDKs/runtimes for the corresponding application hosts and extensions.
- Apple signing capabilities and a configured iCloud container for CloudKit integrations.

The package manifests declare Swift tools version 5.9. The source uses Apple platform APIs introduced in the 26-generation SDKs.

## Swift packages

The repository contains three packages with local dependencies:

```bash
swift build --package-path MartenCore
swift build --package-path MartenMac
swift build --package-path MartenIOS
```

The macOS package also exposes a development executable:

```bash
swift run --package-path MartenMac MartenMac
```

The SwiftPM runner is useful for desktop development. Signed application hosts are needed for capabilities such as iCloud, app groups and system extensions.

## Xcode hosts

`Marten.xcworkspace` references the macOS and iOS wrapper projects. This Git snapshot includes the workspace, wrapper source, assets, property lists and entitlements; the `.xcodeproj` bundles themselves are excluded by the repository's `.gitignore`.

For a fresh checkout, build the Swift packages directly or create local Xcode application and extension hosts using the supplied wrapper source. Add the local packages to those hosts and configure their signing and capabilities. A machine with the local wrapper projects already configured can open `Marten.xcworkspace`.

The macOS host consumes `MartenMacServices` and `MartenCore`. The iOS hosts consume `MartenIOSApp` and `MartenCore`; the watch host consumes `MartenWatchApp`.

## Capabilities and permissions

| Capability | Purpose |
| --- | --- |
| Accessibility | Paste automation and the global hotkey event tap |
| Input Monitoring | Global keyboard interaction |
| Screen Recording | Optional screen-region OCR capture |
| iCloud / CloudKit | Private and shared record synchronisation |
| App groups | Shared storage for iOS application and extension targets |
| Local authentication | Unlocking protected pinboard views |
| Speech / microphone | Optional iOS voice input, where enabled |

The supplied entitlement files document the project's container and app-group configuration. Configure identifiers and signing for the developer account used to run the hosts.

## Tests

```bash
swift test --package-path MartenCore
swift test --package-path MartenMac
swift test --package-path MartenIOS
```

The packages include unit tests for persistence, searching, representations, assets, pinboards, sync, paste behaviour, UI state and extension integrations. Platform-dependent tests require the corresponding Apple SDK or host environment.
