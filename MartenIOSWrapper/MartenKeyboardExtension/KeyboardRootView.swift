import Combine
import MartenCore
import MartenIOSApp
import SwiftUI
import UIKit

// MARK: - Animation Constants

private enum KeyboardAnimation {
    static let quickSpringResponse: Double = 0.25
    static let quickSpringDamping: Double = 0.86

    static var quick: Animation {
        .spring(response: quickSpringResponse, dampingFraction: quickSpringDamping)
    }
}

// MARK: - Helper Views

private struct KeyboardSearchBar: View {
    @Binding var text: String
    var prompt: String = "Search"
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(.system(size: 16))
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: .capsule)
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

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
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        return luminance < 0.56
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

private extension View {
    @ViewBuilder
    func keyboardChipBackground(isHighlighted: Bool) -> some View {
        self
            .background(
                isHighlighted
                    ? Color.accentColor.opacity(0.2)
                    : Color.secondary.opacity(0.1),
                in: .capsule
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isHighlighted
                            ? Color.accentColor.opacity(0.3)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
    }
}

@MainActor
final class KeyboardExtensionViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedPinboardID: UUID?
    @Published private(set) var pinboards: [SharedPinboardSummary] = []
    @Published private(set) var items: [SharedClipItemSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let queryService: SharedClipQueryService
    private var queryTask: Task<Void, Never>?

    init(queryService: SharedClipQueryService) {
        self.queryService = queryService
    }

    func load() {
        Task {
            await refreshPinboards()
            await searchNow()
        }
    }

    func search() {
        queryTask?.cancel()
        queryTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await searchNow()
        }
    }

    private func refreshPinboards() async {
        do {
            pinboards = try await queryService.pinboards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func searchNow() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items = try await queryService.recentItems(
                    pinboardID: selectedPinboardID,
                    limit: 30
                )
            } else {
                items = try await queryService.searchItems(
                    query: query,
                    pinboardID: selectedPinboardID,
                    limit: 50
                )
            }
            errorMessage = nil
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
    }
}

struct KeyboardRootView: View {
    @StateObject var viewModel: KeyboardExtensionViewModel
    let onInsertText: (String) -> Void
    let onRecordHeartbeat: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Modern glass search bar
            VStack(spacing: 10) {
                KeyboardSearchBar(
                    text: $viewModel.query,
                    prompt: "Search Marten"
                )
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .onChange(of: viewModel.query) {
                    viewModel.search()
                }

                // Filter chips with liquid glass design
                if !viewModel.pinboards.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip(
                                title: "All",
                                icon: nil,
                                isSelected: viewModel.selectedPinboardID == nil
                            ) {
                                withAnimation(KeyboardAnimation.quick) {
                                    viewModel.selectedPinboardID = nil
                                    viewModel.search()
                                }
                            }
                            
                            ForEach(viewModel.pinboards.filter { !$0.isSystemMarten }) { pinboard in
                                filterChip(
                                    title: pinboard.name,
                                    icon: pinboard.iconName,
                                    colorHex: pinboard.colorHex,
                                    isSelected: viewModel.selectedPinboardID == pinboard.id
                                ) {
                                    withAnimation(KeyboardAnimation.quick) {
                                        viewModel.selectedPinboardID = pinboard.id
                                        viewModel.search()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(height: 40)
                }
            }
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)

            Divider()

            // Content area
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isLoading {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No matching items")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.items) { item in
                            itemRow(item)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    handleItemTap(item)
                                }
                            
                            if item.id != viewModel.items.last?.id {
                                Divider()
                                    .padding(.leading, 14)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            onRecordHeartbeat()
            viewModel.load()
        }
    }

    private func filterChip(
        title: String,
        icon: String?,
        colorHex: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let colorHex = colorHex {
                    KeyboardPinboardIndicator(
                        colorHex: colorHex,
                        sign: icon,
                        size: 18
                    )
                }
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Capsule())
            .keyboardChipBackground(isHighlighted: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func itemRow(_ item: SharedClipItemSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.insertionText.isEmpty ? "Untitled Item" : item.insertionText)
                    .font(.system(size: 15))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 5) {
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    
                    Text(itemTypeLabel(item.itemType))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer(minLength: 8)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(uiColor: .systemBackground))
    }

    private func handleItemTap(_ item: SharedClipItemSummary) {
        let text = item.insertionText
        guard !text.isEmpty else { return }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        onInsertText(text)
        onRecordHeartbeat()
    }

    private func itemTypeLabel(_ type: ItemType) -> String {
        switch type {
        case .text: return "Text"
        case .url: return "Link"
        case .image: return "Image"
        case .file: return "File"
        case .richText: return "Rich Text"
        case .code: return "Code"
        case .color: return "Color"
        case .mixed: return "Mixed"
        }
    }
}
