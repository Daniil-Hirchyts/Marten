import AppKit
import SwiftUI

enum PinboardSignPickerTab: String, CaseIterable, Identifiable {
    case emoji = "Emoji"
    case icon = "Icon"

    var id: String { rawValue }
}

struct PinboardSignOption: Hashable, Identifiable {
    let token: String
    let label: String

    var id: String { token }
}

enum PinboardSignCatalog {
    static let emojiOptions: [PinboardSignOption] = [
        .init(token: "😀", label: "grinning face"),
        .init(token: "😄", label: "smile"),
        .init(token: "😅", label: "sweat smile"),
        .init(token: "😂", label: "joy"),
        .init(token: "🙂", label: "slightly smiling"),
        .init(token: "😉", label: "wink"),
        .init(token: "😊", label: "blush"),
        .init(token: "😎", label: "cool sunglasses"),
        .init(token: "🤩", label: "star eyes"),
        .init(token: "🥳", label: "celebrate party"),
        .init(token: "🤔", label: "thinking"),
        .init(token: "🤯", label: "mind blown"),
        .init(token: "🤗", label: "hug"),
        .init(token: "🤫", label: "shush"),
        .init(token: "🤝", label: "handshake"),
        .init(token: "🙌", label: "hands raised"),
        .init(token: "👏", label: "clap"),
        .init(token: "🫶", label: "heart hands"),
        .init(token: "❤️", label: "heart"),
        .init(token: "🧡", label: "orange heart"),
        .init(token: "💚", label: "green heart"),
        .init(token: "💙", label: "blue heart"),
        .init(token: "💜", label: "purple heart"),
        .init(token: "🩷", label: "pink heart"),
        .init(token: "⭐", label: "star"),
        .init(token: "✨", label: "sparkles"),
        .init(token: "⚡", label: "lightning"),
        .init(token: "🔥", label: "fire"),
        .init(token: "🌈", label: "rainbow"),
        .init(token: "🌙", label: "moon"),
        .init(token: "☀️", label: "sun"),
        .init(token: "📌", label: "pin"),
        .init(token: "📎", label: "paperclip"),
        .init(token: "📍", label: "location pin"),
        .init(token: "🧠", label: "brain"),
        .init(token: "🧩", label: "puzzle"),
        .init(token: "🎯", label: "target"),
        .init(token: "🎉", label: "confetti"),
        .init(token: "🎵", label: "music"),
        .init(token: "📷", label: "camera"),
        .init(token: "💡", label: "idea"),
        .init(token: "🛠️", label: "tools"),
        .init(token: "🚀", label: "rocket"),
        .init(token: "✅", label: "check"),
        .init(token: "❗", label: "important"),
    ]

    static let iconOptions: [PinboardSignOption] = [
        .init(token: "star.fill", label: "star"),
        .init(token: "sparkles", label: "sparkles"),
        .init(token: "heart.fill", label: "heart"),
        .init(token: "bookmark.fill", label: "bookmark"),
        .init(token: "flag.fill", label: "flag"),
        .init(token: "pin.fill", label: "pin"),
        .init(token: "bolt.fill", label: "bolt"),
        .init(token: "flame.fill", label: "flame"),
        .init(token: "lightbulb.fill", label: "idea"),
        .init(token: "checkmark.circle.fill", label: "check circle"),
        .init(token: "exclamationmark.circle.fill", label: "important circle"),
        .init(token: "questionmark.circle.fill", label: "question circle"),
        .init(token: "clock.fill", label: "clock"),
        .init(token: "calendar", label: "calendar"),
        .init(token: "bell.fill", label: "bell"),
        .init(token: "envelope.fill", label: "mail"),
        .init(token: "paperplane.fill", label: "paper plane"),
        .init(token: "doc.fill", label: "document"),
        .init(token: "folder.fill", label: "folder"),
        .init(token: "tray.full.fill", label: "tray"),
        .init(token: "archivebox.fill", label: "archive"),
        .init(token: "tag.fill", label: "tag"),
        .init(token: "link", label: "link"),
        .init(token: "globe", label: "globe"),
        .init(token: "location.fill", label: "location"),
        .init(token: "map.fill", label: "map"),
        .init(token: "camera.fill", label: "camera"),
        .init(token: "photo.fill", label: "photo"),
        .init(token: "video.fill", label: "video"),
        .init(token: "music.note", label: "music note"),
        .init(token: "headphones", label: "headphones"),
        .init(token: "book.fill", label: "book"),
        .init(token: "graduationcap.fill", label: "graduation"),
        .init(token: "briefcase.fill", label: "briefcase"),
        .init(token: "wrench.and.screwdriver.fill", label: "tools"),
        .init(token: "hammer.fill", label: "hammer"),
        .init(token: "paintbrush.fill", label: "paint brush"),
        .init(token: "gamecontroller.fill", label: "game controller"),
        .init(token: "cart.fill", label: "cart"),
        .init(token: "gift.fill", label: "gift"),
        .init(token: "leaf.fill", label: "leaf"),
        .init(token: "pawprint.fill", label: "paw"),
        .init(token: "cup.and.saucer.fill", label: "coffee"),
        .init(token: "fork.knife", label: "food"),
        .init(token: "house.fill", label: "home"),
        .init(token: "car.fill", label: "car"),
        .init(token: "airplane", label: "airplane"),
        .init(token: "bicycle", label: "bicycle"),
        .init(token: "figure.walk", label: "walk"),
        .init(token: "figure.run", label: "run"),
    ]

