import SwiftUI

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
    var onFilters: (() -> Void)?
    var hasActiveFilters: Bool = false

    var focusRequest: Binding<Bool>?

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            #if os(iOS)
                MartenUISearchTextField(
                    text: $text,
                    placeholder: prompt,
                    onFocus: {
                        // Handle focus if needed
                    }
                )
                .frame(height: 36)
            #else
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField(prompt, text: $text)
                    .focused($isTextFieldFocused)
            #endif

            // Clear button - only shown when there's text (Handled by UISearchTextField on iOS)
            #if !os(iOS)
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
            #endif
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
            #if !os(iOS)
            isTextFieldFocused = true
            #endif
            // For iOS, focus handling would need to be passed down to UIViewRepresentable
            DispatchQueue.main.async {
                focusRequest?.wrappedValue = false
            }
        }
    }
}

#if os(iOS)
struct MartenUISearchTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onFocus: () -> Void
    var focusRequest: Binding<Bool>?
    var showsLeadingIcon: Bool = true

    func makeUIView(context: Context) -> UISearchTextField {
        let searchTextField = UISearchTextField()
        searchTextField.placeholder = placeholder
        searchTextField.delegate = context.coordinator
        searchTextField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )

        searchTextField.borderStyle = .none
        searchTextField.backgroundColor = .clear

        if !showsLeadingIcon {
            searchTextField.leftViewMode = .never
        }

        return searchTextField
    }

    func updateUIView(_ uiView: UISearchTextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if focusRequest?.wrappedValue == true {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
                focusRequest?.wrappedValue = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: MartenUISearchTextField

        init(_ parent: MartenUISearchTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            if let text = textField.text {
                parent.text = text
            }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onFocus()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
#endif
