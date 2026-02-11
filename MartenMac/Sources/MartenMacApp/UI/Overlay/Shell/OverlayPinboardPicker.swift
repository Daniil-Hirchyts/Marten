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
                        .frame(width: 22, height: 15)
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
        .popover(isPresented: $verticalPinboardCreateState.isPresented, arrowEdge: .top) {
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
                        .frame(width: 22, height: 15)
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
                        if pinboard.isShared {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } else if pinboardLockController.isLocked(pinboardID: pinboard.id) {
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
        .popover(isPresented: $verticalPinboardEditState.isPresented, arrowEdge: .top) {
            verticalPinboardEditPopover
        }
        .accessibilityIdentifier("overlay.pinboard.picker.edit")
        .accessibilityLabel("Edit selected pinboard")
    }

    var verticalPinboardCreatePopover: some View {
        VStack(spacing: 16) {
            Text("New Pinboard")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)

            createPopoverInputSection

            HStack {
                Button("Cancel") {
                    cancelVerticalPinboardCreate()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    commitVerticalPinboardCreate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(verticalPinboardCreateState.draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("overlay.pinboard.verticalCreate.commit")
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            DispatchQueue.main.async {
                verticalPinboardNameFocused = true
            }
        }
        .onChange(of: verticalPinboardCreateState.draftName) { _, newValue in
            if newValue.count > 22 {
                verticalPinboardCreateState.draftName = String(newValue.prefix(22))
            }
        }
    }

    var createPopoverInputSection: some View {
        HStack(spacing: 0) {
            inputStylePicker
            inputSeparator
            inputTextField
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    var inputStylePicker: some View {
        PinboardStylePickerButton(
            selectedColorHex: verticalPinboardCreateState.draftColorHex,
            selectedSign: verticalPinboardCreateState.draftIconName,
            shouldPresentOnAppear: $verticalPinboardCreateState.shouldPresentStylePicker,
            onColorSelect: { verticalPinboardCreateState.draftColorHex = $0 },
            onSignSelect: { verticalPinboardCreateState.draftIconName = $0 }
        )
        .frame(width: 44, height: 32)
        .contentShape(Rectangle())
    }

    var inputSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 16)
    }

    var inputTextField: some View {
        TextField("Name", text: $verticalPinboardCreateState.draftName)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .focused($verticalPinboardNameFocused)
            .accessibilityIdentifier("overlay.pinboard.verticalCreate.name")
    }

    var verticalPinboardEditPopover: some View {
        VStack(spacing: 16) {
            Text("Edit Pinboard")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)

            editPopoverInputSection

            HStack {
                Button("Cancel") {
                    cancelVerticalPinboardEdit()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    commitVerticalPinboardEdit()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(verticalPinboardEditState.draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("overlay.pinboard.verticalEdit.commit")
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            DispatchQueue.main.async {
                verticalPinboardEditNameFocused = true
            }
        }
        .onChange(of: verticalPinboardEditState.draftName) { _, newValue in
            if newValue.count > 22 {
                verticalPinboardEditState.draftName = String(newValue.prefix(22))
            }
        }
    }

    var editPopoverInputSection: some View {
        HStack(spacing: 0) {
            editStylePicker
            editSeparator
            editTextField
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    var editStylePicker: some View {
        PinboardStylePickerButton(
            selectedColorHex: verticalPinboardEditState.draftColorHex,
            selectedSign: verticalPinboardEditState.draftIconName,
            shouldPresentOnAppear: $verticalPinboardEditState.shouldPresentStylePicker,
            onColorSelect: { verticalPinboardEditState.draftColorHex = $0 },
            onSignSelect: { verticalPinboardEditState.draftIconName = $0 }
        )
        .frame(width: 44, height: 32)
        .contentShape(Rectangle())
    }

    var editSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 16)
    }

    var editTextField: some View {
        TextField("Name", text: $verticalPinboardEditState.draftName)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .focused($verticalPinboardEditNameFocused)
            .accessibilityIdentifier("overlay.pinboard.verticalEdit.name")
    }
}

