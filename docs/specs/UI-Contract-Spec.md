# UI Contract Specification
**Paste Clipboard Manager - Engineering Specification**

---

## Document Metadata

- **Version:** 1.0.0
- **Last Updated:** 2026-01-10
- **Status:** Draft
- **Owner:** Engineering Team
- **Dependencies:** 
  - `Architecture-Overview.md` (parent)
  - `Data-Model-Spec.md` (data sources)
  - `macOS-Services-Spec.md` (system integration)

---

## 1. Purpose and Scope

This document defines the complete user interface specification for the Paste Clipboard Manager macOS application. It specifies all UI components, interactions, animations, accessibility requirements, and visual design rules.

### 1.1 Goals

1. **Native feel:** Leverage macOS design patterns and conventions
2. **Performance:** 60 FPS animations, < 500ms overlay open time
3. **Keyboard-first:** All actions accessible via keyboard
4. **Accessibility:** Full VoiceOver support, keyboard navigation
5. **Visual consistency:** Uniform spacing, typography, and colors

### 1.2 Design Philosophy

**Principles:**
- **Minimal and focused:** Show only essential information
- **Fast and responsive:** Instant feedback for all interactions
- **Non-intrusive:** Don't interrupt the user's workflow
- **Predictable:** Consistent behavior across all contexts

---

## 2. Application Structure

### 2.1 UI Hierarchy

```
PasteApp (SwiftUI App)
├── MenuBarExtra
│   └── StatusItemView
│       └── MenuBarMenu
├── OverlayWindow (NSPanel)
│   └── OverlayRootView
│       ├── PinboardTabBar
│       ├── ItemCardRow
│       └── SearchMode
├── SettingsWindow
│   └── SettingsView
│       ├── GeneralTab
│       ├── PrivacyTab
│       ├── ShortcutsTab
│       └── PurchaseTab
└── OnboardingWindow (First Launch)
    └── OnboardingFlow
```

---

## 3. Overlay Window (Primary UI)

### 3.1 Window Behavior

**Type:** Custom `NSPanel` hosting SwiftUI

**Configuration:**
```swift
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.styleMask = [.borderless]
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
```

**Positioning:**
- Anchored: Bottom of screen
- Margin: 8pt from bottom edge, 8pt from left/right edges
- Width: Full width minus horizontal margins
- Height: Adaptive based on content (typical: 320pt)

**States:**
- Hidden (default)
- Visible - Browse Mode
- Visible - Search Mode
- Visible - Paste Stack Mode
- Click outside overlay closes the panel
- Overlay closes when the app loses focus or another app activates

### 3.2 Visual Design

**Background:**
- Material: `.hudWindow` (translucent dark or light based on system appearance)
- Border radius: 16pt
- Shadow: 0pt 8pt 32pt rgba(0,0,0,0.3)

**Safe Areas:**
- Top padding: 8pt
- Bottom padding: 8pt
- Leading/trailing padding: 8pt

### 3.3 Animation

**Open Animation (200ms):**
```swift
.transition(.move(edge: .bottom).combined(with: .opacity))
.animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
```

**Close Animation (150ms):**
```swift
.transition(.opacity)
.animation(.easeOut(duration: 0.15), value: isVisible)
```

---

## 4. Pinboard Tab Bar

### 4.1 Layout

**Position:** Top row of overlay (tabs + search field)

**Structure:**
```
[• All] [• Work] [• Personal] [+]   [ Search ]
```

**Dimensions:**
- Height: 40pt
- Tab min width: 100pt
- Tab max width: 200pt
- Spacing: 8pt
- Plus button: 32x32pt
- Search field: 160pt width, right aligned in the same row

### 4.2 Tab Component

**Visual:**
- Background: `.quaternary` when not selected
- Background selected: `.blue` (or custom pinboard color)
- Text color: `.primary` / `.white` (based on selection)
- Font: System 13pt, weight .medium
- Color dot: 8pt diameter, leading position
- Border radius: 8pt

