import Combine
import MartenCore
import MartenIOSApp
import SwiftUI
import UIKit

// MARK: - Helper Views

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

@MainActor
final class KeyboardExtensionViewModel: ObservableObject {
    @Published var selectedPinboardID: UUID?
    @Published private(set) var pinboards: [SharedPinboardSummary] = []
    @Published private(set) var items: [SharedClipItemSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let queryService: SharedClipQueryService
    init(queryService: SharedClipQueryService) {
        self.queryService = queryService
    }

    func load() {
        Task {
            await refreshPinboards()
            await refreshItems()
        }
    }

    func refresh() {
        Task {
            await refreshItems()
        }
    }

    private func refreshPinboards() async {
        do {
            pinboards = try await queryService.pinboards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshItems() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await queryService.recentItems(
                pinboardID: selectedPinboardID,
                limit: 50
            )
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
    let onDeleteBackward: () -> Void
    let onRecordHeartbeat: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

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
                    Image(systemName: "tray")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No items")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 148), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(viewModel.items) { item in
                            Button {
                                handleItemTap(item)
                            } label: {
                                KeyboardItemCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
            }
            
            keyboardActions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            onRecordHeartbeat()
            viewModel.load()
        }
        .onChange(of: viewModel.selectedPinboardID) {
            viewModel.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            pinboardMenu

            Spacer(minLength: 0)

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    
    private var keyboardActions: some View {
        HStack(spacing: 12) {
            Button {
                onInsertText(" ")
                onRecordHeartbeat()
            } label: {
                Text("Space")
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .frame(height: 42)
            
            Button {
                onDeleteBackward()
                onRecordHeartbeat()
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Button {
                onInsertText("\n")
                onRecordHeartbeat()
            } label: {
                Image(systemName: "return")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .padding(.top, 4)
    }

    private var pinboardMenu: some View {
        Menu {
            Button {
                viewModel.selectedPinboardID = nil
            } label: {
                if viewModel.selectedPinboardID == nil {
                    Label("All pinboards", systemImage: "checkmark")
                } else {
                    Text("All pinboards")
                }
            }
            
            ForEach(viewModel.pinboards.filter { !$0.isSystemMarten }) { pinboard in
                Button {
                    viewModel.selectedPinboardID = pinboard.id
                } label: {
                    Label {
                        Text(pinboard.name)
                    } icon: {
                        if let iconName = pinboard.iconName, !iconName.isEmpty {
                            Image(systemName: iconName)
                        } else {
                            Image(systemName: "folder")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let selected = selectedPinboard {
                    KeyboardPinboardIndicator(
                        colorHex: selected.colorHex,
                        sign: selected.iconName,
                        size: 18
                    )
                }

                Text(selectedPinboardTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }

    private var selectedPinboard: SharedPinboardSummary? {
        guard let id = viewModel.selectedPinboardID else { return nil }
        return viewModel.pinboards.first(where: { $0.id == id })
    }

    private var selectedPinboardTitle: String {
        selectedPinboard?.name ?? "All pinboards"
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
}

private struct KeyboardItemCard: View {
    let item: SharedClipItemSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: itemTypeIcon(item.itemType))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            Text(item.insertionText.isEmpty ? "Untitled" : item.insertionText)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func itemTypeIcon(_ type: ItemType) -> String {
        switch type {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .richText: return "doc.richtext"
        case .code: return "chevron.left.slash.chevron.right"
        case .color: return "paintpalette"
        case .mixed: return "square.stack.3d.up"
        }
    }
}
