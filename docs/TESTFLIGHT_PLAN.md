# Marten iOS — TestFlight Beta Plan

## Overview

4-phase beta ramp from internal team to external testers, validating stability, sync reliability, and UX quality at each gate.

---

## Phase 1: Internal Team (Days 1-3)

**Audience:** Core development team (2-3 people)
**Build:** Debug-signed TestFlight with all feature flags enabled

### Test Scenarios
- [ ] Fresh install on iPhone and iPad — onboarding flow
- [ ] Create text, image, code, link, color, and file items
- [ ] Pinboard CRUD: create, rename, reorder, delete
- [ ] Lock/unlock pinboard
- [ ] Search: text query, filter by type/date/app/device
- [ ] Voice dictation search
- [ ] Rich text editing (bold, italic, lists, headers)
- [ ] Context menu actions: copy, share, move, delete
- [ ] Multi-select: batch move, batch delete
- [ ] Drag and drop between pinboards
- [ ] Deep links: `marten://pinboard/<id>`, `marten://item/<id>`

### Go/No-Go Criteria
- Zero crashes in 48 hours of active use
- All CRUD operations succeed
- No data loss or corruption

---

## Phase 2: Sync Validation (Days 4-7)

**Audience:** Internal team, 2+ devices per tester
**Build:** Same as Phase 1

### Test Scenarios
- [ ] Enable iCloud sync on two devices
- [ ] Create item on Device A, verify appears on Device B within 60s
- [ ] Edit item on Device A, verify update propagates
- [ ] Delete item on Device B, verify removed on Device A
- [ ] Airplane mode → create items → reconnect → verify sync recovery
- [ ] Shared pinboard: owner shares, participant accepts via link
- [ ] Shared pinboard: participant adds items, owner sees them
- [ ] Shared pinboard: owner stops sharing, participant loses access
- [ ] Trigger "Sync Now" button, verify status transitions
- [ ] Background → foreground transition resumes sync

### Go/No-Go Criteria
- Sync latency < 60s for all operations
- No duplicate items after conflict resolution
- Shared pinboard accept/leave works end-to-end
- Error messages are user-friendly (not raw error strings)

---

## Phase 3: Extension & Integration Testing (Days 8-12)

**Audience:** Internal team + 5-10 trusted external testers
**Build:** Release-signed TestFlight

### Test Scenarios
- [ ] Share Extension: share text/URL/image from Safari, Notes, Photos
- [ ] Share Extension: target a specific pinboard
- [ ] Keyboard Extension: enable in Settings, verify Full Access prompt
- [ ] Keyboard Extension: browse and insert clips from keyboard
- [ ] Widgets: add Recent Clips widget to Home Screen
- [ ] Widgets: add Quick Access widget to Lock Screen
- [ ] Widgets: tap widget item opens correct item in app
- [ ] Siri Shortcuts: "Search Marten for X", "Create Marten Item"
- [ ] Appearance: switch System/Light/Dark, verify correct rendering
- [ ] Dynamic Type: test at default, large, and accessibility XXL

### Go/No-Go Criteria
- All extensions install and function
- Widget refresh rate acceptable (< 15 min staleness)
- No keyboard extension memory warnings
- Accessibility audit passes (VoiceOver, Dynamic Type)

---

## Phase 4: Open Beta (Days 13-20)

**Audience:** Up to 100 external beta testers
**Build:** Release-signed TestFlight, shared pinboards feature flag ON

### Test Scenarios
- [ ] Full user journey: install → create items → organize → sync → share
- [ ] Battery impact: verify no excessive background activity
- [ ] Storage impact: check app size stays reasonable (< 50MB)
- [ ] Network conditions: test on cellular, Wi-Fi, mixed connectivity
- [ ] Edge cases: very long text items (>10KB), many pinboards (>20)
- [ ] Uninstall and reinstall: verify iCloud data recovery
- [ ] iOS version compatibility (iOS 26.0+)
- [ ] Collect qualitative feedback via TestFlight feedback form

### Go/No-Go Criteria
- Crash-free rate > 99.5%
- No P0 or P1 bugs open
- User feedback sentiment positive (no blocking UX issues)
- App Review guidelines compliance verified
- Privacy manifest validated (no missing API declarations)

---

## Release Decision

After Phase 4 completes with all go/no-go criteria met:

1. Increment version to release candidate
2. Final archive build with production CloudKit container
3. Submit to App Store Connect
4. Complete App Store metadata and screenshots
5. Submit for App Review
