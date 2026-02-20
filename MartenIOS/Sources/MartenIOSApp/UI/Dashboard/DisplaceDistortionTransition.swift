import SwiftUI

struct DisplaceDistortionModifier: ViewModifier {
    var offset: CGFloat
    var isInsertion: Bool
    
    func body(content: Content) -> some View {
        let progress = abs(offset) / UIScreen.main.bounds.width
        content
            // Elements move and displace with a 3D rotation
            .offset(x: offset)
            .scaleEffect(1 - (progress * 0.15))
            .blur(radius: progress * 12)
            .opacity(1 - progress)
            .rotation3DEffect(
                .degrees(Double(offset / 15)), 
                axis: (x: 0, y: 1.0, z: 0.2), 
                perspective: 0.6
            )
    }
}

public extension AnyTransition {
    static func displaceDistortion(direction: Int) -> AnyTransition {
        let insertionOffset = UIScreen.main.bounds.width * CGFloat(direction)
        let removalOffset = -UIScreen.main.bounds.width * CGFloat(direction)
        
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
