import SwiftUI

struct SettingsRow<Content: View>: View {
    let icon: String?
    let iconColor: Color?
    let title: String
    let titleColor: Color
    let subtitle: String?
    let value: String?
    let action: Content

    init(
        icon: String? = nil,
        iconColor: Color? = nil,
        title: String,
        titleColor: Color = .primary,
        subtitle: String? = nil,
        value: String? = nil,
        @ViewBuilder action: () -> Content
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.titleColor = titleColor
        self.subtitle = subtitle
        self.value = value
        self.action = action()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon, let iconColor {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(iconColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(titleColor)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
            }

            action
        }
    }
}

extension SettingsRow where Content == EmptyView {
    init(
        icon: String? = nil,
        iconColor: Color? = nil,
        title: String,
        titleColor: Color = .primary,
        subtitle: String? = nil,
        value: String? = nil
    ) {
        self.init(
            icon: icon,
            iconColor: iconColor,
            title: title,
            titleColor: titleColor,
            subtitle: subtitle,
            value: value,
            action: { EmptyView() }
        )
    }
}
