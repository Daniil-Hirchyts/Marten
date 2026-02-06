import ClipboardCore
import ClipboardMacServices
import CoreData
import OSLog
import SwiftUI

private struct ScrollViewBoundsKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty {
            value = next
        }
    }
}

struct PinboardTabBar: View {
    let tabSpacing: CGFloat = 12
    let placeholderWidth: CGFloat = 3
    let localCoordinateSpaceName = "PinboardBarLocalSpace"
    let scrollSpaceName = "PinboardScrollSpace"
    let headerButtonSize: CGFloat = 30
    let headerButtonIconSize: CGFloat = 14
    let tabContentHeight: CGFloat = 20
    let tabVerticalPadding: CGFloat = 5
    let tabHorizontalPadding: CGFloat = 10
    let minTabWidth: CGFloat = 60
    let maxTabWidth: CGFloat = 160
    let maxPinboardNameLength = 22

    let pinboards: [Pinboard]
    let selectedID: UUID?
    let isLocked: (Pinboard) -> Bool
    let isUnlocked: (Pinboard) -> Bool
    @Binding var editingID: NSManagedObjectID?
    @Binding var isCreatePopoverPresented: Bool
    @ViewBuilder let createPopoverContent: () -> AnyView
    
    @Binding var draftName: String
    @Binding var draftColor: String
    @Binding var draftIcon: String?
    var isGlobalDragActive: Bool = false
    let window: NSWindow?
    var onPreviewUpdate: ((PinboardDragPreviewData?) -> Void)? = nil

    let onSelect: (UUID?) -> Void
    let onCreate: () -> Void
    let onSetLockEnabled: (Pinboard, Bool) -> Void
    let onUnlock: (Pinboard) -> Void
    let onLockNow: (Pinboard) -> Void
    let onRename: (Pinboard) -> Void
    let onColorChange: (Pinboard, String) -> Void
    let onIconChange: (Pinboard, String?) -> Void
    let onDelete: (Pinboard) -> Void
    let onReorder: (Pinboard, Pinboard, Bool) -> Void
    let onReorderEnd: () -> Void
    let onMoveItem: (Pinboard, String) -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void
    let coordinateSpaceName: String

    static let allTabObjectID = NSManagedObjectID()

    @EnvironmentObject private var frameCoordinator: FrameCoordinator
    @FocusState var isFocused: Bool

    enum CommitState {
        case none
        case cancel
        case commit
        case suppress
    }

    @StateObject var frameManager = PinboardFrameManager()

    @State var dragState: PinboardTabDragState?
    @State var dragOpacity: Double = 0
    @State var dropTarget: PinboardTabDropTarget?
    @State var commitState: CommitState = .none
    @State var trailingTabWidth: CGFloat = 40
    @State var autoScrollTimer: Timer?
    @State var scrollViewBounds: CGRect = .zero
    @State var currentScrollProxy: ScrollViewProxy?
    @State var shouldPresentStylePickerFromMenu = false
    @State var isStyleOnlyEditMode = false
    @State var pinnedEditorObjectID: NSManagedObjectID?
    @State var pinnedEditorWidth: CGFloat?
    @Environment(\.colorScheme) var colorScheme

    let autoScrollEdgeInset: CGFloat = 40
    let autoScrollSpeed: CGFloat = 4

    var canReorder: Bool {
        editingID == nil
    }

    let scrollContentPadding: CGFloat = 10

    var measuredContentWidth: CGFloat {
        frameManager.contentWidth
    }

    func availableScrollWidth(parentWidth: CGFloat) -> CGFloat {
        max(0, parentWidth - trailingTabWidth - tabSpacing)
    }

