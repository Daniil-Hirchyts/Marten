import SwiftUI

#if os(iOS)
import UIKit

struct DashboardSearchTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var focusRequest: Binding<Bool>?

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.delegate = context.coordinator
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.clearButtonMode = .never
        textField.textAlignment = .left
        textField.returnKeyType = .search
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if focusRequest?.wrappedValue == true {
            DispatchQueue.main.async {
                guard !uiView.isFirstResponder else {
                    focusRequest?.wrappedValue = false
                    return
                }
                uiView.becomeFirstResponder()
                focusRequest?.wrappedValue = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DashboardSearchTextField

        init(_ parent: DashboardSearchTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
#endif

