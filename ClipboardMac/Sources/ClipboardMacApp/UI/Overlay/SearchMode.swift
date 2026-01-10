import SwiftUI

struct SearchModeView: View {
    let query: String
    let resultCount: Int
    let onClear: () -> Void

    var body: some View {
        SearchModeHeader(query: query, resultCount: resultCount, onClear: onClear)
    }
}
