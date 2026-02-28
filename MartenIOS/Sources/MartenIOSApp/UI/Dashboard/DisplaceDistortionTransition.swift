import SwiftUI

#if canImport(UIKit)
import UIKit
private let dashboardScreenWidth: CGFloat = UIScreen.main.bounds.width
#elseif canImport(AppKit)
import AppKit
private let dashboardScreenWidth: CGFloat = NSScreen.main?.frame.width ?? 800
#else
private let dashboardScreenWidth: CGFloat = 800
#endif

struct DisplaceDistortionModifier: ViewModifier {
    var offset: CGFloat
    var isInsertion: Bool
    
    func body(content: Content) -> some View {
        let progress = abs(offset) / dashboardScreenWidth
        content
            .offset(x: offset)
            .scaleEffect(1 - (progress * 0.10))
            .opacity(1 - progress)
    }
}

public extension AnyTransition {
    static func displaceDistortion(direction: Int) -> AnyTransition {
        let insertionOffset = dashboardScreenWidth * CGFloat(direction)
        let removalOffset = -dashboardScreenWidth * CGFloat(direction)
        
        return .asymmetric(
            insertion: .modifier(
                active: DisplaceDistortionModifier(offset: insertionOffset, isInsertion: true),
                identity: DisplaceDistortionModifier(offset: 0, isInsertion: true)
            ),
            removal: .modifier(
                active: DisplaceDistortionModifier(offset: removalOffset, isInsertion: false),
                identity: DisplaceDistortionModifier(offset: 0, isInsertion: false)
            )
        )
    }
}
