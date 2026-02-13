import SwiftUI

// MARK: - Animation Constants

enum MartenAnimation {
    static let springResponse: Double = 0.35
    static let springDamping: Double = 0.82
    static let quickSpringResponse: Double = 0.25
    static let quickSpringDamping: Double = 0.86

    static var smooth: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    static var quick: Animation {
        .spring(response: quickSpringResponse, dampingFraction: quickSpringDamping)
    }

    static var slideUp: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
    }

    static var fadeScale: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.95))
    }
}

// MARK: - iOS Button Size Standards

/// Standard button sizes following iOS Human Interface Guidelines
enum MartenButtonSize {
    /// Minimum tap target size recommended by Apple (44x44 points)
    static let minimumTapTarget: CGFloat = 44

    /// Standard icon button size (44x44 points)
    static let iconButton: CGFloat = 44

    /// Large icon button size (56x56 points)
    static let largeIconButton: CGFloat = 56

    /// Standard button height for text buttons
    static let standardHeight: CGFloat = 50

    /// Prominent button height
    static let prominentHeight: CGFloat = 52

    /// Compact button height (minimum recommended)
    static let compactHeight: CGFloat = 44
}

// MARK: - Glass Surface

struct MartenGlassSurface<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let isInteractive: Bool
    @ViewBuilder let content: Content

    init(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 12,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                content
                    .padding(padding)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.clear)
                    )
                    .glassEffect(
                        isInteractive ? .regular.interactive() : .regular,
                        in: .rect(cornerRadius: cornerRadius)
                    )
            } else {
                fallbackSurface
            }
        #else
            fallbackSurface
        #endif
    }

    private var fallbackSurface: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
    }
}

// MARK: - Glass Card (optimized for item cards)

struct MartenGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let isSelected: Bool
    @ViewBuilder let content: Content

    init(
        cornerRadius: CGFloat = 18,
        isSelected: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.isSelected = isSelected
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                content
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.clear)
                    )
                    .glassEffect(
                        .regular.interactive(),  // No tint on selection
                        in: .rect(cornerRadius: cornerRadius)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                isSelected ? Color.accentColor : .clear,
                                lineWidth: isSelected ? 3 : 0
                            )
                    )
            } else {
                fallbackCard
            }
        #else
            fallbackCard
        #endif
    }

    private var fallbackCard: some View {
        content
            .padding(14)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isSelected ? Color.accentColor : .white.opacity(0.14),
                        lineWidth: isSelected ? 3 : 1
                    )
            )
    }
}

// MARK: - Glass Container

struct MartenGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: spacing) {
                    content
                }
            } else {
                content
            }
        #else
            content
        #endif
    }
}

struct MartenGlassSection<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        MartenGlassSurface(cornerRadius: 16, padding: 0) {
            VStack(spacing: spacing) {
                content
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Glass Toolbar

struct MartenGlassToolbar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                content
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            } else {
                content
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        #else
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        #endif
    }
}

// MARK: - Glass Search Bar

struct MartenGlassSearchBar: View {
    @Binding var text: String
    var prompt: String = "Search"
    var onClear: (() -> Void)?
    var onVoice: (() -> Void)?
    var isVoiceRecording: Bool = false
    var onFilters: (() -> Void)?
    var hasActiveFilters: Bool = false

    var focusRequest: Binding<Bool>?

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            #if os(iOS)
                TextField(prompt, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($isTextFieldFocused)
            #else
                TextField(prompt, text: $text)
                    .focused($isTextFieldFocused)
            #endif

            // Clear button - only shown when there's text
            if !text.isEmpty {
                Button {
                    text = ""
                    onClear?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 32, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            if let onVoice {
                Button {
                    onVoice()
                } label: {
                    Image(
                        systemName: isVoiceRecording
                            ? "waveform.circle.fill" : "mic.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isVoiceRecording ? Color.accentColor : .secondary)
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isVoiceRecording ? "Stop voice search" : "Start voice search"
                )
            }
        }
        .frame(height: MartenButtonSize.iconButton)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 100)
                .fill(Color.clear)
                .contentShape(RoundedRectangle(cornerRadius: 100))
        )
        .glassSearchBackground()
        .onChange(of: focusRequest?.wrappedValue ?? false) { _, newValue in
            guard newValue else { return }
            isTextFieldFocused = true
            DispatchQueue.main.async {
                focusRequest?.wrappedValue = false
            }
        }
    }
}