**States:**
- Default
- Hover (brightness +10%)
- Selected
- Dragging (opacity 0.7)

**Interaction:**
- Click: Switch to pinboard
- Right-click: Show context menu
- Drag: Reorder pinboards
- Keyboard: ⌘→ / ⌘← to navigate

### 4.3 Tab Context Menu

**Menu Items:**
```
Rename Pinboard
Delete Pinboard
```

**Conditional:**
- System "Clipboard" pinboard is not shown in the tab bar

### 4.4 Plus Button

**Visual:**
- Icon: SF Symbol `plus.circle.fill`
- Size: 24pt icon in 32pt button
- Color: `.secondary`
- Hover: Scale 1.1

**Interaction:**
- Click: Show "New Pinboard" sheet
- Keyboard: ⌘N (when overlay is focused)

**Pinboard Editor Sheet:**
- Fields: Name, color swatch picker
- Color palette uses predefined hex values
- Rename uses the same sheet with current values prefilled

---

## 5. Item Card Row

### 5.1 Layout

**Position:** Top of overlay, below pinboard tabs

**Structure:**
- Horizontal scroll view with snap-to-card behavior
- Cards: 220pt width, 220pt height (square)
- Spacing: 8pt between cards
- Padding: 8pt leading/trailing
- Shows 1-4 cards simultaneously depending on screen width

**Scrolling:**
- Paging enabled (snap to card boundaries)
- Momentum: Moderate spring feel
- Keyboard: ← / → arrows to navigate
- Mouse wheel / trackpad: Natural scroll
- Drag cards to reorder (browse mode)

### 5.2 Card Component

**Visual Structure:**
```
┌──────────────────────────────┐
│ Text  3m              ┌─┐    │ ← Header
│                       │•│    │
│                                │
│   [Preview Content]            │ ← Body
│                                │
│                                │
│                          5     │ ← Footer (index)
└──────────────────────────────┘
```

**Styling:**
- Background: `.tertiarySystemFill`
- Border: 1pt `.separator` (subtle)
- Border radius: 12pt
- Shadow: 0pt 2pt 8pt rgba(0,0,0,0.1)

**States:**
- Default
- Hover (border highlight, scale 1.02)
- Selected (blue border 2pt, scale 1.03)
- Pressing (scale 0.98)
- Reorder target (dashed blue outline placeholder)

### 5.3 Card Header

**Layout:**
- Height: 28pt
- Padding: 12pt horizontal, 8pt vertical

**Elements:**
1. **Type + Time Label**
   - Font: System 11pt, weight .medium
   - Color: `.secondary`
   - Format: "Text 3m" / "Image now" / "File 2h" / "Code 1d"

2. **Menu Button (trailing)**
   - Icon: SF Symbol `ellipsis.circle`
   - Size: 20pt
   - Color: `.secondary`
   - Visibility: Hidden by default, shown on hover
   - Tap: Show context menu

### 5.4 Card Body (Preview)

**Padding:** 12pt all sides

**Preview Types:**

#### Text Preview
- Font: System 14pt, weight .regular
- Color: `.primary`
- Line limit: 6 lines
- Line height: 1.3
- Truncation: `...` at end
- Preserve: Leading whitespace for code

#### Rich Text Preview
- Rendered as AttributedString
- Max font size: 14pt (scale down if larger)
- Line limit: 6 lines
- Preserve: Bold, italic, basic formatting
- Strip: Colors, backgrounds (use system colors)

#### Image Preview
- Content mode: `.fit`
- Max size: Fill available space
- Loading: ProgressView placeholder
- Error: SF Symbol `photo` with gray background

#### URL Preview (with metadata)
- Favicon: 16x16pt (top-left)
- Title: System 13pt, weight .semibold, 2 lines max
- URL: System 11pt, weight .regular, 1 line, truncated
- Preview image (if available): 100% width, 80pt height
- Layout: Vertical stack

