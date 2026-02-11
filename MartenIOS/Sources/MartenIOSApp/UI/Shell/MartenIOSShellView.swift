import SwiftUI

struct MartenIOSShellView: View {
    @Bindable var container: MartenIOSAppContainer

    var body: some View {
        TabView(selection: Binding(
            get: { container.selectedTab },
            set: { container.selectedTab = $0 }
        )) {
            Tab("Dashboard", systemImage: "rectangle.grid.2x2.fill", value: .dashboard) {
                NavigationStack {
                    MartenIOSDashboardView(container: container)
                }
            }

            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    MartenIOSSettingsView(container: container)
                }
            }
        }
    }
}
