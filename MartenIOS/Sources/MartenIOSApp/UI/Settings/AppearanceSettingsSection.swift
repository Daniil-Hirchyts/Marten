import SwiftUI

struct AppearanceSettingsSection: View {
    @Bindable var container: MartenIOSAppContainer

    var body: some View {
        Section {
            Picker(
                "Theme",
                selection: Binding(
                    get: { container.appearance },
                    set: { container.setAppearance($0) }
                )
            ) {
                ForEach(MartenIOSAppearance.allCases, id: \.rawValue) { appearance in
                    Label(appearance.displayName, systemImage: appearance.iconName)
                        .tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("App theme")
        } header: {
            Label("Appearance", systemImage: "paintbrush")
        }
    }
}

private extension MartenIOSAppearance {
    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}
