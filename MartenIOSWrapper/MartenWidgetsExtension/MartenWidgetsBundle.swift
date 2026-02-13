import SwiftUI
import WidgetKit

@main
struct MartenWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MartenQuickAccessWidget()
        RecentItemsLockWidget()
    }
}
