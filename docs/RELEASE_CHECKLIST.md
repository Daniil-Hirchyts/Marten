# Marten iOS — Release Checklist

## Pre-Submission

### Tests
- [ ] `swift test --package-path MartenCore` passes (all 30+ tests)
- [ ] `swift test --package-path MartenIOS` passes (all 25+ tests)
- [ ] Performance benchmarks run without regressions

### Builds
- [ ] `xcodebuild -project MartenIOSWrapper/MartenIOSWrapper.xcodeproj -scheme MartenIOSWrapper -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` succeeds
- [ ] Archive build succeeds with valid provisioning profile
- [ ] All 4 targets build: app, keyboard extension, share extension, widgets extension

### Entitlements
- [ ] App Groups entitlement configured for shared container
- [ ] iCloud (CloudKit) entitlement present
- [ ] Push Notifications entitlement present
- [ ] Keyboard extension has RequestsOpenAccess if needed

### Privacy Manifests
- [ ] `MartenIOSWrapper/PrivacyInfo.xcprivacy` present (UserDefaults CA92.1, FileTimestamp C617.1)
- [ ] `MartenKeyboardExtension/PrivacyInfo.xcprivacy` present (UserDefaults CA92.1)
- [ ] `MartenShareExtension/PrivacyInfo.xcprivacy` present (UserDefaults CA92.1)
- [ ] `MartenWidgetsExtension/PrivacyInfo.xcprivacy` present (UserDefaults CA92.1)

### Feature Flags
- [ ] `SharedPinboardsFeatureFlag.isEnabled` set appropriately for release
- [ ] Review all UserDefaults registered defaults for correctness

### Metadata
- [ ] App Store description updated
- [ ] Screenshots prepared for all required device sizes
- [ ] App icon set (1024x1024 + required sizes)
- [ ] Version number and build number incremented
- [ ] What's New text drafted

### Accessibility
- [ ] VoiceOver tested on primary flows (dashboard, pinboard switching, item actions)
- [ ] Dynamic Type tested at largest accessibility size
- [ ] All interactive elements have accessibility labels

### Data & Sync
- [ ] CloudKit schema deployed to production container
- [ ] Conflict resolution tested with multi-device scenarios
- [ ] Shared pinboard accept/leave flow tested
- [ ] Offline-to-online sync recovery verified

## Post-Submission
- [ ] TestFlight build distributed to internal testers
- [ ] Monitor crash reports in first 24 hours
- [ ] Verify CloudKit production data flow
