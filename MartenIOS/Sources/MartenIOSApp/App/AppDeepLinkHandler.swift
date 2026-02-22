import Foundation

enum AppDeepLinkAction: Equatable {
    case selectPinboard(UUID)
    case selectItem(UUID)
    case search
    case paste
    case create
    case openDashboard
}

struct AppDeepLinkHandler {
    func action(for url: URL) -> AppDeepLinkAction? {
        guard url.scheme?.lowercased() == "marten" else { return nil }

        var components: [String] = []
        if let host = url.host, !host.isEmpty {
            components.append(host)
        }
        components.append(contentsOf: url.pathComponents.filter { $0 != "/" })
        guard let route = components.first?.lowercased() else { return nil }

        switch route {
        case "pinboard":
            guard components.count >= 2, let pinboardID = UUID(uuidString: components[1]) else {
                return nil
            }
            return .selectPinboard(pinboardID)
        case "item":
            guard components.count >= 2, let itemID = UUID(uuidString: components[1]) else {
                return nil
            }
            return .selectItem(itemID)
        case "search":
            return .search
        case "paste":
            return .paste
        case "create":
            return .create
        case "open":
            return .openDashboard
        default:
            return nil
        }
    }
}
