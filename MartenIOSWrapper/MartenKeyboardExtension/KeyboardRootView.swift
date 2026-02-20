import Combine
import MartenCore
import MartenIOSApp
import SwiftUI
import UIKit

private struct KeyboardPinboardIndicator: View {
    let colorHex: String
    var sign: String? = nil
    var size: CGFloat = 24

    private var baseColor: Color {
        Color(hex: colorHex, fallback: .gray)
    }

    private var signColor: Color {
        isDarkBackground ? .white.opacity(0.95) : .black.opacity(0.78)
    }

    private var signShadowColor: Color {
        .black.opacity(isDarkBackground ? 0.22 : 0.28)
    }

    private var signContainerSize: CGFloat {
        max(6, size * 0.72)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(baseColor)

            Circle()
                .strokeBorder(baseColor.opacity(0.96), lineWidth: max(1, size * 0.09))

            if let sign = sign, !sign.isEmpty {
                signView(sign)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func signView(_ sign: String) -> some View {
        if UIImage(systemName: sign) != nil {
            Image(systemName: sign)
                .font(.system(size: size * 0.52, weight: .bold))
                .foregroundStyle(signColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: signContainerSize, height: signContainerSize)
                .offset(y: size * 0.015)
                .shadow(color: signShadowColor, radius: max(0.6, size * 0.11), x: 0, y: 0.45)
        } else {
            Text(sign)
                .font(.system(size: size * 0.56))
                .foregroundStyle(signColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(width: signContainerSize, height: signContainerSize)
                .offset(y: size * 0.015)
                .shadow(color: signShadowColor, radius: max(0.6, size * 0.11), x: 0, y: 0.45)
        }
    }

    private var isDarkBackground: Bool {
        let uiColor = UIColor(hex: colorHex)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        return luminance < 0.56
    }
}

private struct KeyboardSourceAppIconBadge: View {
    let bundleID: String?
    let appName: String?
    let iconData: Data?
    var size: CGFloat = 30

    private static let martenBundleID = "com.hirchyts.marten"
    private static let fallbackBackgroundHex = "#6C757D"

    private struct Style {
        let symbol: String
        let backgroundHex: String
    }

    private var normalizedBundleID: String? {
        let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private var normalizedAppName: String? {
        let trimmed = appName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private var resolvedBundleID: String? {
        if let normalizedBundleID {
            return normalizedBundleID
        }
        guard isMartenAppName else { return nil }
        return Self.martenBundleID
    }

    private var isMartenAppName: Bool {
        guard let normalizedAppName else { return false }
        return normalizedAppName == "marten" || normalizedAppName.contains("marten")
    }

    private var isMartenSource: Bool {
        if let resolvedBundleID {
            return resolvedBundleID == Self.martenBundleID || resolvedBundleID.hasPrefix("\(Self.martenBundleID).")
        }
        return isMartenAppName
    }

    private var style: Style {
        Self.style(bundleID: bundleID, appName: appName)
    }

    private var embeddedIcon: UIImage? {
        guard let iconData, !iconData.isEmpty else { return nil }
        return UIImage(data: iconData)
    }

    private var symbol: String {
        style.symbol
    }

    private var backgroundColor: Color {
        Color(hex: style.backgroundHex)
    }

    static func backgroundHex(bundleID: String?, appName: String?) -> String {
        style(bundleID: bundleID, appName: appName).backgroundHex
    }

    static func foregroundColor(bundleID: String?, appName: String?) -> Color {
        let normalizedHex = ColorHex.normalizedHex(from: backgroundHex(bundleID: bundleID, appName: appName))
            ?? fallbackBackgroundHex
        return ColorHex.foregroundColor(for: normalizedHex)
    }

    private static func style(bundleID: String?, appName: String?) -> Style {
        let normalizedBundleID = normalize(bundleID)
        let normalizedAppName = normalize(appName)

        let resolvedBundleID: String?
        if let normalizedBundleID {
            resolvedBundleID = normalizedBundleID
        } else if isMartenAppName(normalizedAppName) {
            resolvedBundleID = martenBundleID
        } else {
            resolvedBundleID = nil
        }

        let isMartenSource: Bool
        if let resolvedBundleID {
            isMartenSource = resolvedBundleID == martenBundleID
                || resolvedBundleID.hasPrefix("\(martenBundleID).")
        } else {
            isMartenSource = isMartenAppName(normalizedAppName)
        }

        if isMartenSource {
            return Style(symbol: "sparkles", backgroundHex: "#FF2E00")
        }

        guard let resolvedBundleID else {
            return Style(symbol: "app.fill", backgroundHex: fallbackBackgroundHex)
        }

        if resolvedBundleID.contains("safari") {
            return Style(symbol: "safari.fill", backgroundHex: "#0A84FF")
        }
        if resolvedBundleID.contains("mail") {
            return Style(symbol: "envelope.fill", backgroundHex: "#007AFF")
        }
        if resolvedBundleID.contains("messages") {
            return Style(symbol: "message.fill", backgroundHex: "#34C759")
        }
        if resolvedBundleID.contains("notes") {
            return Style(symbol: "note.text", backgroundHex: "#FFD60A")
        }
        if resolvedBundleID.contains("files") {
            return Style(symbol: "folder.fill", backgroundHex: "#4C9CFF")
        }
        if resolvedBundleID.contains("photos") {
            return Style(symbol: "photo.fill", backgroundHex: "#FF9500")
        }
        if resolvedBundleID.contains("chrome") {
            return Style(symbol: "globe", backgroundHex: "#4285F4")
        }

        return Style(symbol: "app.fill", backgroundHex: fallbackBackgroundHex)
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    private static func isMartenAppName(_ value: String?) -> Bool {
        guard let value else { return false }
        return value == "marten" || value.contains("marten")
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(backgroundColor)

            if let embeddedIcon {
                Image(uiImage: embeddedIcon)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.54, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
        )
    }
}

private struct KeyboardStatusChip: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

extension Color {
    init(hex: String, fallback: Color = .gray) {
        let uiColor = UIColor(hex: hex)
        self.init(uiColor: uiColor)
    }
}

extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}


@MainActor
final class KeyboardExtensionViewModel: ObservableObject {
    @Published var selectedPinboardID: UUID?
    @Published private(set) var pinboards: [SharedPinboardSummary] = []
    @Published private(set) var items: [SharedClipItemSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var isPinboardMenuPresented = false

    private let queryService: SharedClipQueryService
    private let commandService: SharedClipCommandService

    init(
        queryService: SharedClipQueryService,
        commandService: SharedClipCommandService
    ) {
        self.queryService = queryService
        self.commandService = commandService
    }

    func load() {
        Task {
            await refreshPinboards()
            await refreshItems(showLoading: true)
        }
    }

    func refresh() {
        Task {
            await refreshItems(showLoading: items.isEmpty)
        }
    }

    func refreshSilently() {
        Task {
            await refreshItems(showLoading: false)
        }
    }

    func selectPinboard(_ id: UUID?) {
        selectedPinboardID = id
        isPinboardMenuPresented = false
    }

    func moveItem(_ item: SharedClipItemSummary, to pinboardID: UUID?) async -> Bool {
        do {
            try await commandService.moveItem(itemID: item.id, toPinboardID: pinboardID)
            await refreshItems(showLoading: false)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteItem(_ item: SharedClipItemSummary) async -> Bool {
        do {
            try await commandService.deleteItem(itemID: item.id)
            await refreshItems(showLoading: false)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func markItemUsed(_ item: SharedClipItemSummary) async {
        try? await commandService.markItemUsed(itemID: item.id)
    }

    private func refreshPinboards() async {
        do {
            pinboards = try await queryService.pinboards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshItems(showLoading: Bool) async {
        if showLoading {
            isLoading = true
        }
        defer {
            if showLoading {
                isLoading = false
            }
        }
        do {
            let fetched = try await queryService.recentItems(
                pinboardID: selectedPinboardID,
                limit: 5000
            )
            withAnimation(.spring(duration: 0.26, bounce: 0)) {
                items = fetched
            }
            errorMessage = nil
        } catch {
            if showLoading {
                items = []
            }
            errorMessage = error.localizedDescription
        }
    }
}

struct KeyboardRootView: View {
    @StateObject var viewModel: KeyboardExtensionViewModel
    let onInsertText: (String) -> Void
    let onDeleteBackward: () -> Void
    let onRecordHeartbeat: () -> Void
    let onCopySelectionToMarten: () async -> Bool
    let onCopyClipboardToMarten: () async -> Bool
    let allowsNetworkFetch: Bool

    @State private var lockStateStore: PinboardLockStateStore
    @State private var copyButtonState: CopyButtonState = .idle
    @State private var previewItem: SharedClipItemSummary?
    @State private var moveDestinationItem: SharedClipItemSummary?

    private enum CopyButtonState {
        case idle
        case copying
        case failure
    }

    init(
        viewModel: KeyboardExtensionViewModel,
        onInsertText: @escaping (String) -> Void,
        onDeleteBackward: @escaping () -> Void,
        onRecordHeartbeat: @escaping () -> Void,
        onCopySelectionToMarten: @escaping () async -> Bool,
        onCopyClipboardToMarten: @escaping () async -> Bool,
        allowsNetworkFetch: Bool
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onInsertText = onInsertText
        self.onDeleteBackward = onDeleteBackward
        self.onRecordHeartbeat = onRecordHeartbeat
        self.onCopySelectionToMarten = onCopySelectionToMarten
        self.onCopyClipboardToMarten = onCopyClipboardToMarten
        self.allowsNetworkFetch = allowsNetworkFetch

        let sharedDefaults = UserDefaults(suiteName: "group.com.hirchyts.marten") ?? .standard
        _lockStateStore = State(initialValue: PinboardLockStateStore(userDefaults: sharedDefaults))
    }

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 12
            let verticalPadding: CGFloat = 8
            let interItemSpacing: CGFloat = 12
            let topBarHeight: CGFloat = 42
            let bottomBarHeight: CGFloat = 56
            let contentMaxHeight = max(0, proxy.size.height - topBarHeight - bottomBarHeight)
            let maxCardSideByHeight = contentMaxHeight - (verticalPadding * 2) - 8
            let visibleCardCount: CGFloat = 2.0
            let availableWidth = max(0, proxy.size.width - (horizontalPadding * 2))
            let spacingTotal = interItemSpacing * max(0, visibleCardCount - 1)
            let maxCardSideByWidth = (availableWidth - spacingTotal) / max(1, visibleCardCount)
            let cardSide = floor(max(150, min(320, maxCardSideByHeight, maxCardSideByWidth)))
            let contentHeight = cardSide + (verticalPadding * 2)
            let rows = [GridItem(.fixed(cardSide), spacing: interItemSpacing)]

            ZStack {
                VStack(spacing: 0) {
                    pinboardHeaderBar
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 4)

                    if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.red.opacity(0.8))
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .frame(height: contentHeight)
                    } else if viewModel.isLoading {
                        VStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Loading...")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: contentHeight)
                    } else if viewModel.items.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "tray")
                                .font(.system(size: 22))
                                .foregroundStyle(.secondary.opacity(0.6))
                            Text("No items")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: contentHeight)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHGrid(rows: rows, spacing: interItemSpacing) {
                                ForEach(viewModel.items) { item in
                                    cardButton(for: item, cardSide: cardSide)
                                }
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.vertical, verticalPadding)
                        }
                        .frame(height: contentHeight)
                    }

                    Spacer(minLength: 0)

                    bottomControlRow
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    onRecordHeartbeat()
                    viewModel.load()
                }
                .onChange(of: viewModel.selectedPinboardID) {
                    viewModel.refresh()
                }
                .onChange(of: viewModel.pinboards) { _, newValue in
                    lockStateStore.reconcile(validPinboardIDs: Set(newValue.map(\.id)))
                }

                if viewModel.isPinboardMenuPresented {
                    VStack {
                        Spacer()
                        pinboardMenuOverlay
                            .padding(.bottom, 60)
                            .padding(.horizontal, 12)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
                }

                if let moveDestinationItem {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.25)) {
                                self.moveDestinationItem = nil
                            }
                        }

                    VStack {
                        Spacer()
                        moveDestinationOverlay(for: moveDestinationItem)
                            .padding(.bottom, 16)
                            .padding(.horizontal, 12)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(120)
                }

                if let previewItem {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.25)) {
                                self.previewItem = nil
                            }
                        }

                    previewOverlay(for: previewItem, cardSide: cardSide)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(140)
                }

            }
        }
    }

    private var bottomControlRow: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    previewItem = nil
                    moveDestinationItem = nil
                    viewModel.isPinboardMenuPresented.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    if let selected = selectedPinboard {
                        KeyboardPinboardIndicator(
                            colorHex: selected.colorHex,
                            sign: selected.iconName,
                            size: 16
                        )
                    } else {
                        KeyboardPinboardIndicator(
                            colorHex: "#007AFF",
                            sign: "tray.full",
                            size: 16
                        )
                    }

                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(
                            viewModel.isPinboardMenuPresented ? .degrees(180) : .degrees(0))
                }
                .frame(height: 44)
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button {
                handleCopyButtonTap()
            } label: {
                Group {
                    if copyButtonState == .copying {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.primary)
                    } else {
                        Image(systemName: copyButtonSymbol)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(copyButtonForeground)
                .frame(width: 44, height: 44)
                .background(copyButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(copyButtonState == .copying)
            .accessibilityLabel("Copy to Marten")
            .accessibilityHint("Save selected text to Marten")

            Button {
                onInsertText(" ")
                onRecordHeartbeat()
            } label: {
                Text("Space")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .frame(minWidth: 80, maxWidth: .infinity, minHeight: 44, maxHeight: 44)

            Button {
                onDeleteBackward()
                onRecordHeartbeat()
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button {
                onInsertText("\n")
                onRecordHeartbeat()
            } label: {
                Image(systemName: "return")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .padding(.top, 4)
    }

    private var copyButtonSymbol: String {
        switch copyButtonState {
        case .idle:
            return "doc.on.doc"
        case .copying:
            return "doc.on.doc"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    private var copyButtonForeground: Color {
        switch copyButtonState {
        case .failure:
            return .white
        default:
            return .primary
        }
    }

    private var copyButtonBackground: Color {
        switch copyButtonState {
        case .idle:
            return Color.primary.opacity(0.05)
        case .copying:
            return Color.primary.opacity(0.09)
        case .failure:
            return .orange
        }
    }

    private func handleCopyButtonTap() {
        guard copyButtonState != .copying else { return }
        copyButtonState = .copying

        Task { @MainActor in
            // Try copying selected text first; if nothing is selected,
            // fall back to reading the system clipboard.
            var didCopy = await onCopySelectionToMarten()
            if !didCopy {
                didCopy = await onCopyClipboardToMarten()
            }
            let feedback = UINotificationFeedbackGenerator()

            if didCopy {
                feedback.notificationOccurred(.success)
                viewModel.refreshSilently()
                copyButtonState = .idle
            } else {
                feedback.notificationOccurred(.error)
                copyButtonState = .failure
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                copyButtonState = .idle
            }
        }
    }

    private var pinboardMenuOverlay: some View {
        VStack(spacing: 0) {
            Button {
                viewModel.selectPinboard(nil)
            } label: {
                HStack(spacing: 12) {
                    KeyboardPinboardIndicator(
                        colorHex: "#007AFF",
                        sign: "tray.full",
                        size: 24
                    )

                    Text("All")
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)

                    Spacer()

                    if viewModel.selectedPinboardID == nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 52)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(customPinboards) { pinboard in
                        let isLocked = lockStateStore.isLocked(pinboard.id)
                        let canAccess = lockStateStore.canAccess(pinboard.id)
                        Button {
                            if isLocked && !canAccess {
                                Task { @MainActor in
                                    let unlocked = await lockStateStore.unlock(
                                        pinboardID: pinboard.id,
                                        pinboardName: pinboard.name
                                    )
                                    guard unlocked else { return }
                                    viewModel.selectPinboard(pinboard.id)
                                }
                            } else {
                                viewModel.selectPinboard(pinboard.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                KeyboardPinboardIndicator(
                                    colorHex: pinboard.colorHex,
                                    sign: pinboard.iconName,
                                    size: 24
                                )

                                HStack(spacing: 8) {
                                    Text(pinboard.name)
                                        .font(.system(size: 16))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    if pinboard.isShared {
                                        KeyboardStatusChip(systemImage: "person.2.fill")
                                    }

                                    if isLocked {
                                        KeyboardStatusChip(
                                            systemImage: canAccess ? "lock.open.fill" : "lock.fill")
                                    }
                                }

                                Spacer()

                                if viewModel.selectedPinboardID == pinboard.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if pinboard.id != customPinboards.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var selectedPinboard: SharedPinboardSummary? {
        guard let id = viewModel.selectedPinboardID else { return nil }
        return viewModel.pinboards.first(where: { $0.id == id })
    }

    private var customPinboards: [SharedPinboardSummary] {
        viewModel.pinboards.filter { !$0.isSystemMarten }
    }

    private var selectedPinboardTitle: String {
        selectedPinboard?.name ?? "All"
    }

    private var itemCountTitle: String {
        let count = viewModel.items.count
        if count == 1 {
            return "1 item"
        }
        return "\(count) items"
    }

    private var pinboardHeaderBar: some View {
        HStack(spacing: 10) {
            Text(selectedPinboardTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(itemCountTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06))
                .clipShape(Capsule())
        }
        .frame(height: 28)
    }

    @ViewBuilder
    private func cardButton(for item: SharedClipItemSummary, cardSide: CGFloat) -> some View {
        let button = Button {
            handleItemTap(item)
        } label: {
            cardLabel(for: item, cardSide: cardSide)
        }
        .buttonStyle(.plain)
        .contextMenu {
            contextMenuContent(for: item)
        } preview: {
            contextMenuPreview(for: item)
        }

        if let dragText = dragText(for: item) {
            button.onDrag {
                onRecordHeartbeat()
                return NSItemProvider(object: dragText as NSString)
            }
        } else {
            button
        }
    }

    @ViewBuilder
    private func cardLabel(for item: SharedClipItemSummary, cardSide: CGFloat) -> some View {
        KeyboardItemCardView(
            item: item,
            pinboards: viewModel.pinboards,
            allowsNetworkFetch: allowsNetworkFetch
        )
        .frame(width: cardSide)
        .contentShape(Rectangle())
    }

    private func dragText(for item: SharedClipItemSummary) -> String? {
        let text = item.insertionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text
    }

    private func handleItemTap(_ item: SharedClipItemSummary) {
        let text = item.insertionText
        guard !text.isEmpty else { return }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        onInsertText(text)
        onRecordHeartbeat()
        Task {
            await viewModel.markItemUsed(item)
        }
    }

    private func contextActionMenuButton(
        for action: ItemCardContextAction,
        item: SharedClipItemSummary,
        compactTitle: Bool = false
    ) -> some View {
        Button(role: action == .delete ? .destructive : nil) {
            DispatchQueue.main.async {
                self.handleContextAction(action, item: item)
            }
        } label: {
            Label(contextActionTitle(for: action, compact: compactTitle), systemImage: action.systemImage)
                .font(.system(size: 12, weight: .medium))
                .imageScale(.small)
        }
        .controlSize(.small)
    }

    private func contextActionTitle(for action: ItemCardContextAction, compact: Bool) -> String {
        if action == .copyPlainText {
            return compact ? "Plain" : "Copy Plain Text"
        }
        return action.title
    }

    @ViewBuilder
    private func contextMenuContent(for item: SharedClipItemSummary) -> some View {
        let orderedActions = ItemCardContextAction.ordered
        let keyboardActions = orderedActions.filter { $0 != .preview && $0 != .share }
        let nonDeleteActions = keyboardActions.filter { $0 != .delete }

        ForEach(nonDeleteActions, id: \.self) { action in
            contextActionMenuButton(
                for: action,
                item: item,
                compactTitle: action == .copyPlainText
            )
        }

        if keyboardActions.contains(.delete) {
            Divider()
            contextActionMenuButton(for: .delete, item: item)
        }
    }

    private func contextMenuPreview(for item: SharedClipItemSummary) -> some View {
        KeyboardContextPreviewCard(
            item: item,
            pinboards: viewModel.pinboards
        )
    }

    private func handleContextAction(_ action: ItemCardContextAction, item: SharedClipItemSummary) {
        switch action {
        case .copy:
            copyItemToPasteboard(item)
        case .copyPlainText:
            copyItemToPasteboard(item, asPlainText: true)
        case .preview:
            handlePreviewAction(for: item)
        case .togglePin:
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.warning)
        case .share:
            break
        case .moveToPinboard:
            withAnimation(.spring(duration: 0.25)) {
                viewModel.isPinboardMenuPresented = false
                previewItem = nil
                moveDestinationItem = item
            }
        case .delete:
            viewModel.isPinboardMenuPresented = false
            moveDestinationItem = nil
            previewItem = nil
            Task { @MainActor in
                let didDelete = await viewModel.deleteItem(item)
                UINotificationFeedbackGenerator().notificationOccurred(didDelete ? .success : .error)
            }
        }
    }

    private func copyItemToPasteboard(
        _ item: SharedClipItemSummary,
        asPlainText: Bool = false
    ) {
        guard let text = copyText(for: item, asPlainText: asPlainText) else {
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.error)
            return
        }

        UIPasteboard.general.string = text
        onRecordHeartbeat()
        Task {
            await viewModel.markItemUsed(item)
        }

        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(.success)
    }

    private func copyText(for item: SharedClipItemSummary, asPlainText _: Bool) -> String? {
        let plainText = item.plainText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let plainText, !plainText.isEmpty {
            return plainText
        }

        let fallbackText = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fallbackText, !fallbackText.isEmpty {
            return fallbackText
        }

        return nil
    }

    private func handlePreviewAction(for item: SharedClipItemSummary) {
        guard supportsPreview(item) else {
            copyItemToPasteboard(item)
            return
        }

        withAnimation(.spring(duration: 0.25)) {
            viewModel.isPinboardMenuPresented = false
            moveDestinationItem = nil
            previewItem = item
        }
    }

    private func supportsPreview(_ item: SharedClipItemSummary) -> Bool {
        switch item.itemType {
        case .text, .richText, .image, .code, .url:
            return true
        default:
            return false
        }
    }


    private func previewOverlay(for item: SharedClipItemSummary, cardSide: CGFloat) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                HStack {
                    Text("Preview")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("Done") {
                        withAnimation(.spring(duration: 0.25)) {
                            previewItem = nil
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .buttonStyle(.plain)
                }

                KeyboardItemCardView(
                    item: item,
                    pinboards: viewModel.pinboards,
                    allowsNetworkFetch: allowsNetworkFetch
                )
                .frame(width: min(proxySafePreviewWidth(cardSide), 340))
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        }
    }

    private func proxySafePreviewWidth(_ cardSide: CGFloat) -> CGFloat {
        max(220, cardSide + 28)
    }

    private func moveDestinationOverlay(for item: SharedClipItemSummary) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Move to Pinboard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        moveDestinationItem = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Button {
                Task { @MainActor in
                    await performMove(item, to: nil)
                }
            } label: {
                HStack(spacing: 12) {
                    KeyboardPinboardIndicator(
                        colorHex: "#007AFF",
                        sign: "tray.full",
                        size: 24
                    )
                    Text("All")
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                    Spacer()

                    if isInAllPinboard(item) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 52)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(customPinboards) { pinboard in
                        let isLocked = lockStateStore.isLocked(pinboard.id)
                        let canAccess = lockStateStore.canAccess(pinboard.id)
                        Button {
                            if isLocked && !canAccess {
                                Task { @MainActor in
                                    let unlocked = await lockStateStore.unlock(
                                        pinboardID: pinboard.id,
                                        pinboardName: pinboard.name
                                    )
                                    guard unlocked else { return }
                                    await performMove(item, to: pinboard.id)
                                }
                            } else {
                                Task { @MainActor in
                                    await performMove(item, to: pinboard.id)
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                KeyboardPinboardIndicator(
                                    colorHex: pinboard.colorHex,
                                    sign: pinboard.iconName,
                                    size: 24
                                )

                                HStack(spacing: 8) {
                                    Text(pinboard.name)
                                        .font(.system(size: 16))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    if pinboard.isShared {
                                        KeyboardStatusChip(systemImage: "person.2.fill")
                                    }

                                    if isLocked {
                                        KeyboardStatusChip(
                                            systemImage: canAccess ? "lock.open.fill" : "lock.fill"
                                        )
                                    }
                                }

                                Spacer()

                                if item.pinboardIDs.contains(pinboard.id) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if pinboard.id != customPinboards.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
    }

    private func isInAllPinboard(_ item: SharedClipItemSummary) -> Bool {
        let customPinboardIDs = Set(customPinboards.map(\.id))
        return Set(item.pinboardIDs).isDisjoint(with: customPinboardIDs)
    }

    private func performMove(_ item: SharedClipItemSummary, to pinboardID: UUID?) async {
        let didMove = await viewModel.moveItem(item, to: pinboardID)
        let feedback = UINotificationFeedbackGenerator()
        feedback.notificationOccurred(didMove ? .success : .error)

        if didMove {
            withAnimation(.spring(duration: 0.25)) {
                moveDestinationItem = nil
            }
        }
    }
}

private struct KeyboardTransparencyGrid: View {
    var squareSize: CGFloat = 6
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let light = colorScheme == .dark
                ? Color.white.opacity(0.10)
                : Color.black.opacity(0.06)
            let dark = colorScheme == .dark
                ? Color.white.opacity(0.18)
                : Color.black.opacity(0.12)

            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                while x < size.width {
                    let color = ((row + col) % 2 == 0) ? light : dark
                    context.fill(
                        Path(CGRect(x: x, y: y, width: squareSize, height: squareSize)),
                        with: .color(color)
                    )
                    x += squareSize
                    col += 1
                }
                y += squareSize
                row += 1
            }
        }
    }
}

private struct KeyboardItemCardPresentation {
    let title: String
    let headerSubtitle: String?
    let footerLeadingText: String
    let footerTrailingText: String

    let previewKind: PreviewKind
    let snippet: String?
    let urlHost: String?
    let colorHex: String?
    let fileName: String?
    let fileSize: String?

    let primaryPinboardColorHex: String?
    let primaryPinboardSign: String?
    let primaryPinboardID: UUID?

    let sourceAppBundleID: String?
    let sourceAppName: String?
    let sourceAppIconData: Data?

    enum PreviewKind {
        case text, richText, image, link, file, code, color, mixed
    }

    init(item: SharedClipItemSummary, pinboards: [SharedPinboardSummary]) {
        let primaryPinboard = pinboards.first { pinboard in
            !pinboard.isSystemMarten && item.pinboardIDs.contains(pinboard.id)
        }

        self.primaryPinboardID = primaryPinboard?.id

        self.primaryPinboardColorHex = primaryPinboard?.colorHex
        self.primaryPinboardSign = primaryPinboard?.iconName

        self.sourceAppName = Self.sourceLabel(item)
        self.sourceAppBundleID = item.sourceAppBundleID
        self.sourceAppIconData = item.sourceAppIconData

        self.title = Self.defaultTitle(for: item.itemType)
        self.headerSubtitle = primaryPinboard?.name ?? Self.sourceLabel(item)
        self.footerLeadingText = Self.relativeTime(from: item.modifiedAt)
        self.fileSize = Self.byteCountString(for: item.byteCount)
        self.fileName = item.fileName ?? Self.fileName(fromPathText: item.primaryText)

        let normalizedInsertionText = Self.normalizedText(item.insertionText)
        let linkHost = item.linkPreview?.siteName ?? normalizedInsertionText.flatMap { URL(string: $0)?.host }
        self.urlHost = linkHost

        let resolvedColorHex = item.colorHex ?? normalizedInsertionText.flatMap(ColorHex.normalizedHex(from:))
        self.colorHex = resolvedColorHex

        switch item.itemType {
        case .url:
            self.snippet = Self.normalizedText(item.linkPreview?.title) ?? normalizedInsertionText
        case .color:
            self.snippet = resolvedColorHex ?? normalizedInsertionText
        case .image, .file:
            self.snippet = nil
        default:
            self.snippet = normalizedInsertionText
        }

        let statsLabel = Self.statsLabel(for: item, snippet: self.snippet)
        self.footerTrailingText = item.itemType == .url ? (linkHost ?? "URL") : statsLabel

        switch item.itemType {
        case .text: self.previewKind = .text
        case .richText: self.previewKind = .richText
        case .image: self.previewKind = .image
        case .url: self.previewKind = .link
        case .file: self.previewKind = .file
        case .code: self.previewKind = .code
        case .color: self.previewKind = .color
        case .mixed: self.previewKind = .mixed
        }
    }

    private static func defaultTitle(for type: ItemType) -> String {
        switch type {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .file: return "File"
        case .url: return "Link"
        case .code: return "Code"
        case .color: return "Color"
        case .mixed: return "Item"
        }
    }

    private static func sourceLabel(_ item: SharedClipItemSummary) -> String? {
        if let sourceAppName = normalizedText(item.sourceAppName) {
            return sourceAppName
        }

        guard let bundleID = normalizedText(item.sourceAppBundleID) else { return nil }
        if let suffix = bundleID.split(separator: ".").last {
            return String(suffix)
        }
        return bundleID
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "now"
        }
        if interval < 3600 {
            return "\(Int(interval / 60))m"
        }
        if interval < 86400 {
            return "\(Int(interval / 3600))h"
        }
        return "\(Int(interval / 86400))d"
    }

    private static func byteCountString(for count: Int64) -> String? {
        guard count > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private static func fileName(fromPathText value: String?) -> String? {
        guard let raw = normalizedText(value) else { return nil }
        return URL(fileURLWithPath: raw).lastPathComponent
    }

    private static func statsLabel(for item: SharedClipItemSummary, snippet: String?) -> String {
        switch item.itemType {
        case .text, .richText, .code:
            let count = snippet?.count ?? 0
            return "\(count) chars"
        case .color:
            return "Color"
        default:
            return byteCountString(for: item.byteCount) ?? defaultTitle(for: item.itemType)
        }
    }
}

private struct KeyboardContextPreviewCard: View {
    let item: SharedClipItemSummary
    let pinboards: [SharedPinboardSummary]

    private var pres: KeyboardItemCardPresentation {
        KeyboardItemCardPresentation(item: item, pinboards: pinboards)
    }

    private let cardCornerRadius: CGFloat = 7
    private let cardPadding: CGFloat = 8
    private let headerMinHeight: CGFloat = 22

    var body: some View {
        header
            .frame(width: 170, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(headerBackgroundColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(headerBorderColor, lineWidth: 0.5)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(pres.title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(headerTextColor)
                    .lineLimit(1)

                if let subtitle = pres.headerSubtitle {
                    Text(subtitle)
                        .font(.system(size: 6.5, weight: .medium))
                        .foregroundStyle(headerTextColor.opacity(0.74))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let colorHex = pres.primaryPinboardColorHex {
                KeyboardPinboardIndicator(
                    colorHex: colorHex,
                    sign: pres.primaryPinboardSign,
                    size: 14
                )
            } else {
                KeyboardSourceAppIconBadge(
                    bundleID: pres.sourceAppBundleID,
                    appName: pres.sourceAppName,
                    iconData: pres.sourceAppIconData,
                    size: 14
                )
            }
        }
        .padding(.horizontal, cardPadding)
        .padding(.vertical, 4)
        .frame(minHeight: headerMinHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerBackgroundColor: Color {
        if let pinboardHex = pres.primaryPinboardColorHex,
           let normalizedHex = ColorHex.normalizedHex(from: pinboardHex) {
            return Color(hex: normalizedHex, fallback: .gray).opacity(0.96)
        }
        let hex = KeyboardSourceAppIconBadge.backgroundHex(
            bundleID: pres.sourceAppBundleID,
            appName: pres.sourceAppName
        )
        return Color(hex: hex, fallback: .gray).opacity(0.94)
    }

    private var headerTextColor: Color {
        if let pinboardHex = pres.primaryPinboardColorHex,
           let normalizedHex = ColorHex.normalizedHex(from: pinboardHex) {
            return ColorHex.foregroundColor(for: normalizedHex)
        }
        return KeyboardSourceAppIconBadge.foregroundColor(
            bundleID: pres.sourceAppBundleID,
            appName: pres.sourceAppName
        )
    }

    private var headerBorderColor: Color {
        headerTextColor.opacity(0.28)
    }
}

private struct KeyboardItemCardView: View {
    let item: SharedClipItemSummary
    let pinboards: [SharedPinboardSummary]
    let allowsNetworkFetch: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var thumbnailImage: UIImage?
    @State private var linkPreviewImage: UIImage?

    private var pres: KeyboardItemCardPresentation {
        KeyboardItemCardPresentation(item: item, pinboards: pinboards)
    }

    private let cardCornerRadius: CGFloat = 12
    private let cardPadding: CGFloat = 8
    private let headerMinHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader

            VStack(alignment: .leading, spacing: 0) {
                if isEdgeToEdgeContent {
                    previewContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    previewContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, cardPadding)
                        .padding(.top, 4)

                    Spacer(minLength: 0)
                }

                cardFooter
                    .padding(.horizontal, cardPadding)
                    .padding(.top, 2)
                    .padding(.bottom, cardPadding)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(cardBorderColor, lineWidth: 0.5)
        )
        .aspectRatio(1, contentMode: .fit)
        .task(id: previewTaskID) {
            await loadPreviewAssets()
        }
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(pres.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(headerTextColor)
                    .lineLimit(1)

                if let subtitle = pres.headerSubtitle {
                    Text(subtitle)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(headerTextColor.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if let colorHex = pres.primaryPinboardColorHex {
                KeyboardPinboardIndicator(
                    colorHex: colorHex,
                    sign: pres.primaryPinboardSign,
                    size: 16
                )
            } else {
                KeyboardSourceAppIconBadge(
                    bundleID: pres.sourceAppBundleID,
                    appName: pres.sourceAppName,
                    iconData: pres.sourceAppIconData,
                    size: 16
                )
            }
        }
        .padding(.horizontal, cardPadding)
        .padding(.vertical, 4)
        .frame(minHeight: headerMinHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: cardCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: cardCornerRadius
            )
            .fill(headerBackgroundColor)
        )
    }

    private var cardFooter: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(pres.footerLeadingText)
                .font(.system(size: 9))
                .foregroundStyle(tertiaryTextColor)

            Spacer(minLength: 0)

            Text(pres.footerTrailingText)
                .font(.system(size: 9))
                .foregroundStyle(tertiaryTextColor)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch pres.previewKind {
        case .text, .richText, .mixed:
            Text(pres.snippet ?? "")
                .font(.system(size: 11))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .code:
            Text(pres.snippet ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .link:
            linkPreview
        case .image:
            imagePreview
        case .file:
            filePreview
        case .color:
            colorPreview
        }
    }

    private var imagePreview: some View {
        ZStack {
            KeyboardTransparencyGrid(squareSize: 8)

            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var linkPreview: some View {
        GeometryReader { geometry in
            ZStack {
                if let linkPreviewImage {
                    Image(uiImage: linkPreviewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.08)
                                : Color.black.opacity(0.05)
                        )

                    VStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(.secondary)

                        if let host = pres.urlHost {
                            Text(host)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
    }

    private var filePreview: some View {
        VStack(spacing: 3) {
            Spacer(minLength: 0)

            Image(systemName: "doc.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(secondaryTextColor)

            if let fileName = pres.fileName {
                Text(fileName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            if let fileSize = pres.fileSize {
                Text(fileSize)
                    .font(.system(size: 8))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var colorPreview: some View {
        let hex = pres.colorHex ?? "#808080"
        let normalizedHex = ColorHex.normalizedHex(from: hex) ?? "#808080"
        let background = Color(hex: normalizedHex, fallback: .gray)
        let foreground = ColorHex.foregroundColor(for: normalizedHex)

        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(background)
            .frame(height: 44)
            .overlay {
                Text(normalizedHex)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
            }
    }

    private var isEdgeToEdgeContent: Bool {
        pres.previewKind == .image || pres.previewKind == .link
    }

    private var previewTaskID: String {
        let linkPreviewID = item.linkPreview?.id.uuidString ?? "none"
        let linkPreviewFetchedAt = item.linkPreview.map { Int64($0.fetchedAt.timeIntervalSince1970 * 1000) } ?? 0
        let thumbnailPath = item.thumbnailPath ?? "none"
        return "\(item.id.uuidString)-\(Int64(item.modifiedAt.timeIntervalSince1970 * 1000))-\(thumbnailPath)-\(linkPreviewID)-\(linkPreviewFetchedAt)-\(allowsNetworkFetch)"
    }

    private var headerBackgroundColor: Color {
        if let pinboardHex = pres.primaryPinboardColorHex,
           let normalizedHex = ColorHex.normalizedHex(from: pinboardHex) {
            return Color(hex: normalizedHex, fallback: .gray).opacity(0.96)
        }
        let hex = KeyboardSourceAppIconBadge.backgroundHex(
            bundleID: pres.sourceAppBundleID,
            appName: pres.sourceAppName
        )
        return Color(hex: hex, fallback: .gray).opacity(0.94)
    }

    private var headerTextColor: Color {
        if let pinboardHex = pres.primaryPinboardColorHex,
           let normalizedHex = ColorHex.normalizedHex(from: pinboardHex) {
            return ColorHex.foregroundColor(for: normalizedHex)
        }
        return KeyboardSourceAppIconBadge.foregroundColor(
            bundleID: pres.sourceAppBundleID,
            appName: pres.sourceAppName
        )
    }

    private var cardBackgroundColor: Color {
        if pres.previewKind == .color,
           let colorHex = pres.colorHex,
           let normalizedHex = ColorHex.normalizedHex(from: colorHex) {
            return Color(hex: normalizedHex, fallback: .gray)
        }

        return colorScheme == .dark
            ? Color(.sRGB, white: 0.04, opacity: 0.72)
            : Color(.sRGB, white: 0.96, opacity: 0.9)
    }

    private var cardBorderColor: Color {
        if let pinboardHex = pres.primaryPinboardColorHex,
           let normalizedHex = ColorHex.normalizedHex(from: pinboardHex) {
            return Color(hex: normalizedHex, fallback: .gray).opacity(0.35)
        }

        if pres.previewKind == .color,
           let colorHex = pres.colorHex,
           let normalizedHex = ColorHex.normalizedHex(from: colorHex) {
            return ColorHex.foregroundColor(for: normalizedHex).opacity(0.3)
        }

        return colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.12)
    }

    private var primaryTextColor: Color {
        if pres.previewKind == .color,
           let colorHex = pres.colorHex,
           let normalizedHex = ColorHex.normalizedHex(from: colorHex) {
            return ColorHex.foregroundColor(for: normalizedHex)
        }
        return colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.9)
    }

    private var secondaryTextColor: Color {
        if pres.previewKind == .color,
           let colorHex = pres.colorHex,
           let normalizedHex = ColorHex.normalizedHex(from: colorHex) {
            return ColorHex.foregroundColor(for: normalizedHex).opacity(0.8)
        }
        return colorScheme == .dark ? Color.white.opacity(0.75) : Color.black.opacity(0.75)
    }

    private var tertiaryTextColor: Color {
        if pres.previewKind == .color,
           let colorHex = pres.colorHex,
           let normalizedHex = ColorHex.normalizedHex(from: colorHex) {
            return ColorHex.foregroundColor(for: normalizedHex).opacity(0.7)
        }
        return colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
    }

    private func loadPreviewAssets() async {
        switch pres.previewKind {
        case .image:
            linkPreviewImage = nil
            thumbnailImage = nil
            thumbnailImage = await KeyboardImagePreviewLoader.shared.loadThumbnail(for: item)
        case .link:
            thumbnailImage = nil
            linkPreviewImage = nil
            linkPreviewImage = await KeyboardLinkBannerImageLoader.shared.loadImage(
                for: item,
                allowsNetworkFetch: allowsNetworkFetch
            )
        default:
            thumbnailImage = nil
            linkPreviewImage = nil
        }
    }
}