#### File Preview
- Icon: SF Symbol or file type icon, 48pt
- Filename: System 13pt, weight .medium, 2 lines max
- File size: System 11pt, weight .regular, `.secondary`
- Layout: Centered vertical stack

#### Code Preview (detected text)
- Font: SF Mono 12pt
- Color: `.primary`
- Background: `.quaternarySystemFill`
- Border radius: 4pt
- Padding: 8pt
- Line limit: 8 lines
- Preserve: Exact whitespace and formatting

### 5.5 Card Footer

**Layout:**
- Position: Absolute bottom-right
- Padding: 8pt
- Size: 24x24pt

**Index Badge:**
- Background: `.blue` (or accent color)
- Text: White, System 12pt, weight .bold
- Format: "1" through "9"
- Border radius: 12pt (circular)
- Visibility: Only for first 9 visible items

**Pinboard Colors:**
- Small color dots next to the type badge
- One dot per pinboard membership (excluding system clipboard)

### 5.6 Card Context Menu

**Menu Items:**
```
Paste (or "Copy to Clipboard")
Paste as Plain Text
---
Move to Pinboard ▸
  • Work
  • Personal
  ---
  New Pinboard...
---
Pin Item
Delete Item
```

**Conditional:**
- "Paste" vs "Copy" based on general settings
- "Pin Item" / "Unpin Item" available only when a pinboard is selected

### 5.7 Empty State

**When:** No items in current pinboard

**Visual:**
```
[SF Symbol: tray]
No items yet
Clipboard history will appear here
```

- Icon: 48pt, `.quaternary` color
- Title: System 16pt, weight .medium, `.secondary`
- Subtitle: System 13pt, weight .regular, `.tertiary`
- Layout: Centered vertically and horizontally

---

## 6. Search Mode

### 6.1 Activation

**Triggers:**
- Click the search field (always visible)
- Keyboard: ⌘F (focuses the search field)
- Start typing when overlay is focused

**Transition:**
- Search field remains visible
- Item card row updates live with results

### 6.2 Search Field

**Layout:**
- Position: Same row as pinboard tabs
- Width: 160pt (short field aligned to trailing edge)
- Height: 28pt

**Visual:**
- Background: `.quaternarySystemFill`
- Border: 1pt `.separator`
- Border radius: 10pt
- Placeholder: "Search"
- Font: System 14pt
- Clear button (trailing): SF Symbol `xmark.circle.fill` (appears when typing)

**Interaction:**
- Focus: Auto-focus on activation
- Typing: Incremental search (debounced 150ms)
- Escape: Clear and exit search mode
- Enter: Select first result
- ↑ / ↓: Navigate results

### 6.3 Search Results

**Display:** Item card row (same as browse mode)

**Sorting:** Relevance (best match first), then by date (newest first)

**Highlight:** Match keywords in preview text (yellow background, 30% opacity)

**No Results State:**
```
[SF Symbol: magnifyingglass]
No results for "query"
Try different keywords
```

### 6.4 Search Scope Indicator

**Position:** Below search field (if needed)

**Options:**
- "Searching in [Pinboard Name]"
- "Searching in All Pinboards"

**Toggle:** Click to switch scope

---

## 7. Paste Stack Mode

### 7.1 Activation

**Triggers:**
- Keyboard: Shift+⌘C (default shortcut)
- Menu bar menu: "Activate Paste Stack"

**Visual Difference:**
- Overlay header text: "Paste Stack"
- Selected cards show checkmark badge (top-right)
- Footer shows: "3 items selected" + [Clear] [Paste]

### 7.2 Multi-Selection

**Interaction:**
- Click card: Toggle selection
- Keyboard: Space to toggle current card
- ← / →: Navigate without deselecting
- ⌘A: Select all visible items
- Escape: Clear selection and exit

**Visual:**
- Selected cards: Blue border 2pt, checkmark badge (SF Symbol `checkmark.circle.fill`, 24pt, top-right)
- Unselected: Default appearance

### 7.3 Stack Footer Bar

