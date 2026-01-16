# Validation

This document defines how to validate the app across platforms, versions, and real-world target apps. Validation is ongoing and is not tied to a single implementation phase.

## Release Smoke Test Checklist

- [ ] App launches successfully
- [ ] Copy text Captured
- [ ] Copy image Captured
- [ ] Open overlay (Shift+Cmd+V) Opens
- [ ] Select item Pastes into TextEdit
- [ ] Quick Paste (Cmd+1) Works
- [ ] Search for item Found
- [ ] Create pinboard Saved
- [ ] Move item to pinboard Works
- [ ] Settings open General/Privacy/Shortcuts load
- [ ] Change retention Takes effect
- [ ] Erase history Deletes items
- [ ] Enable iCloud sync Syncs
- [ ] Disable iCloud sync Stops syncing
- [ ] Restart app Data persists
- [ ] Quit and reopen Everything works

## Paste Behaviors Manual Validation

### Target App Matrix

- Notes
- Safari
- Chrome
- Messages
- Mail
- Slack
- Xcode
- Terminal
- Microsoft Word/Pages
- Google Docs (browser)

### Test Scenarios

- Paste single text item
- Paste rich text item; verify plain text mode strips formatting
- Quick Paste 1–9 into at least 3 different apps
- Paste stack (5+ items) sequentially
- Paste stack (20 items) sequentially (timing/ordering)
- Denied Accessibility permission → user sees guidance and app behaves safely
- Sleep/wake cycle → hotkeys continue to work

### Pass/Fail Notes

Record per-app issues: paste succeeds/fails, needs longer delay/activation retry, hotkey conflicts, focus/activation edge cases.

## Manual Testing Protocols

- Validate permissions flows on a clean profile (Accessibility + Input Monitoring)
- Validate focus/activation edge cases (switch apps during paste)
- Validate hotkey conflicts (popular apps with global shortcuts)
- Validate screen sharing mode behavior
