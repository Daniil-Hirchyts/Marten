import MartenCore
import MartenMacServices
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

private struct AddButtonWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

enum PinboardTabBarIDs {
    static let allTabObjectID = NSManagedObjectID()
}

struct PinboardTabBar<CreatePopoverContent: View>: View {
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
    @ViewBuilder let createPopoverContent: () -> CreatePopoverContent
    
    @Binding var draftName: String
    @Binding var draftColor: String
    @Binding var draftIcon: String?
    var isGlobalDragActive: Bool = false
    var itemDragPinboardDropTargetID: NSManagedObjectID? = nil
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
    var onSharePinboard: ((Pinboard) -> Void)? = nil
    var onManageSharing: ((Pinboard) -> Void)? = nil
    var onStopSharing: ((Pinboard) -> Void)? = nil
    var onLeaveSharedPinboard: ((Pinboard) -> Void)? = nil
    @Binding var shareSheetPinboard: Pinboard?
    var sharingRepository: (any PinboardSharingRepositoryProtocol)?
    let coordinateSpaceName: String

    static var allTabObjectID: NSManagedObjectID { PinboardTabBarIDs.allTabObjectID }

    @EnvironmentObject var frameCoordinator: FrameCoordinator
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
    @State var addButtonWidth: CGFloat = 30
    @State var autoScrollTimer: Timer?
    @State var scrollViewBounds: CGRect = .zero
    @State var currentScrollProxy: ScrollViewProxy?
    @State var shouldPresentStylePickerFromMenu = false
    @State var isStyleOnlyEditMode = false
    @State var pinnedEditorObjectID: NSManagedObjectID?
    @State var pinnedEditorWidth: CGFloat?
    @State private var isPlusHovered = false
    @Environment(\.colorScheme) var colorScheme

    let autoScrollEdgeInset: CGFloat = 40
    let autoScrollSpeed: CGFloat = 4

    var canReorder: Bool {
        editingID == nil
    }

    let tabsToAddSpacing: CGFloat = 6
    let scrollContentPadding: CGFloat = 10
    let fallbackTabsContentWidth: CGFloat = 120

    var measuredContentWidth: CGFloat {
        frameManager.contentWidth
    }

    func overlayFrame(from proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .named(coordinateSpaceName))
    }

    func localFrame(from proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .named(localCoordinateSpaceName))
    }

    func layoutMetrics(parentWidth: CGFloat) -> PinboardTabBarLayoutMetrics {
        PinboardTabBarLayoutMetrics(
            parentWidth: parentWidth,
            addButtonWidth: addButtonWidth,
            interControlSpacing: tabsToAddSpacing,
            measuredContentWidth: measuredContentWidth,
            lastNonZeroContentWidth: frameManager.lastNonZeroContentWidth,
            scrollContentPadding: scrollContentPadding,
            fallbackContentWidth: fallbackTabsContentWidth
        )
    }

    func scrollToSelectedPinboard(using scrollProxy: ScrollViewProxy, selectedID: UUID?) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if let selectedID {
                scrollProxy.scrollTo(selectedID, anchor: .center)
            } else {
                scrollProxy.scrollTo("all", anchor: .center)
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(parentWidth: proxy.size.width)

            HStack(spacing: tabsToAddSpacing) {
                ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        pinboardsContent(isMeasuring: false)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, scrollContentPadding)
                    }
                    .scrollClipDisabled()
                    .scrollDisabled(metrics.isScrollDisabled)
                    .coordinateSpace(name: scrollSpaceName)
                    .frame(width: metrics.viewportWidth)
                    .background(
                        GeometryReader { scrollGeo in
                            let bounds = scrollGeo.frame(in: .named(localCoordinateSpaceName))
                            Color.clear
                                .preference(key: ScrollViewBoundsKey.self, value: bounds)
                                .onAppear {
                                    if !rectsApproximatelyEqual(scrollViewBounds, bounds) {
                                        scrollViewBounds = bounds
                                    }
                                    currentScrollProxy = scrollProxy
                                }
                        }
                    )
                    .onPreferenceChange(ScrollViewBoundsKey.self) { newBounds in
                        if !rectsApproximatelyEqual(scrollViewBounds, newBounds) {
                            scrollViewBounds = newBounds
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
                        withAnimation(.easeInOut(duration: 0.18)) {
                            scrollProxy.scrollTo(pinboard.id, anchor: .center)
                        }
                    }
                    .onChange(of: selectedID) { _, newSelectedID in
                        scrollToSelectedPinboard(using: scrollProxy, selectedID: newSelectedID)
                    }
                    .onChange(of: pinboards.map(\.id)) { _, _ in
                        scrollToSelectedPinboard(using: scrollProxy, selectedID: selectedID)
                    }
                }
                .mask {
                    let width = metrics.viewportWidth
                    let fadeLocation = width > 0 ? min(0.5, scrollContentPadding / width) : 0
                    
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
                        OverlayHeaderButton(
                            systemImage: "plus",
                            size: headerButtonSize,
                            iconSize: headerButtonIconSize,
                            isHovered: isPlusHovered
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(OverlayAnimation.quickTransition) {
                            isPlusHovered = hovering
                        }
                    }
                    .popover(isPresented: $isCreatePopoverPresented, arrowEdge: .top) {
                        createPopoverContent()
                    }
                    .accessibilityIdentifier("overlay.pinboard.add")
                    .accessibilityLabel("Add pinboard")
                    .accessibilityHint("Creates a new pinboard")
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(
                                key: PinboardLayoutInfoKey.self,
                                value: PinboardLayoutInfo(editorOverlayFrame: overlayFrame(from: proxy))
                            )
                            .preference(
                                key: AddButtonWidthKey.self,
                                value: proxy.size.width
                            )
                    }
                )
            }
            .frame(width: metrics.groupWidth, alignment: .leading)
            .coordinateSpace(name: localCoordinateSpaceName)
            .overlay(alignment: .topLeading) {
                placeholderView()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onPreferenceChange(PinboardContentWidthKey.self) { width in
            if let width {
                frameManager.setContentWidth(width)
            }
        }
        .onPreferenceChange(PinboardLayoutInfoKey.self) { layout in
            frameManager.suppressUpdates = (dragState != nil || isGlobalDragActive)
            if !layout.tabFrames.isEmpty {
                frameManager.updateTabFrames(layout.tabFrames)
            }
            if let offset = layout.scrollOffset {
                frameCoordinator.updateCurrentPinboardScrollOffset(offset)
            }
        }
        .onPreferenceChange(AddButtonWidthKey.self) { width in
            guard width > 0 else { return }
            if abs(addButtonWidth - width) > 0.5 {
                addButtonWidth = width
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
            if addButtonWidth <= 0 {
                addButtonWidth = headerButtonSize
            }
        }
    }
}