**Layout:**
- Position: Bottom of overlay
- Height: 48pt
- Background: `.quaternarySystemFill`
- Border-top: 1pt `.separator`

**Elements:**
1. **Selection Count Label**
   - Text: "3 items selected"
   - Font: System 13pt, weight .medium
   - Position: Leading

2. **Clear Button**
   - Style: Bordered button, secondary
   - Text: "Clear"
   - Action: Deselect all

3. **Paste Button**
   - Style: Prominent button, blue
   - Text: "Paste" or "Paste Sequential"
   - Position: Trailing
   - Keyboard: ⌘Enter or Enter
   - Action: Execute paste stack workflow

---

## 8. Settings Window

### 8.1 Window Configuration

**Type:** Standard `NSWindow`

**Size:**
- Width: 600pt
- Height: 500pt
- Resizable: No
- Min/Max: Fixed size

**Position:** Center of screen on first open, restore last position

**Style:** `.titled`, `.closable`, no minimize/zoom buttons

### 8.2 Tab Structure

**Tabs:** (macOS standard tab bar)
1. General
2. Privacy
3. Shortcuts
4. Purchase (or License)

### 8.3 General Tab

**Layout:** Form with sections

#### Section: Startup
```
☑ Open at login
☑ Run in background
```

#### Section: Sync
```
☑ iCloud Sync
    Status: [Synced now] / [Last synced 2m ago] / [Syncing...] / [Error]
    [Force Sync Button]
```

#### Section: Paste Behavior
```
Paste items:
  ⦿ To active app
  ○ To clipboard

☑ Always paste as Plain Text

☑ Sound effects
```

#### Section: History
```
Keep History:  [  Day  ] [  Week  ] [  Month  ] [  Year  ] [  Forever  ]
               ← Slider with 5 discrete steps →

[Erase History...] button (destructive style)
```

**Spacing:**
- Section spacing: 24pt
- Row spacing: 12pt
- Label width: 120pt (aligned right)
- Control leading padding: 8pt

### 8.4 Privacy Tab

**Layout:** Form with sections

#### Section: Visibility
```
☑ Show during screen sharing
```

#### Section: Content
```
☑ Generate link previews
☑ Ignore confidential content
☑ Ignore transient content
```

#### Section: Ignored Applications
```
Applications to ignore:
┌────────────────────────────────────┐
│ [Icon] Keychain Access             │
│ [Icon] Passwords                   │
│                                    │
│                                    │
└────────────────────────────────────┘
  ← List view, 200pt height

[+] [-] buttons below list
```

**Ignored Apps List:**
- Show: App icon (16x16pt) + app name
- Selection: Single select
- Add button: Opens app picker (NSOpenPanel → /Applications)
- Remove button: Deletes selected app from list

### 8.5 Shortcuts Tab

**Layout:** Form with shortcut recorders

```
Activate Paste:           [ ⇧⌘V ]
Activate Paste Stack:     [ ⇧⌘C ]
Show next Pinboard:       [ ⌘→ ]
Show previous Pinboard:   [ ⌘← ]
Quick Paste:              [ ⌘1..9 ]
Plain Text mode:          [ ⇧ Hold ]

[Reset to Defaults] button
```

**Shortcut Recorder Component:**
- Width: 180pt
- Height: 28pt
- Style: Rounded rect, `.tertiarySystemFill` background
- Interaction: Click to record, type new shortcut, Enter to confirm
- Validation: Prevent conflicts, show warning if conflict detected

### 8.6 Purchase Tab

**Layout:** Centered content

**For Paid App (already purchased):**
```
✓ Paste Pro

Thank you for your purchase!
You have full access to all features.

Receipt: [email@example.com]
Purchase Date: January 5, 2026

[Restore Purchases] button (if IAP model)
```

**For IAP Model (not purchased):**
```
Paste Pro

Unlock unlimited clipboard history,
iCloud sync, and all features.

$4.99 one-time purchase

[Purchase] button (prominent)
[Restore Purchases] button (text only)

Terms of Service | Privacy Policy
```

