import MartenCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct ColorViewerSheet: View {
    let item: ClipItem
    var onEdit: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private var normalizedHex: String {
        ColorHex.normalizedHex(from: item.primaryText ?? "") ?? "#808080"
    }

    private var previewColor: Color {
        Color(hex: normalizedHex, fallback: .gray)
    }

    private var foregroundColor: Color {
        ColorHex.foregroundColor(for: normalizedHex)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(previewColor)
                    .overlay {
                        Text(normalizedHex)
                            .font(.system(.title2, design: .monospaced).weight(.bold))
                            .foregroundStyle(foregroundColor)
                    }
                    .frame(height: 240)
                    .padding(.horizontal, 20)

                Button {
                    copyColor()
                } label: {
                    Label("Copy \(normalizedHex)", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)
            }
            .navigationTitle("Color")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }

                if let onEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                }
            }
        }
    }

    private func copyColor() {
        #if canImport(UIKit)
        UIPasteboard.general.string = normalizedHex
        #endif
    }
}
