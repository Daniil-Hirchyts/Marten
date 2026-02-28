import SwiftUI

struct PinboardEditorSheet: View {
    enum Mode {
        case create
        case edit

        var title: String {
            switch self {
            case .create: return "New Pinboard"
            case .edit: return "Edit Pinboard"
            }
        }

        var actionLabel: String {
            switch self {
            case .create: return "Create"
            case .edit: return "Save"
            }
        }
    }

    let mode: Mode
    let initialName: String
    let initialColorHex: String
    let initialIconName: String?
    let onSave: (_ name: String, _ colorHex: String, _ iconName: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String
    @State private var selectedColorHex: String
    @State private var selectedIconName: String?
    @State private var signTab: PinboardSignTab = .emoji
    @State private var signSearchText = ""

    private let colorColumns = Array(
        repeating: GridItem(.flexible(minimum: 28), spacing: 10), count: 8)
    private let signColumns = Array(
        repeating: GridItem(.flexible(minimum: 44), spacing: 10), count: 6)

    init(
        mode: Mode,
        initialName: String = "",
        initialColorHex: String = PinboardColorPalette.defaultHex,
        initialIconName: String? = nil,
        onSave: @escaping (_ name: String, _ colorHex: String, _ iconName: String?) -> Void
    ) {
        self.mode = mode
        self.initialName = initialName
        self.initialColorHex = initialColorHex
        self.initialIconName = initialIconName
        self.onSave = onSave

        _name = State(initialValue: initialName)
        _selectedColorHex = State(initialValue: initialColorHex)
        _selectedIconName = State(initialValue: initialIconName)
        _signTab = State(
            initialValue: PinboardSignCatalogIOS.isSystemSymbol(initialIconName) ? .icon : .emoji)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                if #available(iOS 26, *) {
                    Color.clear.ignoresSafeArea()
                } else {
                Color(platformColor: .platformSystemGroupedBackground)
                        .ignoresSafeArea()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Preview + Name
                        MartenGlassSurface(cornerRadius: 16, padding: 0) {
                            nameSection
                        }

                        // Color & Sign in one block
                        MartenGlassSurface(cornerRadius: 16, padding: 0) {
                            VStack(alignment: .leading, spacing: 14) {
                                colorGrid
                                Divider()
                                    .overlay(.white.opacity(0.1))
                                signPicker
                            }
                            .padding(14)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(mode.title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.actionLabel) {
                        onSave(
                            name.trimmingCharacters(in: .whitespacesAndNewlines),
                            selectedColorHex,
                            selectedIconName
                        )
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Name Section

    private var nameSection: some View {
        HStack(spacing: 10) {
            previewIndicator
            nameTextField
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var previewIndicator: some View {
        ZStack {
            Circle()
                .fill(Color(hex: selectedColorHex, fallback: .gray))
                .frame(width: 28, height: 28)

            if let iconName = selectedIconName {
                if PinboardSignCatalogIOS.isSystemSymbol(iconName) {
                    Image(systemName: iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text(verbatim: iconName)
                        .font(.system(size: 16))
                }
            }
        }
        .animation(MartenAnimation.quick, value: selectedColorHex)
        .animation(MartenAnimation.quick, value: selectedIconName)
    }

    private var nameTextField: some View {
        #if os(iOS)
            TextField("Pinboard name", text: $name)
                .font(.headline)
                .textInputAutocapitalization(.words)
        #else
            TextField("Pinboard name", text: $name)
                .font(.headline)
        #endif
    }

    // MARK: - Color Grid

    private var colorGrid: some View {
        LazyVGrid(columns: colorColumns, spacing: 10) {
            ForEach(PinboardColorPalette.all, id: \.hex) { option in
                Button {
                    withAnimation(MartenAnimation.quick) {
                        selectedColorHex = option.hex
                    }
                } label: {
                    let isSelected =
                        selectedColorHex.caseInsensitiveCompare(option.hex) == .orderedSame
                    Circle()
                        .fill(Color(hex: option.hex, fallback: .gray))
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    swatchStrokeColor(isSelected: isSelected),
                                    lineWidth: isSelected ? 2.5 : 0.7
                                )
                        }
                        .scaleEffect(isSelected ? 1.1 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.name)
            }
        }
    }

    // MARK: - Sign Picker

    private var signPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tab selector + clear
            HStack(spacing: 8) {
                signTabSelector
                Spacer()
                Button {
                    withAnimation(MartenAnimation.quick) {
                        selectedIconName = nil
                    }
                } label: {
                    Text("Clear")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search", text: $signSearchText)
                    .font(.subheadline)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    #endif
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )

            // Sign grid
            LazyVGrid(columns: signColumns, spacing: 10) {
                ForEach(filteredSignOptions, id: \.token) { option in
                    Button {
                        withAnimation(MartenAnimation.quick) {
                            selectedIconName = option.token
                        }
                    } label: {
                        let isSelected = selectedIconName == option.token
                        let selectedColor = Color(hex: selectedColorHex, fallback: .accentColor)

                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? selectedColor.opacity(0.28) : innerSurfaceColor)

                            if signTab == .icon {
                                Image(systemName: option.token)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(isSelected ? selectedColor : .primary)
                            } else {
                                Text(verbatim: option.token)
                                    .font(.system(size: 22))
                            }
                        }
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label)
                }
            }
        }
    }

    private var signTabSelector: some View {
        Picker("Sign Type", selection: $signTab) {
            ForEach(PinboardSignTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: signTab) { _, _ in
            signSearchText = ""
        }
    }

    private var filteredSignOptions: [(token: String, label: String)] {
        PinboardSignCatalogIOS.filtered(tab: signTab, query: signSearchText)
    }

    // MARK: - Colors

    private var subtleSurface: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(0.06))
            : AnyShapeStyle(Color.black.opacity(0.04))
    }

    private var innerSurfaceColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    private func swatchStrokeColor(isSelected: Bool) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(isSelected ? 0.95 : 0.5)
        }
        return Color.black.opacity(isSelected ? 0.65 : 0.2)
    }
}
