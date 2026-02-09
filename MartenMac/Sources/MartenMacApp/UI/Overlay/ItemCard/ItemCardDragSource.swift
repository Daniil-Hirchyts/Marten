import SwiftUI

extension ItemCard {
    var accessibilityHintText: String {
        var parts = ["Press to select"]
        if isDragEnabled {
            parts.append("Drag to move or reorder")
        }
        return parts.joined(separator: ". ")
    }
}

