import Foundation

enum PinboardSignTab: String, CaseIterable, Identifiable {
    case emoji = "Emoji"
    case icon = "Icon"
    var id: String { rawValue }
}

enum PinboardSignCatalogIOS {
    static let emojiOptions: [(token: String, label: String)] = [
        ("😀", "grinning"), ("😄", "smile"), ("😅", "sweat"), ("😂", "joy"),
        ("🙂", "slightly smiling"), ("😉", "wink"), ("😊", "blush"), ("😎", "cool"),
        ("🤩", "star eyes"), ("🥳", "celebrate"), ("🤔", "thinking"), ("🤯", "mind blown"),
        ("🤗", "hug"), ("🤫", "shush"), ("🤝", "handshake"), ("🙌", "raised hands"),
        ("👏", "clap"), ("🫶", "heart hands"), ("❤️", "heart"), ("🧡", "orange heart"),
        ("💚", "green heart"), ("💙", "blue heart"), ("💜", "purple heart"), ("🩷", "pink heart"),
        ("⭐", "star"), ("✨", "sparkles"), ("⚡", "lightning"), ("🔥", "fire"),
        ("🌈", "rainbow"), ("🌙", "moon"), ("☀️", "sun"), ("📌", "pin"),
        ("📎", "paperclip"), ("📍", "location"), ("🧠", "brain"), ("🧩", "puzzle"),
        ("🎯", "target"), ("🎉", "confetti"), ("🎵", "music"), ("📷", "camera"),
        ("💡", "idea"), ("🛠️", "tools"), ("🚀", "rocket"), ("✅", "check"), ("❗", "important"),
    ]

    static let iconOptions: [(token: String, label: String)] = [
        ("star.fill", "star"), ("sparkles", "sparkles"), ("heart.fill", "heart"),
        ("bookmark.fill", "bookmark"), ("flag.fill", "flag"), ("pin.fill", "pin"),
        ("bolt.fill", "bolt"), ("flame.fill", "flame"), ("lightbulb.fill", "idea"),
        ("checkmark.circle.fill", "check"), ("exclamationmark.circle.fill", "important"),
        ("questionmark.circle.fill", "question"), ("clock.fill", "clock"),
        ("calendar", "calendar"), ("bell.fill", "bell"), ("envelope.fill", "mail"),
        ("paperplane.fill", "paper plane"), ("doc.fill", "document"),
        ("folder.fill", "folder"), ("tray.full.fill", "tray"),
        ("archivebox.fill", "archive"), ("tag.fill", "tag"), ("link", "link"),
        ("globe", "globe"), ("location.fill", "location"), ("map.fill", "map"),
        ("camera.fill", "camera"), ("photo.fill", "photo"), ("video.fill", "video"),
        ("music.note", "music"), ("headphones", "headphones"), ("book.fill", "book"),
        ("graduationcap.fill", "graduation"), ("briefcase.fill", "briefcase"),
        ("wrench.and.screwdriver.fill", "tools"), ("hammer.fill", "hammer"),
        ("paintbrush.fill", "paint"), ("gamecontroller.fill", "game"),
        ("cart.fill", "cart"), ("gift.fill", "gift"), ("leaf.fill", "leaf"),
        ("pawprint.fill", "paw"), ("cup.and.saucer.fill", "coffee"),
        ("fork.knife", "food"), ("house.fill", "home"), ("car.fill", "car"),
        ("airplane", "airplane"), ("bicycle", "bicycle"),
        ("figure.walk", "walk"), ("figure.run", "run"),
    ]

    static func filtered(tab: PinboardSignTab, query: String) -> [(
        token: String, label: String
    )] {
        let options = tab == .emoji ? emojiOptions : iconOptions
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return options }
        return options.filter {
            $0.label.localizedCaseInsensitiveContains(trimmed)
                || $0.token.localizedCaseInsensitiveContains(trimmed)
        }
    }

    static func isSystemSymbol(_ token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        return iconOptions.contains { $0.token == token }
    }
}
