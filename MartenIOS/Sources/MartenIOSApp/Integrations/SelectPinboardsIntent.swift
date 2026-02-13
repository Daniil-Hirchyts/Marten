#if canImport(AppIntents) && canImport(WidgetKit)
    import AppIntents
    import WidgetKit

    public struct SelectPinboardsIntent: WidgetConfigurationIntent {
        public static var title: LocalizedStringResource = "Select Pinboards"
        public static var description = IntentDescription("Choose pinboards to show in the widget.")

        public static var parameterSummary: some ParameterSummary {
            When(\.$pinboards, .hasNoValue) {
                Summary("None") {
                    \.$pinboards
                }
            } otherwise: {
                Summary {
                    \.$pinboards
                }
            }
        }

        @Parameter(
            title: "Pinboards",
            default: [PinboardAppEntity.noneOption],
            size: [
                .systemSmall: 1,
                .systemMedium: 2,
                .systemLarge: 4,
            ])
        public var pinboards: [PinboardAppEntity]?

        public init() {
            self.pinboards = [PinboardAppEntity.noneOption]
        }

        public init(pinboards: [PinboardAppEntity]) {
            self.pinboards = pinboards
        }
    }
#endif