---

## 9. Menu Bar

### 9.1 Status Item

**Icon:**
- SF Symbol: `doc.on.clipboard` (or custom icon)
- Size: 16pt template rendering (adapts to dark/light mode)
- States:
  - Default: Black/white based on system appearance
  - Active (overlay open): Highlight
  - Paused: Dimmed or with badge indicator
  - Syncing: Optional spinner overlay (subtle)

**Interaction:**
- Click: Show menu (standard NSMenu)
- Right-click: Same as click (no alternate menu)

### 9.2 Menu Items

```
About Paste
New Text Item          ⌘N
---
Settings...            ⌘,
Help
---
Pause Paste            [checkbox if paused]
---
Quit Paste             ⌘Q
```

**Dynamic:**
- "Pause Paste" / "Resume Paste" toggles based on state

### 9.3 New Text Item Sheet

**Trigger:** Menu item or ⌘N

**Window:**
- Type: Sheet attached to settings window (or floating if no window)
- Size: 400pt x 300pt

**Content:**
```
New Text Item

[Text Field: Multi-line, 200pt height]

Pinboard: [Dropdown: All ▾]

[Cancel]  [Create]
```

**Interaction:**
- Text field: Auto-focus
- Create button: Disabled if text is empty
- ⌘Enter: Submit
- Escape: Cancel

---

## 10. Onboarding (First Launch)

### 10.1 Flow Structure

**Steps:**
1. Welcome
2. Permissions (Accessibility)
3. How to Use
4. Complete

### 10.2 Welcome Screen

**Content:**
```
[App Icon: 128pt]

Welcome to Paste

Your clipboard history manager for macOS

[Continue] button
```

### 10.3 Permissions Screen

**Content:**
```
[SF Symbol: hand.raised 64pt]

Accessibility Permission Required

Paste needs Accessibility permission to:
• Monitor your clipboard
• Paste content into apps

[Open System Settings] button

[Skip for Now] text button
```

**Behavior:**
- Check permission status on appear
- If granted: Auto-advance to next step
- Open System Settings: Deep link to Accessibility pane

### 10.4 How to Use Screen

**Content:**
```
[Illustration or screenshot]

Press ⇧⌘V to open Paste

Browse your clipboard history,
search, and paste with one click.

[Continue] button
```

### 10.5 Complete Screen

**Content:**
```
[Checkmark icon: 64pt]

You're All Set!

Start copying and Paste will
remember everything.

[Get Started] button
```

**Action:** Close onboarding, show overlay for first time

---

## 11. Interaction Patterns

### 11.1 Keyboard Navigation

**Global Shortcuts:** (when overlay is hidden)
- ⇧⌘V: Open overlay (browse mode)
- ⇧⌘C: Open overlay (paste stack mode)

**Within Overlay:**
- ← / →: Navigate cards
- Enter: Paste selected card
- Space: Toggle selection (in paste stack mode)
- ⌘F: Activate search
- ⌘→ / ⌘←: Switch pinboards
- ⌘1..9: Quick paste indexed item
- ⇧ (hold): Modifier for plain text paste
- Escape: Close overlay
- Tab: Cycle focus (pinboards → cards → search)

**Accessibility:**
- VoiceOver: Announce card content and type
- Full keyboard navigation with Tab
- Speak when overlay opens: "Paste, 47 items"

### 11.2 Mouse / Trackpad

**Overlay:**
- Click card: Select and paste (or copy based on settings)
- Right-click card: Context menu
- Scroll horizontally: Navigate cards
- Click outside overlay: Close

**Pinboard Tabs:**
- Click: Switch pinboard
- Right-click: Context menu
- Drag: Reorder (show drop indicator)

**Search:**
- Click magnifier: Activate search
- Click clear button: Clear query

### 11.3 Drag and Drop

**Drag Source:**
- Card → External app: Drag preview, provide pasteboard data
- Card → Pinboard tab: Move item to pinboard (show highlight)

