import SwiftUI

extension ItemEditorContentView {
    func applyFormatting(_ type: TextFormattingType) {
        NotificationCenter.default.post(
            name: .applyTextFormatting,
            object: nil,
            userInfo: ["type": type]
        )
    }
}
