import AppKit
import SwiftUI

extension OverlayShellView {
    var horizontalHeaderBar: some View {
        HStack(alignment: .center, spacing: 10) {
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
            .frame(width: isSearchExpanded ? searchExpandedWidth : searchCollapsedWidth, alignment: .leading)
            .padding(.leading, 4)

            PinboardTabBarSection(
                pinboards: visiblePinboards,
                selectedID: searchModel.selectedPinboardID,
                isLocked: { pinboardLockController.isLocked(pinboardID: $0.id) },
                isUnlocked: { pinboardLockController.canAccess(pinboardID: $0.id) },
                editingID: $renamePinboardID,
                isCreating: $isCreatingPinboard,
                draftName: $renamePinboardName,
                draftColor: $renamePinboardColor,
                draftIcon: $renamePinboardIcon,
                isGlobalDragActive: dragCoordinator.dragPreviewData != nil,
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
                coordinateSpaceName: overlayCoordinateSpaceName,
                horizontalPadding: 0,
                rowHeight: headerButtonSize,
                onPinboardLayoutChange: handlePinboardLayoutChange,
                onSearchFieldFrameChange: { frame in
                    DispatchQueue.main.async { dragCoordinator.updateSearchFieldFrame(frame) }
                }
            )
            .frame(maxWidth: .infinity)

            settingsButton
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 14)
        .frame(height: headerButtonSize)
        .zIndex(1)
    }

    var verticalToolbarRow: some View {
        HStack(spacing: 8) {
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
                searchExpandedWidth: min(searchExpandedWidth, 260),
                overlayCoordinateSpaceName: overlayCoordinateSpaceName,
                onSearchButtonTap: handleSearchButtonTap,
                onSearchClear: handleSearchClear,
                onClearFilters: searchModel.clearFilters
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            settingsButton
        }
        .padding(.horizontal, 14)
        .onPreferenceChange(SearchFieldFrameKey.self) { frame in
            DispatchQueue.main.async { dragCoordinator.updateSearchFieldFrame(frame) }
        }
    }

    @ViewBuilder
    var settingsButton: some View {
        Group {
            if #available(macOS 14.0, *) {
                OverlaySettingsButton14(
                    closeOverlay: { viewModel.closeOverlayForSettings(completion: $0) },
                    label: { settingsIcon }
                )
            } else {
                Button { viewModel.closeOverlayForSettings(completion: openSettingsLegacy) }
                label: { settingsIcon }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("overlay.settings")
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens settings")
    }

    @ViewBuilder
    var settingsIcon: some View {
        if #available(macOS 26.0, *) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: headerButtonIconSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: headerButtonSize, height: headerButtonSize)
                .glassCircleButton()
                .contentShape(Circle())
        } else {
            Image(systemName: "gearshape.fill")
                .font(.system(size: headerButtonIconSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: headerButtonSize, height: headerButtonSize)
                .background(Circle().fill(Color.white.opacity(DesignTokens.Opacity.backgroundMedium)))
                .contentShape(Circle())
        }
    }
}