    static func preferredTab(for selectedSign: String?) -> PinboardSignPickerTab {
        guard let sign = PinboardSignResolver.normalize(selectedSign) else { return .emoji }
        return PinboardSignResolver.isSystemSymbol(sign) ? .icon : .emoji
    }

    static func filteredOptions(for tab: PinboardSignPickerTab, query: String) -> [PinboardSignOption] {
        let options = tab == .emoji ? emojiOptions : iconOptions
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return options }

        return options.filter { option in
            option.label.localizedStandardContains(trimmed)
                || option.token.localizedStandardContains(trimmed)
        }
    }
}

struct PinboardStylePickerButton: View {
    let selectedColorHex: String
    let selectedSign: String?
    @Binding var shouldPresentOnAppear: Bool
    var onWillOpen: (() -> Void)? = nil
    let onColorSelect: (String) -> Void
    let onSignSelect: (String?) -> Void

    @State private var isPickerPresented = false

    var body: some View {
        Button {
            onWillOpen?()
            isPickerPresented = true
        } label: {
            PinboardIndicator(colorHex: selectedColorHex, sign: selectedSign, size: 16)
                .frame(width: 16, height: 16)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overlay.pinboard.editor.icon")
        .accessibilityLabel("Pinboard style")
        .accessibilityValue(PinboardSignResolver.normalize(selectedSign) ?? "No sign")
        .accessibilityHint("Choose pinboard color and sign")
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            PinboardStylePicker(
                selectedColorHex: selectedColorHex,
                selectedSign: selectedSign,
                onColorSelect: onColorSelect,
                onSignSelect: onSignSelect
            )
            .frame(width: 340, height: 420)
            .padding(12)
        }
        .onAppear {
            openPickerIfRequested()
        }
        .onChange(of: shouldPresentOnAppear) { _, newValue in
            if newValue {
                openPickerIfRequested()
            }
        }
    }

    private func openPickerIfRequested() {
        guard shouldPresentOnAppear else { return }
        shouldPresentOnAppear = false
        onWillOpen?()
        DispatchQueue.main.async {
            isPickerPresented = true
        }
    }
}

private struct PinboardStylePicker: View {
    let selectedColorHex: String
    let selectedSign: String?
    let onColorSelect: (String) -> Void
    let onSignSelect: (String?) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: PinboardSignPickerTab
    @State private var searchText = ""
    @Namespace private var tabSelectionNamespace

    private let signColumns = Array(repeating: GridItem(.flexible(minimum: 42), spacing: 10), count: 6)
    private let colorColumns = Array(repeating: GridItem(.flexible(minimum: 24), spacing: 10), count: 8)

