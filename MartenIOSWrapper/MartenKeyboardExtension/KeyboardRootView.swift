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

private enum KeyboardCardMetrics {
    static let cornerRadius: CGFloat = 16
}


@MainActor
final class KeyboardExtensionViewModel: ObservableObject {
    @Published var selectedPinboardID: UUID?
    @Published private(set) var pinboards: [SharedPinboardSummary] = []
    @Published private(set) var items: [SharedClipItemSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    var customPinboards: [SharedPinboardSummary] {
        pinboards.filter { !$0.isSystemMarten }
    }

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
    @State private var copiedItemID: UUID?
    @State private var copiedOverlayTask: Task<Void, Never>?

    private enum CopyButtonState {
        case idle
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
            let interItemSpacing: CGFloat = 6
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
                    pinboardsTopPanel(fullWidth: proxy.size.width)
                        .padding(.vertical, 8)

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

            }
        }
    }

    private func pinboardsTopPanel(fullWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pinboardPill(from: nil)
                ForEach(viewModel.customPinboards) { pinboard in
                    pinboardPill(from: pinboard)
                }
            }
            .padding(.horizontal, 12)
            .frame(minWidth: fullWidth)
        }
    }

    @ViewBuilder
    private func pinboardPill(from pinboard: SharedPinboardSummary?) -> some View {
        let isSelected = viewModel.selectedPinboardID == pinboard?.id
        let isLocked = pinboard.map { lockStateStore.isLocked($0.id) } ?? false
        let canAccess = pinboard.map { lockStateStore.canAccess($0.id) } ?? true

        Button {
            if isLocked && !canAccess, let pb = pinboard {
                Task { @MainActor in
                    let unlocked = await lockStateStore.unlock(pinboardID: pb.id, pinboardName: pb.name)
                    if unlocked {
                        viewModel.selectPinboard(pb.id)
                    }
                }
            } else {
                withAnimation(.spring(duration: 0.26)) {
                    viewModel.selectPinboard(pinboard?.id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                KeyboardPinboardIndicator(
                    colorHex: pinboard?.colorHex ?? "#8E8E93",
                    sign: pinboard?.iconName ?? "tray",
                    size: 24
                )
                
                if isSelected {
                    Text(pinboard?.name ?? "All")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, isSelected ? 12 : 4)
            .padding(.vertical, 4)
            .background(isSelected ? Color.primary.opacity(0.06) : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @Environment(\.colorScheme) private var controlRowColorScheme

    /// iOS-keyboard-style semi-transparent background for the space bar (lighter, like letter keys).
    private var spaceKeyBackground: Color {
        controlRowColorScheme == .dark
            ? Color.white.opacity(0.22)
            : Color.white.opacity(0.85)
    }

    /// iOS-keyboard-style semi-transparent background for utility keys (darker, like shift/delete).
    private var utilityKeyBackground: Color {
        controlRowColorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.06)
    }

    private var bottomControlRow: some View {
        HStack(spacing: 8) {

            Button {
                onInsertText(" ")
                onRecordHeartbeat()
            } label: {
                Text("space")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(spaceKeyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(minWidth: 100, maxWidth: .infinity, minHeight: 44, maxHeight: 44)

            Button {
                handleCopyButtonTap()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(utilityKeyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy to Marten")
            .accessibilityHint("Save selected text to Marten")

            Button {
                onDeleteBackward()
                onRecordHeartbeat()
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(utilityKeyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                onInsertText("\n")
                onRecordHeartbeat()
            } label: {
                Image(systemName: "return")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 66, height: 44)
                    .background(utilityKeyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .padding(.top, 4)
    }

    private func handleCopyButtonTap() {
        Task { @MainActor in
            var didCopy = await onCopySelectionToMarten()
            if !didCopy {
                didCopy = await onCopyClipboardToMarten()
            }
            let feedback = UINotificationFeedbackGenerator()

            if didCopy {
                feedback.notificationOccurred(.success)
                viewModel.refreshSilently()
            } else {
                feedback.notificationOccurred(.error)
            }
        }
    }


    @ViewBuilder
    private func cardButton(for item: SharedClipItemSummary, cardSide: CGFloat) -> some View {
        cardLabel(for: item, cardSide: cardSide)
            .overlay(
                CardCopiedOverlay(isVisible: copiedItemID == item.id)
            )
            .overlay(
                CardDragTapOverlay(
                    item: item,
                    onTap: { handleItemTap(item) },
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
                _ = await pasteImageToPasteboard(item)
            }
            return
        }

        let text = item.insertionText
        guard !text.isEmpty else { return }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        onInsertText(text)
        onRecordHeartbeat()
        showCopiedOverlay(for: item.id)
        Task {
            await viewModel.markItemUsed(item)
        }
    }

    private func showCopiedOverlay(for itemID: UUID) {
        copiedOverlayTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            copiedItemID = itemID
        }
        copiedOverlayTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                copiedItemID = nil
            }
        }
    }

    /// Writes the raw image bytes for `item` to the system pasteboard so the
    /// user can paste it into the focused app. Falls back to a text copy if
    /// the asset file is not available.
    @MainActor
    private func pasteImageToPasteboard(_ item: SharedClipItemSummary) async -> Bool {
        guard let path = item.thumbnailPath,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            if let text = item.primaryText, !text.isEmpty {
                UIPasteboard.general.string = text
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
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
            return false
        }

        UIPasteboard.general.setData(data, forPasteboardType: typeIdentifier)
        onRecordHeartbeat()
        await viewModel.markItemUsed(item)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showCopiedOverlay(for: item.id)
        return true
    }

}

// MARK: - Card drag + tap overlay

/// Transparent UIKit overlay that owns tap and drag for a card.
/// Lifts a snapshot of the underlying card view so the drag preview matches
/// the rendered card instead of the transparent interaction layer.
private struct CardDragTapOverlay: UIViewRepresentable {
    let item: SharedClipItemSummary
    let onTap: () -> Void
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
        view.addGestureRecognizer(tap)

        let drag = UIDragInteraction(delegate: context.coordinator)
        drag.isEnabled = true
        view.addInteraction(drag)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.item = item
        context.coordinator.onTap = onTap
        context.coordinator.onDragBegin = onDragBegin
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(item: item, onTap: onTap, onDragBegin: onDragBegin)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UIDragInteractionDelegate {
        var item: SharedClipItemSummary
        var onTap: () -> Void
        var onDragBegin: () -> Void

        init(item: SharedClipItemSummary, onTap: @escaping () -> Void, onDragBegin: @escaping () -> Void) {
            self.item = item
            self.onTap = onTap
            self.onDragBegin = onDragBegin
        }

        @objc func handleTap() {
            onTap()
        }

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
            previewForLifting dragItem: UIDragItem,
            session: UIDragSession
        ) -> UITargetedDragPreview? {
            guard let overlayView = interaction.view else { return nil }
            let size = overlayView.bounds.size
            guard size.width > 1, size.height > 1 else { return nil }

            guard let previewView = makePreviewSnapshotView(from: overlayView) else { return nil }

            let params = UIDragPreviewParameters()
            params.visiblePath = UIBezierPath(
                roundedRect: CGRect(origin: .zero, size: size),
                cornerRadius: KeyboardCardMetrics.cornerRadius
            )
            params.backgroundColor = .clear

            let anchorView = overlayView.superview ?? overlayView
            let centerInOverlay = CGPoint(x: overlayView.bounds.midX, y: overlayView.bounds.midY)
            let center = anchorView.convert(centerInOverlay, from: overlayView)
            let target = UIDragPreviewTarget(container: anchorView, center: center)
            return UITargetedDragPreview(view: previewView, parameters: params, target: target)
        }

        private func makePreviewSnapshotView(from overlayView: UIView) -> UIView? {
            guard let window = overlayView.window else { return nil }
            let captureRect = overlayView.convert(overlayView.bounds, to: window)
            guard captureRect.width > 1, captureRect.height > 1 else { return nil }

            let renderer = UIGraphicsImageRenderer(size: captureRect.size)
            let image = renderer.image { _ in
                window.drawHierarchy(
                    in: CGRect(
                        x: -captureRect.minX,
                        y: -captureRect.minY,
                        width: window.bounds.width,
                        height: window.bounds.height
                    ),
                    afterScreenUpdates: false
                )
            }

            let imageView = UIImageView(image: image)
            imageView.frame = CGRect(origin: .zero, size: captureRect.size)
            imageView.layer.cornerRadius = KeyboardCardMetrics.cornerRadius
            imageView.layer.cornerCurve = .continuous
            imageView.layer.masksToBounds = true
            return imageView
        }

        private func makeDragItemProvider() -> NSItemProvider? {
            if item.itemType == .image, let path = item.thumbnailPath {
                let url = URL(fileURLWithPath: path)
                let ext = url.pathExtension.lowercased()
                let utType: UTType
                switch ext {
                case "png":         utType = .png
                case "heic":        utType = .heic
                case "heif":        utType = .heif
                case "tiff", "tif": utType = .tiff
                default:            utType = .jpeg
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

private struct CardCopiedOverlay: View {
    let isVisible: Bool

    var body: some View {
        ZStack {
            if isVisible {
                // Main edge-to-edge overlay background
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.black.opacity(0.08))
                    )

                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

                    Text("Copied")
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(0.3)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isVisible)
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
    @State private var linkPreviewResult: KeyboardLinkPreviewImageResult?

    private var pres: KeyboardItemCardPresentation {
        KeyboardItemCardPresentation(item: item, pinboards: pinboards)
    }

    private let cardCornerRadius: CGFloat = KeyboardCardMetrics.cornerRadius
    private let cardPadding: CGFloat = 12
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
                        .padding(.top, 8)

                    Spacer(minLength: 0)
                }

                cardFooter
                    .padding(.horizontal, cardPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
            }
        }
        .background(
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)

                // Subtle color background
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(cardBackgroundColor)

                // Ambient inner gradient for the whole card
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                glowColor.opacity(colorScheme == .dark ? 0.25 : 0.15),
                                glowColor.opacity(colorScheme == .dark ? 0.0 : 0.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .strokeBorder(cardBorderColor, lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
            radius: 14,
            x: 0,
            y: 8
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
                    size: 16,
                    showBackground: false
                )
            }
        }
        .padding(.horizontal, cardPadding)
        .padding(.vertical, 6)
        .frame(minHeight: headerMinHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                UnevenRoundedRectangle(
                    topLeadingRadius: cardCornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cardCornerRadius
                )
                .fill(.ultraThinMaterial)

                UnevenRoundedRectangle(
                    topLeadingRadius: cardCornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cardCornerRadius
                )
                .fill(headerBackgroundColor)
            }
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: cardCornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cardCornerRadius
                )
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.25), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
        )
    }

    private var cardFooter: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(pres.footerLeadingText)
                .font(.system(size: 8))
                .foregroundStyle(tertiaryTextColor)

            Spacer(minLength: 0)

            Text(pres.footerTrailingText)
                .font(.system(size: 8))
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
                switch linkPreviewResult {
                case .banner(let image):
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                case .favicon(let image):
                    linkPreviewPlaceholderBackground
                    let iconSide = min(min(geometry.size.width, geometry.size.height) * 0.44, 56)
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSide, height: iconSide)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                case nil:
                    linkPreviewPlaceholderBackground
                    Image(systemName: "link")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(
                            colorScheme == .dark
                                ? Color.white.opacity(0.35)
                                : Color.black.opacity(0.25)
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .clipped()
    }

    private var linkPreviewPlaceholderBackground: some View {
        Rectangle()
            .fill(
                colorScheme == .dark
                    ? Color.white.opacity(0.08)
                    : Color.black.opacity(0.05)
            )
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

        return Rectangle()
            .fill(background)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                Text(normalizedHex)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
            }
    }

    private var isEdgeToEdgeContent: Bool {
        pres.previewKind == .image || pres.previewKind == .link || pres.previewKind == .color
    }

    private var previewTaskID: String {
        let linkPreviewID = item.linkPreview?.id.uuidString ?? "none"
        let linkPreviewFetchedAt = item.linkPreview.map { Int64($0.fetchedAt.timeIntervalSince1970 * 1000) } ?? 0
        let thumbnailPath = item.thumbnailPath ?? "none"
        return "\(item.id.uuidString)-\(Int64(item.modifiedAt.timeIntervalSince1970 * 1000))-\(thumbnailPath)-\(linkPreviewID)-\(linkPreviewFetchedAt)-\(allowsNetworkFetch)"
    }

    private var glowColor: Color {
        if let pinboardHex = pres.primaryPinboardColorHex,
           let normalized = ColorHex.normalizedHex(from: pinboardHex) {
            return Color(hex: normalized, fallback: .gray)
        }
        return Color.clear
    }

    private var headerBackgroundColor: Color {
        if let pinboardHex = pres.primaryPinboardColorHex,
           let normalizedHex = ColorHex.normalizedHex(from: pinboardHex) {
            return Color(hex: normalizedHex, fallback: .gray).opacity(colorScheme == .dark ? 0.85 : 1.0)
        }
        return Color.clear
    }

    private var headerTextColor: Color {
        if let pinboardHex = pres.primaryPinboardColorHex,
           let normalizedHex = ColorHex.normalizedHex(from: pinboardHex) {
            return colorScheme == .dark ? ColorHex.foregroundColor(for: normalizedHex) : .white
        }
        return .primary
    }

    private var cardBackgroundColor: Color {
        if colorScheme == .light, pres.primaryPinboardColorHex != nil {
             return glowColor.opacity(0.05)
        }

        return colorScheme == .dark
            ? Color(.sRGB, white: 0.10, opacity: 0.4)
            : Color(.sRGB, white: 1.0, opacity: 0.5)
    }

    private var cardBorderColor: AnyShapeStyle {
        let colors = [
            (colorScheme == .light && pres.primaryPinboardColorHex != nil) ? glowColor.opacity(0.8) : Color.white.opacity(colorScheme == .dark ? 0.15 : 0.8),
            (colorScheme == .light && pres.primaryPinboardColorHex != nil) ? glowColor.opacity(0.2) : Color.white.opacity(colorScheme == .dark ? 0.0 : 0.2)
        ]

        return AnyShapeStyle(LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
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
        return colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
    }

    private func loadPreviewAssets() async {
        switch pres.previewKind {
        case .image:
            linkPreviewResult = nil
            thumbnailImage = nil
            thumbnailImage = await KeyboardImagePreviewLoader.shared.loadThumbnail(for: item)
        case .link:
            thumbnailImage = nil
            linkPreviewResult = nil
            linkPreviewResult = await KeyboardLinkBannerImageLoader.shared.loadImage(
                for: item,
                allowsNetworkFetch: allowsNetworkFetch
            )
        default:
            thumbnailImage = nil
            linkPreviewResult = nil
        }
    }
}
