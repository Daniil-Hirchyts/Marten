# Setup

## Build a signed macOS app (required for iCloud Sync)

CloudKit requires a signed `.app` with the correct entitlements. If you run the mac app unsigned (for example via `swift run`), the app will show iCloud Sync as unavailable.

1. Open `ClipboardMacWrapper/ClipboardMacWrapper.xcodeproj` in Xcode.
2. Select the `ClipboardMacWrapper` target.
3. In **Signing & Capabilities**:
   - Choose your Team.
   - Set a bundle identifier you own.
   - Add the **iCloud** capability, enable **CloudKit**, and select/create a container (e.g. `iCloud.com.yourcompany.paste`).
   - Add the **Push Notifications** capability (CloudKit zone subscriptions deliver remote notifications).
4. If your container ID is different, update it in `ClipboardCore/Sources/Sync/CloudKitConfiguration.swift`.
5. Build & Run in Xcode (this produces a signed `.app` with entitlements).