**Drop Target:**
- Overlay (when open): Accept text/images/files, create new clip item

---

## 12. Visual Design System

### 12.1 Typography

**Font Family:** San Francisco (system default)

**Text Styles:**
- **Title 1:** 28pt, weight .bold (onboarding)
- **Title 2:** 20pt, weight .semibold (settings section headers)
- **Body:** 14pt, weight .regular (card preview, labels)
- **Subhead:** 13pt, weight .medium (card headers)
- **Caption:** 11pt, weight .regular (secondary info)
- **Monospace:** SF Mono 12pt (code preview)

### 12.2 Color Palette

**Semantic Colors:** (adapt to light/dark mode)
- Primary: `.primary` (black / white)
- Secondary: `.secondary` (gray)
- Tertiary: `.tertiary` (lighter gray)
- Accent: `.blue` (or user-chosen accent color)

**Pinboard Colors:**
```swift
enum PinboardColor: String {
    case red     = "#E86B6B"
    case orange  = "#F0B25D"
    case yellow  = "#E2D36B"
    case green   = "#6BCB83"
    case blue    = "#4FAAD7"
    case purple  = "#7A79E3"
    case pink    = "#C47AD8"
    case gray    = "#8E8E93"
}
```

**Backgrounds:**
- Primary: `.windowBackgroundColor`
- Secondary: `.controlBackgroundColor`
- Tertiary: `.tertiarySystemFill`
- Overlay: `.hudWindow` material

### 12.3 Spacing System

**Base Unit:** 4pt

**Common Values:**
- XXS: 4pt
- XS: 8pt
- S: 12pt
- M: 16pt (default)
- L: 20pt
- XL: 24pt
- XXL: 32pt

### 12.4 Shadows

**Elevation Levels:**
- **Level 1:** 0pt 2pt 8pt rgba(0,0,0,0.1) (cards)
- **Level 2:** 0pt 4pt 16pt rgba(0,0,0,0.15) (overlay)
- **Level 3:** 0pt 8pt 32pt rgba(0,0,0,0.3) (floating panels)

### 12.5 Border Radius

- **Small:** 4pt (badges, buttons)
- **Medium:** 8pt (tabs, input fields)
- **Large:** 12pt (cards)
- **XLarge:** 16pt (overlay window)

---

## 13. Accessibility

### 13.1 VoiceOver Support

**Requirements:**
- All interactive elements have accessibility labels
- Card content is announced with type and preview text
- Navigation hints: "Card 3 of 47, Text from 3 minutes ago"
- Actions: "Double tap to paste"

**Example Labels:**
```swift
.accessibilityLabel("Text item from 3 minutes ago")
.accessibilityValue(previewText)
.accessibilityHint("Double tap to paste into active application")
.accessibilityAddTraits(.isButton)
```

### 13.2 Keyboard Accessibility

**Focus Indicators:**
- Clear 2pt blue outline on focused elements
- Focus ring respects system accent color
- Skip links for power users (e.g., skip pinboard tabs)

**Shortcuts:**
- All actions accessible via keyboard
- Shortcuts listed in menu (with symbols: ⌘⇧⌥⌃)
- Customizable shortcuts with conflict detection

### 13.3 Reduce Motion

**When enabled:**
- Disable scale animations
- Use fade only for transitions
- Disable parallax effects

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

