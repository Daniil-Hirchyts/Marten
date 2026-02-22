import SwiftUI

struct IntegrationDetailView<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let buttonTitle: String
    let action: () -> Void
    let instructions: Content

    init(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        buttonTitle: String,
        action: @escaping () -> Void,
        @ViewBuilder instructions: () -> Content
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.description = description
        self.buttonTitle = buttonTitle
        self.action = action
        self.instructions = instructions()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                        .frame(width: 80, height: 80)
                        .background(iconColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text(title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 40)

                Button(action: action) {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
                    Text("How to Enable")
                        .font(.headline)
                        .padding(.horizontal)

                    instructions
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct InstructionStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.body)
                .padding(.top, 2)
        }
    }
}
