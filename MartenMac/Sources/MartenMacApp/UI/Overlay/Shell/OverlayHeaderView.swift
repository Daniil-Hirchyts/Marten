import AppKit
import SwiftUI

extension OverlayShellView {
    var horizontalHeaderBar: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let filterExtra: CGFloat = headerButtonSize + 1 // filter button + separator
            let searchGroupCollapsed = searchCollapsedWidth + filterExtra
            let searchGroupExpanded = searchCollapsedWidth + searchExpandedWidth + filterExtra
            let searchWidth: CGFloat = isSearchExpanded ? searchGroupExpanded : searchGroupCollapsed
            let leadingPad: CGFloat = 4
            let trailingPad: CGFloat = 4
            let spacing: CGFloat = 7
            let settingsWidth: CGFloat = headerButtonSize

            // Pinboard area boundaries
            let collapsedSearchEnd = leadingPad + searchGroupCollapsed + spacing
            let expandedSearchEnd = leadingPad + searchGroupExpanded + spacing
            let settingsLeadingEdge = totalWidth - trailingPad - settingsWidth
            let pinboardEnd = settingsLeadingEdge - spacing

            // Full pinboard width when search is collapsed
            let fullPinboardWidth = max(0, pinboardEnd - collapsedSearchEnd)

            // Estimated bar visual width (tabs + scroll padding + spacing + add button)
            let barEstimatedWidth = pinboardTabsContentWidth + 56

            // Free space on left side when bar is centered in full pinboard area
            let freeSpaceLeft = max(0, (fullPinboardWidth - barEstimatedWidth) / 2)

            // Would the expanded search overlap the centered tab content?
            let searchExtension = searchGroupExpanded - searchGroupCollapsed
            let wouldOverlap = freeSpaceLeft < searchExtension

            // Effective pinboard leading edge: push only when content would overlap
            let pinboardStart = (isSearchExpanded && wouldOverlap) ? expandedSearchEnd : collapsedSearchEnd
            let pinboardWidth = max(0, pinboardEnd - pinboardStart)

            OverlaySearchBarView(
                isSearchExpanded: $isSearchExpanded,
                isFilterPopoverPresented: $isFilterPopoverPresented,
                searchText: $searchModel.searchText,
                searchFocused: $searchFocused,
                dateFilter: $searchModel.dateFilter,
                typeFilters: $searchModel.typeFilters,
                appFilters: $searchModel.appFilters,
                appOptions: searchModel.appOptions,
                hasActiveFilters: searchModel.hasActiveFilters,
                headerButtonSize: headerButtonSize,
                headerButtonIconSize: headerButtonIconSize,
                searchCollapsedWidth: searchCollapsedWidth,
                searchExpandedWidth: searchExpandedWidth,
                overlayCoordinateSpaceName: overlayCoordinateSpaceName,
                onSearchButtonTap: handleSearchButtonTap,
                onSearchClear: handleSearchClear,
                onClearFilters: searchModel.clearFilters
            )
            .frame(width: searchWidth, height: headerButtonSize, alignment: .leading)
            .position(x: leadingPad + searchWidth / 2, y: headerButtonSize / 2)
            .zIndex(1)

            PinboardTabBarSection(
                pinboards: visiblePinboards,
                selectedID: searchModel.selectedPinboardID,
                isLocked: { pinboardLockController.isLocked(pinboardID: $0.id) },
                isUnlocked: { pinboardLockController.canAccess(pinboardID: $0.id) },
                editingID: $pinboardRenameState.id,
                isCreatePopoverPresented: $verticalPinboardCreateState.isPresented,
                createPopoverContent: { verticalPinboardCreatePopover },
                draftName: $pinboardRenameState.name,
                draftColor: $pinboardRenameState.colorHex,
                draftIcon: $pinboardRenameState.iconName,
                isGlobalDragActive: dragCoordinator.dragPreviewData != nil,
                itemDragPinboardDropTargetID: itemDragPinboardDropTargetID,
                window: window,
                onPreviewUpdate: { dragCoordinator.updatePinboardDragPreviewWindow($0, parentWindow: window) },
                onSelect: handlePinboardSelect,
                onCreate: handlePinboardCreateStart,
                onSetLockEnabled: handleSetPinboardLock,
                onUnlock: handleRequestPinboardUnlock,
                onLockNow: handleLockPinboardNow,
                onRename: handlePinboardRenameStart,
                onColorChange: pinboardManager.changePinboardColor,
                onIconChange: pinboardManager.changePinboardIcon,
                onDelete: handleDeletePinboard,
                onReorder: handlePinboardReorder,
                onReorderEnd: pinboardManager.saveChanges,
                onMoveItem: handlePinboardMoveItem,
                onCommit: handlePinboardCommit,
                onCancel: handlePinboardCancel,
                onSharePinboard: handleSharePinboard,
                onManageSharing: handleManageSharing,
                onStopSharing: handleStopSharing,
                onLeaveSharedPinboard: handleLeaveSharedPinboard,
                shareSheetPinboard: $shareSheetPinboard,
                sharingRepository: sharingRepository,
                coordinateSpaceName: overlayCoordinateSpaceName,
                horizontalPadding: 0,
                rowHeight: headerButtonSize,
                onPinboardLayoutChange: handlePinboardLayoutChange,
                onSearchFieldFrameChange: { frame in
                    dragCoordinator.updateSearchFieldFrame(frame)
                }
            )
            .frame(width: pinboardWidth, height: headerButtonSize)
            .position(x: pinboardStart + pinboardWidth / 2, y: headerButtonSize / 2)