// Use:
.scaleEffect(reduceMotion ? 1.0 : scale)
```

### 13.4 Increase Contrast

**When enabled:**
- Increase border opacity
- Use darker/lighter backgrounds
- Disable transparency on cards

### 13.5 Color Blindness

**Considerations:**
- Don't rely on color alone (use icons + text)
- Pinboard colors have text labels
- Selected state uses border + icon (not just color)

---

## 14. Performance Requirements

### 14.1 Response Time Budgets

| Action | Target | Maximum |
|--------|--------|---------|
| Open overlay | 200ms | 500ms |
| Card render | 16ms (60fps) | 33ms |
| Search query | 100ms | 250ms |
| Switch pinboard | 50ms | 150ms |
| Thumbnail load | 200ms | 1000ms |

### 14.2 Optimization Strategies

**Lazy Loading:**
- Render only visible cards (+ 2 offscreen for preloading)
- Load thumbnails on-demand
- Use placeholders during loading

**Caching:**
- Cache rendered card views
- Cache thumbnail images
- Cache search results (invalidate on data change)

**Animations:**
- Use `.drawingGroup()` for complex card layouts
- Prefer `.opacity` over `.blur` for fade effects
- Limit shadow complexity

---

## 15. Phase-Specific Implementation Tasks

### Phase 1: Core Foundation (Weeks 1-3)

**UI Tasks:**
- [x] Create basic SwiftUI overlay window
- [x] Simple list view of text items
- [x] Open/close animation
- [x] Global hotkey to show overlay

**Success Criteria:**
- Overlay opens in <500ms
- Can display 100 items without lag

**Status Notes:**
- Performance targets are not yet benchmarked

---

### Phase 2: Full Capture & UI Parity (Weeks 4-6)

**UI Tasks:**
-- [x] Design card component with all preview types (basic card + thumbnail/metadata)
-- [x] Implement horizontal scroll with snap behavior (view-aligned on macOS 14+, fallback on 13)
-- [x] Create pinboard tab bar component (minimal horizontal list in overlay + create)
-- [x] Implement tab switching (filtering + search scoped to pinboard)
-- [x] Add context menus (card + tab) (basic actions wired)
-- [x] Create search mode UI (inline search field + result count)
-- [x] Implement search field with incremental search (Core Data-backed search results)
-- [x] Design empty states (search/pinboard empty messaging + styled panel)
-- [x] Add menu bar icon and menu (initial status item + toggle/quit menu)
-- [x] Create "New Text Item" sheet (basic panel)

**Status Notes:**
- Pinboard tab reorder and keyboard navigation remain out of scope for Phase 2
- Pinboard color picker delivered via the pinboard editor sheet (create/rename)
- Card context menu supports paste (preserved/plain), move-to-pinboard, pin/unpin (pinboard only), copy, and delete

**Success Criteria:**
- All content types preview correctly
- Smooth scrolling at 60 FPS
- Search returns results in <100ms
- UI matches design mockups

**Deliverables:**
```
ClipboardMac/UI/
├── Overlay/
│   ├── OverlayWindow.swift
│   ├── OverlayRootView.swift
│   ├── PinboardTabBar.swift
│   ├── ItemCardRow.swift
│   ├── ItemCard.swift
│   ├── CardPreviews/
│   │   ├── TextPreview.swift
│   │   ├── ImagePreview.swift
│   │   ├── URLPreview.swift
│   │   ├── FilePreview.swift
│   │   └── CodePreview.swift
│   └── SearchMode.swift
├── Components/
│   ├── PinboardTab.swift
│   └── ContextMenus.swift
└── MenuBar/
    ├── MenuBarView.swift
    └── NewTextItemSheet.swift