// MARK: - Buttons

struct MartenGlassProminentButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                Button(action: action) {
                    label
                        .frame(minHeight: MartenButtonSize.prominentHeight)
                }
                .buttonStyle(.glassProminent)
            } else {
                Button(action: action) {
                    label
                        .frame(minHeight: MartenButtonSize.prominentHeight)
                }
                .buttonStyle(.borderedProminent)
            }
        #else
            Button(action: action) {
                label
                    .frame(minHeight: MartenButtonSize.prominentHeight)
            }
            .buttonStyle(.borderedProminent)
        #endif
    }
}

struct MartenGlassButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                Button(action: action) {
                    label
                        .frame(minHeight: MartenButtonSize.standardHeight)
                }
                .buttonStyle(.glass)
            } else {
                Button(action: action) {
                    label
                        .frame(minHeight: MartenButtonSize.standardHeight)
                }
                .buttonStyle(.bordered)
            }
        #else
            Button(action: action) {
                label
                    .frame(minHeight: MartenButtonSize.standardHeight)
            }
            .buttonStyle(.bordered)
        #endif
    }
}

/// Icon-only button with proper iOS tap target size
struct MartenIconButton: View {
    let systemImage: String
    let action: () -> Void
    let size: CGFloat
    let tint: Color?

    init(
        systemImage: String,
        size: CGFloat = MartenButtonSize.iconButton,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.size = max(size, MartenButtonSize.minimumTapTarget)  // Enforce minimum
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .foregroundStyle(tint ?? .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.12), .clear],
                    startPoint: .init(x: phase - 0.5, y: 0.5),
                    endPoint: .init(x: phase + 0.5, y: 0.5)
                )
                .blendMode(.overlay)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: .capsule)
    }
}

// MARK: - View Extensions

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    @ViewBuilder
    func glassSearchBackground() -> some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                self
                    .background(Capsule().fill(Color.clear))
                    .glassEffect(.regular.interactive(), in: .capsule)
            } else {
                self.background(.regularMaterial, in: .capsule)
            }
        #else
            self.background(.regularMaterial, in: .capsule)
        #endif
    }

    @ViewBuilder
    func glassChipBackground(isHighlighted: Bool) -> some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                self
                    .background(Capsule().fill(Color.clear))
                    .glassEffect(
                        isHighlighted
                            ? .regular.tint(.accentColor).interactive()
                            : .regular.interactive(),
                        in: .capsule
                    )
            } else {
                self.background(
                    isHighlighted
                        ? Color.accentColor.opacity(0.18)
                        : Color.secondary.opacity(0.12),
                    in: .capsule
                )
            }
        #else
            self.background(
                isHighlighted
                    ? Color.accentColor.opacity(0.18)
                    : Color.secondary.opacity(0.12),
                in: .capsule
            )
        #endif
    }

    @ViewBuilder
    func glassCircleBackground(isHighlighted: Bool) -> some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                self
                    .background(Circle().fill(Color.clear))
                    .glassEffect(
                        isHighlighted
                            ? .regular.tint(.accentColor).interactive()
                            : .regular.interactive(),
                        in: .circle
                    )
            } else {
                self.background(
                    Circle()
                        .fill(
                            isHighlighted
                                ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
                )
            }
        #else
            self.background(
                Circle()
                    .fill(
                        isHighlighted
                            ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
            )
        #endif
    }
}
