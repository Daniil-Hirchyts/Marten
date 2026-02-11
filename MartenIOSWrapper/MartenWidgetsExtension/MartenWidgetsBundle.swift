import SwiftUI
import WidgetKit

@main
struct MartenWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RecentItemsWidget()
        SelectedPinboardWidget()
        RecentItemsLockWidget()
    }
}
