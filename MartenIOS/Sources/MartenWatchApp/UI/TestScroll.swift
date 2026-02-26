import SwiftUI

struct TestScroll: View {
    var body: some View {
        ScrollView {
            Text("Test")
                .scrollTransition { view, phase in
                    view.offset(y: phase.value * -15)
                }
        }
    }
}