            settingsButton
                .frame(width: settingsWidth, height: headerButtonSize)
                .position(x: settingsLeadingEdge + settingsWidth / 2, y: headerButtonSize / 2)
        }
        .onPreferenceChange(SearchFieldFrameKey.self) { frame in
            dragCoordinator.updateSearchFieldFrame(frame)
        }
        .padding(.horizontal, 12)
        .frame(height: headerButtonSize)
        .zIndex(1)
    }

    var verticalToolbarRow: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width
            let spacing: CGFloat = 8
            let settingsWidth: CGFloat = headerButtonSize
            
            // Calculate how much space the search bar (toggle + text field + filter) can take.
            let searchBarAvailableWidth = availableWidth - spacing - settingsWidth
            
            // Calculate the text field part width by subtracting toggle and filter buttons.
            let maxSearchTextFieldWidth = max(80, searchBarAvailableWidth - searchCollapsedWidth - headerButtonSize - 1)
            let effectiveSearchExpandedWidth = maxSearchTextFieldWidth

            HStack(spacing: spacing) {
                OverlaySearchBarView(
                    isSearchExpanded: $isSearchExpanded,
                    isFilterPopoverPresented: $isFilterPopoverPresented,
                    searchText: $searchModel.searchText,
                    searchFocused: $searchFocused,
                    dateFilter: $searchModel.dateFilter,
                    typeFilters: $searchModel.typeFilters,
                    appFilters: $searchModel.appFilters,
                    appOptions: searchModel.appOptions,
                    hasActiveFilters: searchModel.hasActiveFilters,
                    headerButtonSize: headerButtonSize,
                    headerButtonIconSize: headerButtonIconSize,
                    searchCollapsedWidth: searchCollapsedWidth,
                    searchExpandedWidth: effectiveSearchExpandedWidth,
                    overlayCoordinateSpaceName: overlayCoordinateSpaceName,
                    onSearchButtonTap: handleSearchButtonTap,
                    onSearchClear: handleSearchClear,
                    onClearFilters: searchModel.clearFilters
                )
                .frame(width: isSearchExpanded ? searchBarAvailableWidth : searchCollapsedWidth + headerButtonSize + 1, alignment: .leading)

                if !isSearchExpanded {
                    Spacer()
                }

                settingsButton
            }
        }
        .padding(.horizontal, 6)
        .frame(height: headerButtonSize)
        .onPreferenceChange(SearchFieldFrameKey.self) { frame in
            dragCoordinator.updateSearchFieldFrame(frame)
        }
    }

    @ViewBuilder
    var settingsButton: some View {
        Menu {
            Button {
                NSApp.sendAction(
                    #selector(AppDelegate.openNewTextItem),
                    to: NSApp.delegate,
                    from: nil
                )
            } label: {
                Label("New Text Item", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("n", modifiers: .command)

            Button {
                NSApp.sendAction(Selector(("openOCRCapture")), to: nil, from: nil)
            } label: {
                Label("Capture Text (OCR)", systemImage: "text.viewfinder")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button {
                viewModel.closeOverlayForSettings {
                    NSApp.sendAction(
                        #selector(AppDelegate.openSettingsWindow),
                        to: NSApp.delegate,
                        from: nil
                    )
                }
            } label: {
                Label("Preferences...", systemImage: "gearshape")
            }
            .accessibilityLabel("Preferences")

            Divider()

            if pasteboardMonitor.isPaused {
                Button {
                    pasteboardMonitor.resume()
                } label: {
                    Label("Resume Capture", systemImage: "play.circle")
                }
            } else {
                Menu {
                    Button("5 Minutes") { pasteboardMonitor.pauseForDuration(300) }
                    Button("15 Minutes") { pasteboardMonitor.pauseForDuration(900) }
                    Button("30 Minutes") { pasteboardMonitor.pauseForDuration(1800) }
                    Button("1 Hour") { pasteboardMonitor.pauseForDuration(3600) }
                    Divider()
                    Button("Until Resumed") { pasteboardMonitor.pauseForDuration(nil) }
                } label: {
                    Label("Pause Capture", systemImage: "pause.circle")
                }
            }

            Toggle(isOn: $screenSharingManager.isScreenSharingModeActive) {
                Label("Screen Sharing Mode", systemImage: "rectangle.inset.filled.on.rectangle")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .accessibilityLabel("Screen Sharing Mode")

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Marten", systemImage: "power")
            }
            .accessibilityLabel("Quit Marten")
        } label: {
            settingsIcon
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            withAnimation(OverlayAnimation.quickTransition) {
                isOptionsHovered = hovering
            }
        }
        .accessibilityIdentifier("overlay.options.menu")
        .accessibilityLabel("Options")
        .accessibilityHint("Shows application options")
    }

    @ViewBuilder
    var settingsIcon: some View {
        OverlayHeaderButton(
            systemImage: "ellipsis",
            size: headerButtonSize,
            iconSize: headerButtonIconSize,
            isHovered: isOptionsHovered
        )
    }
}
