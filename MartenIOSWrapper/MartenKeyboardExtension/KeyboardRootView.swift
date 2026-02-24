import Combine
import MartenCore
import MartenIOSApp
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @State private var activeToast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var contextMenuItem: SharedClipItemSummary?

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
            let topBarHeight: CGFloat = 36
            let bottomBarHeight: CGFloat = 56
            let contentMaxHeight = max(0, proxy.size.height - topBarHeight - bottomBarHeight)
            let maxCardSideByHeight = contentMaxHeight - (verticalPadding * 2) - 8
            let visibleCardCount: CGFloat = 2.0
            let availableWidth = max(0, proxy.size.width - (horizontalPadding * 2))
            let spacingTotal = interItemSpacing * max(0, visibleCardCount - 1)
            let maxCardSideByWidth = (availableWidth - spacingTotal) / max(1, visibleCardCount)
            let cardSide = floor(max(40, min(320, maxCardSideByHeight, maxCardSideByWidth)))
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
                        .scrollClipDisabled()
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
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.2)) {
                                viewModel.isPinboardMenuPresented = false
                            }
                        }
                        .zIndex(99)

                    VStack(spacing: 0) {
                        Spacer()
                        HStack(alignment: .bottom, spacing: 0) {
                            pinboardMenuOverlay
                                .frame(maxWidth: 280)
                            Spacer(minLength: 0)
                        }
                        .padding(.bottom, 64)
                        .padding(.horizontal, 12)
                    }
                    .transition(
                        .scale(scale: 0.82, anchor: .bottomLeading)
                        .combined(with: .opacity)
                    )
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

                if contextMenuItem != nil {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.2)) {
                                contextMenuItem = nil
                            }
                        }
                        .zIndex(148)
                }

                if let item = contextMenuItem {
                    VStack(spacing: 0) {
                        Spacer()
                        contextMenuPanel(for: item)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 60)
                    }
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                    .zIndex(149)
                }

                if let message = activeToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(message)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.black.opacity(0.82)))
                        .padding(.bottom, 64)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                    .zIndex(200)
                }

            }
        }
    }

    private var bottomControlRow: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.22, bounce: 0.1)) {
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
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .modifier(PinboardMenuGlassModifier())
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

    private func cardButton(for item: SharedClipItemSummary, cardSide: CGFloat) -> some View {
        cardLabel(for: item, cardSide: cardSide)
            .overlay(
                CardInteractionOverlay(
                    item: item,
                    onTap: { handleItemTap(item) },
                    onLongPress: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(duration: 0.2, bounce: 0)) {
                            previewItem = nil
                            moveDestinationItem = nil
                            viewModel.isPinboardMenuPresented = false
                            contextMenuItem = item
                        }
                    },
                    onDragBegin: { onRecordHeartbeat() }
                )
            )
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

    private func handleItemTap(_ item: SharedClipItemSummary) {
        if item.itemType == .image {
            // Images cannot be injected via insertText; copy image data to the
            // pasteboard instead so the user can paste it in the target app.
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            Task {
                await pasteImageToPasteboard(item)
            }
            return
        }

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

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            activeToast = message
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                activeToast = nil
            }
        }
    }

    /// Writes the raw image bytes for `item` to the system pasteboard so the
    /// user can paste it into the focused app. Falls back to a text copy if
    /// the asset file is not available.
    private func pasteImageToPasteboard(_ item: SharedClipItemSummary) async {
        guard let path = item.thumbnailPath,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            if let text = item.primaryText, !text.isEmpty {
                UIPasteboard.general.string = text
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        let typeIdentifier: String
        switch ext {
        case "png":  typeIdentifier = UTType.png.identifier
        case "heic": typeIdentifier = UTType.heic.identifier
        case "heif": typeIdentifier = UTType.heif.identifier
        case "tiff", "tif": typeIdentifier = UTType.tiff.identifier
        default:     typeIdentifier = UTType.jpeg.identifier
        }

        // Read image bytes off the main thread to avoid blocking.
        let data = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value

        guard let data, !data.isEmpty else {
            if let text = item.primaryText, !text.isEmpty {
                UIPasteboard.general.string = text
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        UIPasteboard.general.setData(data, forPasteboardType: typeIdentifier)
        onRecordHeartbeat()
        await viewModel.markItemUsed(item)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showToast("Image copied to clipboard")
    }

    private func contextMenuPanel(for item: SharedClipItemSummary) -> some View {
        let actions: [ItemCardContextAction] = [.copy, .copyPlainText, .moveToPinboard]
        return VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element) { idx, action in
                Button {
                    withAnimation(.spring(duration: 0.2)) { contextMenuItem = nil }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        handleContextAction(action, item: item)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .frame(width: 24, alignment: .center)
                        Text(action.title)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx < actions.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }

            Divider()

            Button {
                withAnimation(.spring(duration: 0.2)) { contextMenuItem = nil }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    handleContextAction(.delete, item: item)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: ItemCardContextAction.delete.systemImage)
                        .font(.system(size: 15))
                        .foregroundStyle(.red)
                        .frame(width: 24, alignment: .center)
                    Text(ItemCardContextAction.delete.title)
                        .font(.system(size: 16))
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .modifier(PinboardMenuGlassModifier())
    }

    private func handleContextAction(_ action: ItemCardContextAction, item: SharedClipItemSummary) {
        switch action {
        case .copy:
            copyItemToPasteboard(item)
        case .copyPlainText:
            copyItemToPasteboard(item, asPlainText: true)
        case .preview:
            handlePreviewAction(for: item)
        case .edit:
            break
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
        if item.itemType == .image && !asPlainText {
            Task {
                await pasteImageToPasteboard(item)
            }
            return
        }

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
        showToast(asPlainText ? "Copied as plain text" : "Copied")
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

// MARK: - Card interaction overlay

/// Transparent UIKit overlay that owns tap, long-press, and drag gestures for a card.
/// Using UIKit gesture recognizers directly avoids conflicts that arise when SwiftUI's
/// `.onDrag` wrapper prevents `.onLongPressGesture` from firing in a keyboard extension.
private struct CardInteractionOverlay: UIViewRepresentable {
    let item: SharedClipItemSummary
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onDragBegin: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        tap.delegate = context.coordinator

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.45
        longPress.delegate = context.coordinator

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)

        let drag = UIDragInteraction(delegate: context.coordinator)
        drag.isEnabled = true
        view.addInteraction(drag)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.item = item
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        context.coordinator.onDragBegin = onDragBegin
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(item: item, onTap: onTap, onLongPress: onLongPress, onDragBegin: onDragBegin)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UIDragInteractionDelegate {
        var item: SharedClipItemSummary
        var onTap: () -> Void
        var onLongPress: () -> Void
        var onDragBegin: () -> Void
        private var longPressDidFire = false

        init(
            item: SharedClipItemSummary,
            onTap: @escaping () -> Void,
            onLongPress: @escaping () -> Void,
            onDragBegin: @escaping () -> Void
        ) {
            self.item = item
            self.onTap = onTap
            self.onLongPress = onLongPress
            self.onDragBegin = onDragBegin
        }

        @objc func handleTap() {
            guard !longPressDidFire else { longPressDidFire = false; return }
            onTap()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            longPressDidFire = true
            onLongPress()
        }

        // Allow our tap/long-press to coexist with the drag interaction's internal recognizer.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        // MARK: UIDragInteractionDelegate

        func dragInteraction(
            _ interaction: UIDragInteraction,
            itemsForBeginning session: UIDragSession
        ) -> [UIDragItem] {
            onDragBegin()
            guard let provider = makeDragItemProvider() else { return [] }
            return [UIDragItem(itemProvider: provider)]
        }

        func dragInteraction(
            _ interaction: UIDragInteraction,
            previewForLifting item: UIDragItem,
            session: UIDragSession
        ) -> UITargetedDragPreview? {
            guard let overlayView = interaction.view else { return nil }
            let size = overlayView.bounds.size
            guard size.width > 0 else { return nil }

            // Walk up the hierarchy to find the container that holds both
            // the card visual and our transparent overlay. SwiftUI's .overlay()
            // modifier creates a parent that has the base content and overlay
            // as separate children — it's the first ancestor with the same
            // bounds as the card and more than one subview.
            var cardContainer: UIView = overlayView
            var candidate = overlayView.superview
            while let c = candidate {
                if abs(c.bounds.width - size.width) < 1,
                   abs(c.bounds.height - size.height) < 1,
                   c.subviews.count >= 2 {
                    cardContainer = c
                    break
                }
                candidate = c.superview
            }

            // Render the already-displayed card layer into an image.
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { _ in
                cardContainer.layer.render(in: UIGraphicsGetCurrentContext()!)
            }
            let imageView = UIImageView(image: image)
            imageView.frame = CGRect(origin: .zero, size: size)

            let params = UIDragPreviewParameters()
            params.visiblePath = UIBezierPath(roundedRect: imageView.bounds, cornerRadius: 12)
            params.backgroundColor = .clear

            let anchorView = overlayView.superview ?? overlayView
            let center = CGPoint(x: anchorView.bounds.midX, y: anchorView.bounds.midY)
            let target = UIDragPreviewTarget(container: anchorView, center: center)
            return UITargetedDragPreview(view: imageView, parameters: params, target: target)
        }

        private func makeDragItemProvider() -> NSItemProvider? {
            if item.itemType == .image, let path = item.thumbnailPath {
                let url = URL(fileURLWithPath: path)
                let ext = url.pathExtension.lowercased()
                let utType: UTType
                switch ext {
                case "png":        utType = .png
                case "heic":       utType = .heic
                case "heif":       utType = .heif
                case "tiff", "tif": utType = .tiff
                default:           utType = .jpeg
                }
                let provider = NSItemProvider()
                provider.registerDataRepresentation(
                    forTypeIdentifier: utType.identifier,
                    visibility: .all
                ) { completion in
                    DispatchQueue.global(qos: .userInitiated).async {
                        if let data = try? Data(contentsOf: url) {
                            completion(data, nil)
                        } else {
                            completion(nil, CocoaError(.fileReadNoSuchFile))
                        }
                    }
                    return nil
                }
                return provider
            }
            let text = item.insertionText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return NSItemProvider(object: text as NSString)
        }
    }
}

private struct PinboardMenuGlassModifier: ViewModifier {
    private let cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
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
                SourceAppIconBadge(
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
        return SourceAppIconDescriptor.resolve(
            bundleID: pres.sourceAppBundleID,
            appName: pres.sourceAppName
        ).backgroundColor.opacity(0.94)
    }

    private var headerTextColor: Color {
        if let pinboardHex = pres.primaryPinboardColorHex,
           let normalizedHex = ColorHex.normalizedHex(from: pinboardHex) {
            return ColorHex.foregroundColor(for: normalizedHex)
        }
        return SourceAppIconDescriptor.resolve(
            bundleID: pres.sourceAppBundleID,
            appName: pres.sourceAppName
        ).foregroundColor
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