```

---

### Phase 3: Paste Behaviors (Weeks 7-8)

**UI Tasks:**
- [x] Implement paste stack mode UI
- [x] Add multi-selection visual feedback
- [x] Create stack footer bar
- [x] Add selection count label and buttons
- [x] Implement quick paste index badges (1-9)
- [x] Add visual feedback for paste actions (footer "Pasting..." state)
- [x] Create plain text mode indicator (when Shift held)
- [x] Add sound effects integration (system sounds)

**Success Criteria:**
- Stack selection feels responsive
- Quick paste (⌘1-9) responds instantly
- Plain text mode has clear visual indicator

---

### Phase 4: Privacy & Settings (Weeks 9-10)

**UI Tasks:**
- [ ] Create settings window with tab structure
- [ ] Implement General tab (all controls)
- [ ] Implement Privacy tab (all controls)
- [ ] Implement Shortcuts tab with shortcut recorders
- [ ] Implement Purchase tab
- [ ] Create app picker for ignored apps
- [ ] Add sync status indicator
- [ ] Create onboarding flow (4 screens)
- [ ] Design permission request UI
- [ ] Add "Pause" indicator in menu bar

**Success Criteria:**
- All settings persist correctly
- Onboarding completes in <2 minutes
- Permission requests are clear

---

### Phase 5: CloudKit Sync (Weeks 11-14)

**UI Tasks:**
- [ ] Add sync status indicator in settings
- [ ] Show "Syncing..." state in UI
- [ ] Display sync errors to user
- [ ] Add "Force Sync" button
- [ ] Show last sync time
- [ ] Handle iCloud account issues in UI
- [ ] Display quota warnings (if approaching limit)

**Success Criteria:**
- User can understand sync status at a glance
- Errors are actionable (not technical)
- Sync doesn't block UI

---

### Phase 6: Hardening & Performance (Weeks 15-16)

**UI Tasks:**
- [ ] Profile UI rendering with Instruments
- [ ] Optimize card rendering
- [ ] Reduce animation complexity if needed
- [ ] Add skeleton loading states
- [ ] Polish transitions and micro-animations
- [ ] Conduct accessibility audit
- [ ] Test with VoiceOver
- [ ] Test with all accessibility options enabled
- [ ] Finalize dark mode appearance
- [ ] Add UI tests for critical flows

**Success Criteria:**
- Consistent 60 FPS in all scenarios
- No visual glitches
- Perfect VoiceOver support
- All animations respect Reduce Motion

---

## 16. Decisions

### 16.1 Decisions Needed

1. **Click outside to close?**
   - **Implemented:** Close on outside interaction and app focus loss
   - **Notes:** Escape still closes the overlay

2. **Card width: Fixed or adaptive?**
   - **Implemented:** Fixed 220pt (consistent sizing)

3. **Maximum visible cards?**
   - **Recommendation:** Show 3-4 cards, scroll for more
   - **Alternative:** Scale down to show more (max 6)

4. **Pinboard color in card UI?**
   - **Implemented:** Color dots in card footer

### 16.2 Future Enhancements

- [ ] Customizable card layouts (compact / expanded)
- [ ] Themes (beyond system light/dark)
- [ ] Custom fonts for code preview
- [ ] Grid view (alternative to carousel)
- [ ] Advanced search syntax (type:image, app:Safari)
- [x] Drag to reorder within pinboard (browse mode only)
- [ ] Inline editing of text items
- [ ] Item annotations/notes

---

## 17. Testing Checklist

### 17.1 Visual Testing

- [ ] Test in light mode
- [ ] Test in dark mode
- [ ] Test on different screen sizes (13" - 32")
- [ ] Test on Retina and non-Retina displays
- [ ] Test with external displays
- [ ] Test with different macOS versions (if supporting older)

### 17.2 Interaction Testing

- [ ] All keyboard shortcuts work
- [ ] All mouse interactions work
- [ ] All trackpad gestures work
- [ ] Context menus appear correctly
- [ ] Drag and drop works in all scenarios
- [ ] Focus indicators are clear
- [ ] Tab navigation follows logical order

### 17.3 Accessibility Testing

- [ ] VoiceOver reads all content correctly
- [ ] All actions accessible via keyboard
- [ ] Focus indicators respect system settings
- [ ] Reduce Motion is respected
- [ ] Increase Contrast is respected
- [ ] Text scales with system preferences

---

## 18. Changelog

### Version 1.0.0 (2026-01-09)
- Initial UI contract specification
- Defined all major UI components
- Specified interaction patterns
- Outlined accessibility requirements
- Detailed phase-specific UI tasks

---

**Related Documents:**
- [Architecture Overview](./Architecture-Overview.md)
- [Data Model Spec](./Data-Model-Spec.md) - Data displayed in UI
- [macOS Services Spec](./macOS-Services-Spec.md) - Backend for UI actions
- [Privacy & Security Spec](./Privacy-Security-Spec.md) - Privacy UI requirements
