import SwiftUI

struct MartenIOSShellView: View {
    @Bindable var container: MartenIOSAppContainer

    var body: some View {
        NavigationStack {
            MartenIOSDashboardView(container: container)
        }
    }
}
