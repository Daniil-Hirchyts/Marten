import SwiftUI

struct AppearanceSettingsSection: View {
    @Bindable var container: MartenIOSAppContainer

    var body: some View {
        Picker(
            "Theme",
            selection: Binding(
                get: { container.appearance },
                set: { container.setAppearance($0) }
            )
        ) {
            ForEach(MartenIOSAppearance.allCases, id: \.rawValue) { appearance in
                Text(appearance.displayName)
                    .tag(appearance)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("App theme")
    }
}