    init(
        selectedColorHex: String,
        selectedSign: String?,
        onColorSelect: @escaping (String) -> Void,
        onSignSelect: @escaping (String?) -> Void
    ) {
        self.selectedColorHex = selectedColorHex
        self.selectedSign = selectedSign
        self.onColorSelect = onColorSelect
        self.onSignSelect = onSignSelect
        _selectedTab = State(initialValue: PinboardSignCatalog.preferredTab(for: selectedSign))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                PinboardIndicator(colorHex: selectedColorHex, sign: selectedSign, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Customize Pinboard")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Pick color and optional sign")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear Sign") {
                    onSignSelect(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .adaptiveGlassBackground(shape: .roundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: colorColumns, spacing: 10) {
                    ForEach(PinboardPalette.all, id: \.hex) { color in
                        Button {
                            onColorSelect(color.hex)
                        } label: {
                            Circle()
                                .fill(Color(hex: color.hex, fallback: .gray))
                                .overlay {
                                    Circle()
                                        .strokeBorder(
                                            swatchStrokeColor(isSelected: isSelectedColor(color.hex)),
                                            lineWidth: isSelectedColor(color.hex) ? 2 : 0.7
                                        )
                                }
                                .frame(width: 24, height: 24)
                                .scaleEffect(isSelectedColor(color.hex) ? 1.08 : 1)
                                .shadow(
                                    color: Color.black.opacity(isSelectedColor(color.hex) ? 0.3 : 0.15),
                                    radius: isSelectedColor(color.hex) ? 4 : 2,
                                    y: 1
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("overlay.pinboard.editor.color.\(color.hex)")
                        .accessibilityLabel("Pinboard color \(color.hex)")
                        .accessibilityValue(isSelectedColor(color.hex) ? "Selected" : "Not selected")
                    }
                }
                .accessibilityIdentifier("overlay.pinboard.editor.color")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(subtleSurfaceColor)
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(PinboardSignPickerTab.allCases) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selectedTab == tab ? Color.white : Color.primary.opacity(0.75))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background {
                                    if selectedTab == tab {
                                        Capsule()
                                            .fill(Color.accentColor)
                                            .matchedGeometryEffect(id: "pinboardStylePickerTab", in: tabSelectionNamespace)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(
                    Capsule()
                        .fill(mediumSurfaceColor)
                )

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(subtleSurfaceColor)
                )

                ScrollView {
                    LazyVGrid(columns: signColumns, spacing: 10) {
                        ForEach(filteredOptions) { option in
                            Button {
                                onSignSelect(option.token)
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(option.token == normalizedSelectedSign
                                            ? Color.accentColor.opacity(0.28)
                                            : subtleSurfaceColor)

                                    optionView(for: option)
                                        .foregroundStyle(.primary)
                                }
                                .frame(height: 42)
                            }
                            .buttonStyle(.plain)
                            .help(option.label.capitalized)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .controlSize(.small)
                .background(ScrollViewAppearanceConfigurator())
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(subtleSurfaceColor)
            )
        }
    }

    private var filteredOptions: [PinboardSignOption] {
        PinboardSignCatalog.filteredOptions(for: selectedTab, query: searchText)
    }

    private var normalizedSelectedSign: String? {
        PinboardSignResolver.normalize(selectedSign)
    }

    private func isSelectedColor(_ hex: String) -> Bool {
        selectedColorHex.caseInsensitiveCompare(hex) == .orderedSame
    }

    private var subtleSurfaceColor: Color {
        adaptiveSurfaceColor(opacity: DesignTokens.Opacity.backgroundSubtle)
    }

    private var mediumSurfaceColor: Color {
        adaptiveSurfaceColor(opacity: DesignTokens.Opacity.backgroundMedium)
    }

    private func adaptiveSurfaceColor(opacity: CGFloat) -> Color {
        colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity)
    }

    private func swatchStrokeColor(isSelected: Bool) -> Color {
        if colorScheme == .dark {
            return Color.white.opacity(isSelected ? 0.98 : 0.58)
        }
        return Color.black.opacity(isSelected ? 0.7 : 0.26)
    }

    @ViewBuilder
    private func optionView(for option: PinboardSignOption) -> some View {
        if selectedTab == .icon {
            Image(systemName: option.token)
                .font(.system(size: 14, weight: .semibold))
        } else {
            Text(option.token)
                .font(.system(size: 18))
        }
    }
}

private struct ScrollViewAppearanceConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureScrollView(from: view, remainingAttempts: 8)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureScrollView(from: nsView, remainingAttempts: 8)
    }

    private func configureScrollView(from view: NSView, remainingAttempts: Int) {
        if let scrollView = findScrollView(from: view) {
            // Use default scroller style (removed .overlay)
            if let scroller = scrollView.verticalScroller {
                scroller.controlSize = .mini
            }
            return
        }

        guard remainingAttempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            configureScrollView(from: view, remainingAttempts: remainingAttempts - 1)
        }
    }

    private func findScrollView(from view: NSView) -> NSScrollView? {
        if let enclosing = view.enclosingScrollView {
            return enclosing
        }

        var current = view.superview
        while let node = current {
            if let scroll = node as? NSScrollView {
                return scroll
            }
            current = node.superview
        }

        return nil
    }
}
