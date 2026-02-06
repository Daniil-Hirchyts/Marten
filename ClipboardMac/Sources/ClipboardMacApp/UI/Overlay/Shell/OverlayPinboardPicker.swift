import SwiftUI

extension OverlayShellView {
    var verticalPinboardPickerRow: some View {
        HStack(spacing: 8) {
            verticalPinboardPickerMenu
                .frame(maxWidth: .infinity, alignment: .leading)

            if shouldShowVerticalPinboardEditButton {
                verticalPinboardEditButton
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, 14)
    }

    var verticalPinboardPickerMenu: some View {
        Button {
            isVerticalPinboardDropdownPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                if let selectedCustomPinboard {
                    PinboardIndicator(
                        colorHex: selectedCustomPinboard.colorHex,
                        sign: selectedCustomPinboard.iconName,
                        size: 15
                    )
                } else {
                    Image(systemName: "tray")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 15, height: 15)
                }

                Text(verticalPinboardLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .frame(height: headerButtonSize)
            .background {
                if #available(macOS 26.0, *) {
                    Capsule()
                        .fill(Color.clear)
                        .glassNavigationStyle()
                } else {
                    Capsule()
                        .fill(Color.white.opacity(DesignTokens.Opacity.backgroundMedium))
                }
            }
            .overlay {
                if #available(macOS 26.0, *) {
                    EmptyView()
                } else {
                    Capsule()
                        .stroke(Color.white.opacity(DesignTokens.Opacity.borderStrong), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .popover(isPresented: $isVerticalPinboardDropdownPresented, arrowEdge: .top) {
            verticalPinboardDropdownContent
        }
        .popover(isPresented: $isPinboardCreatePresented, arrowEdge: .top) {
            verticalPinboardCreatePopover
        }
        .accessibilityIdentifier("overlay.pinboard.picker")
        .accessibilityLabel("Pinboard")
    }

    var verticalPinboardDropdownContent: some View {
        VStack(spacing: 0) {
            Button {
                handlePinboardSelect(nil)
                isVerticalPinboardDropdownPresented = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 15, height: 15)
                    Text("All Items")
                    Spacer(minLength: 0)
                    if searchModel.selectedPinboardID == nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            ForEach(visiblePinboards) { pinboard in
                let isSelected = searchModel.selectedPinboardID == pinboard.id
                Button {
                    handlePinboardSelect(pinboard.id)
                    isVerticalPinboardDropdownPresented = false
                } label: {
                    HStack(spacing: 8) {
                        PinboardIndicator(
                            colorHex: pinboard.colorHex,
                            sign: pinboard.iconName,
                            size: 15
                        )
                        Text(pinboard.name)
                        Spacer(minLength: 0)
                        if pinboardLockController.isLocked(pinboardID: pinboard.id) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }

            Divider()
                .padding(.vertical, 2)

            Button {
                isVerticalPinboardDropdownPresented = false
                DispatchQueue.main.async {
                    handleCreatePinboardFromVerticalPicker()
                }
            } label: {
                HStack(spacing: 8) {
                    PinboardIndicator(
                        colorHex: nextAvailablePinboardColorHex(),
                        sign: nil,
                        size: 15
                    )
                    Text("New Pinboard...")
                    Spacer(minLength: 0)
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .frame(minWidth: 200)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    var verticalPinboardEditButton: some View {
        Button {
            presentVerticalPinboardEdit()
        } label: {
            Text("Edit")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isVerticalPinboardEditPresented, arrowEdge: .top) {
            verticalPinboardEditPopover
        }
        .accessibilityIdentifier("overlay.pinboard.picker.edit")
        .accessibilityLabel("Edit selected pinboard")
    }

    var verticalPinboardCreatePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Pinboard")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 8) {
                PinboardStylePickerButton(
                    selectedColorHex: verticalPinboardDraftColor,
                    selectedSign: verticalPinboardDraftIcon,
                    shouldPresentOnAppear: $shouldPresentVerticalPinboardStylePicker,
                    onColorSelect: { verticalPinboardDraftColor = $0 },
                    onSignSelect: { verticalPinboardDraftIcon = $0 }
                )

                TextField("Pinboard name", text: $verticalPinboardDraftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($verticalPinboardNameFocused)
                    .accessibilityIdentifier("overlay.pinboard.verticalCreate.name")
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    cancelVerticalPinboardCreate()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    commitVerticalPinboardCreate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(verticalPinboardDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("overlay.pinboard.verticalCreate.commit")
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            DispatchQueue.main.async {
                verticalPinboardNameFocused = true
            }
        }
    }

    var verticalPinboardEditPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Pinboard")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 8) {
                PinboardStylePickerButton(
                    selectedColorHex: verticalPinboardEditDraftColor,
                    selectedSign: verticalPinboardEditDraftIcon,
                    shouldPresentOnAppear: $shouldPresentVerticalPinboardEditStylePicker,
                    onColorSelect: { verticalPinboardEditDraftColor = $0 },
                    onSignSelect: { verticalPinboardEditDraftIcon = $0 }
                )

                TextField("Pinboard name", text: $verticalPinboardEditDraftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($verticalPinboardEditNameFocused)
                    .accessibilityIdentifier("overlay.pinboard.verticalEdit.name")
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    cancelVerticalPinboardEdit()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    commitVerticalPinboardEdit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(verticalPinboardEditDraftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("overlay.pinboard.verticalEdit.commit")
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            DispatchQueue.main.async {
                verticalPinboardEditNameFocused = true
            }
        }
    }
}