    func overlayFrame(from proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .named(coordinateSpaceName))
    }

    func localFrame(from proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .named(localCoordinateSpaceName))
    }

    func scrollViewWidth(parentWidth: CGFloat) -> CGFloat {
        let availableWidth = availableScrollWidth(parentWidth: parentWidth)

        if measuredContentWidth > 0 {
            let contentWithPadding = measuredContentWidth + (scrollContentPadding * 2)
            return min(contentWithPadding, availableWidth)
        }

        return availableWidth
    }

    func shouldDisableScroll(parentWidth: CGFloat) -> Bool {
        guard measuredContentWidth > 0 else { return true }
        let availableWidth = availableScrollWidth(parentWidth: parentWidth)
        let contentWithPadding = measuredContentWidth + (scrollContentPadding * 2)
        return contentWithPadding <= availableWidth
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 6) {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        pinboardsContent(isMeasuring: false)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, scrollContentPadding)
                    }
                    .scrollDisabled(shouldDisableScroll(parentWidth: proxy.size.width))
                    .coordinateSpace(name: scrollSpaceName)
                    .frame(width: scrollViewWidth(parentWidth: proxy.size.width))
                    .background(
                        GeometryReader { scrollGeo in
                            let bounds = scrollGeo.frame(in: .named(localCoordinateSpaceName))
                            Color.clear
                                .preference(key: ScrollViewBoundsKey.self, value: bounds)
                                .onAppear {
                                    DispatchQueue.main.async {
                                        if !rectsApproximatelyEqual(scrollViewBounds, bounds) {
                                            scrollViewBounds = bounds
                                        }
                                        currentScrollProxy = scrollProxy
                                    }
                                }
                        }
                    )
                    .onPreferenceChange(ScrollViewBoundsKey.self) { newBounds in
                        DispatchQueue.main.async {
                            if !rectsApproximatelyEqual(scrollViewBounds, newBounds) {
                                scrollViewBounds = newBounds
                            }
                        }
                    }
                    .onChange(of: dragState) { newDragState, _ in
                        handleAutoScrollStateChange(newDragState, scrollProxy: scrollProxy)
                    }
                    .onChange(of: editingID) { _, newEditingID in
                        guard let newEditingID else { return }
                        guard let pinboard = pinboards.first(where: { $0.objectID == newEditingID }) else {
                            return
                        }
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                scrollProxy.scrollTo(pinboard.id, anchor: .center)
                            }
                        }
                    }
                }
                .mask {
                    let width = scrollViewWidth(parentWidth: proxy.size.width)
                    let fadeLocation = width > 0 ? scrollContentPadding / width : 0
                    
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: fadeLocation),
                            .init(color: .black, location: 1 - fadeLocation),
                            .init(color: .clear, location: 1),
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }

                ZStack(alignment: .leading) {
                    Button {
                        isStyleOnlyEditMode = false
                        pinnedEditorObjectID = nil
                        pinnedEditorWidth = nil
                        onCreate()
                    } label: {
                        if #available(macOS 26.0, *) {
                            Image(systemName: "plus")
                                .font(.system(size: headerButtonIconSize, weight: .semibold))
                                .frame(width: headerButtonSize, height: headerButtonSize)
                                .glassCircleButton()
                                .contentShape(Circle())
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: headerButtonIconSize, weight: .semibold))
                                .frame(width: headerButtonSize, height: headerButtonSize)
                                .background(
                                    Circle()
                                        .fill(
                                            Color.white.opacity(
                                                DesignTokens.Opacity.backgroundMedium))
                                )
                                .contentShape(Circle())
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .popover(isPresented: $isCreatePopoverPresented, arrowEdge: .top) {
                        createPopoverContent()
                    }
                    .accessibilityIdentifier("overlay.pinboard.add")
                    .accessibilityLabel("Add pinboard")
                    .accessibilityHint("Creates a new pinboard")
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: PinboardLayoutInfoKey.self,
                            value: PinboardLayoutInfo(editorOverlayFrame: overlayFrame(from: proxy))
                        )
                    }
                )
            }
            .fixedSize(horizontal: true, vertical: false)
            .coordinateSpace(name: localCoordinateSpaceName)
            .overlay(alignment: .topLeading) {
                placeholderView()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onPreferenceChange(PinboardLayoutInfoKey.self) { layout in
            DispatchQueue.main.async {
                frameManager.suppressUpdates = (dragState != nil || isGlobalDragActive)
                if !layout.tabFrames.isEmpty {
                    frameManager.updateTabFrames(layout.tabFrames)
                }
                if let offset = layout.scrollOffset {
                    frameCoordinator.updateCurrentPinboardScrollOffset(offset)
                }
                if let w = layout.editorOverlayFrame?.width, trailingTabWidth != w {
                    trailingTabWidth = w
                }
            }
        }
        .onChange(of: draftName) { newValue, _ in
            let clamped = String(newValue.prefix(maxPinboardNameLength))
            if clamped != newValue {
                draftName = clamped
            }
        }
        .onChange(of: pinboards.count) { _, _ in
            frameManager.clearCaches()
        }
        .onChange(of: editingID) { _, newValue in
            if let newValue {
                if pinnedEditorObjectID != newValue {
                    pinnedEditorObjectID = newValue
                    pinnedEditorWidth = frameManager.latestTabFrames[newValue]?.width
                }
            } else {
                shouldPresentStylePickerFromMenu = false
                isStyleOnlyEditMode = false
                pinnedEditorObjectID = nil
                pinnedEditorWidth = nil
            }
        }
        .onChange(of: isCreatePopoverPresented) { _, newValue in
            if newValue {
                isStyleOnlyEditMode = false
            }
        }
        .onAppear {
            frameManager.clearCaches()
        }
    }
}
