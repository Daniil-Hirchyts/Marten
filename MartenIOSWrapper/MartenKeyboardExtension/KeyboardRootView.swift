import Combine
import MartenIOSApp
import SwiftUI

@MainActor
final class KeyboardExtensionViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedPinboardID: UUID?
    @Published private(set) var pinboards: [SharedPinboardSummary] = []
    @Published private(set) var items: [SharedClipItemSummary] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let queryService: SharedClipQueryService
    private var queryTask: Task<Void, Never>?

    init(queryService: SharedClipQueryService) {
        self.queryService = queryService
    }

    func load() {
        Task {
            await refreshPinboards()
            await searchNow()
        }
    }

    func search() {
        queryTask?.cancel()
        queryTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await searchNow()
        }
    }

    private func refreshPinboards() async {
        do {
            pinboards = try await queryService.pinboards()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func searchNow() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items = try await queryService.recentItems(
                    pinboardID: selectedPinboardID,
                    limit: 30
                )
            } else {
                items = try await queryService.searchItems(
                    query: query,
                    pinboardID: selectedPinboardID,
                    limit: 50
                )
            }
            errorMessage = nil
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
    }
}

struct KeyboardRootView: View {
    @StateObject var viewModel: KeyboardExtensionViewModel
    let onInsertText: (String) -> Void
    let onRecordHeartbeat: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search Marten", text: $viewModel.query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)
                .onChange(of: viewModel.query) { _ in
                    viewModel.search()
                }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(title: "All", selected: viewModel.selectedPinboardID == nil) {
                        viewModel.selectedPinboardID = nil
                        viewModel.search()
                    }
                    ForEach(viewModel.pinboards.filter { !$0.isSystemMarten }) { pinboard in
                        chip(title: pinboard.name, selected: viewModel.selectedPinboardID == pinboard.id) {
                            viewModel.selectedPinboardID = pinboard.id
                            viewModel.search()
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
            }

            if viewModel.isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewModel.items.isEmpty {
                Spacer()
                Text("No matching items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.items) { item in
                    Button {
                        let text = item.insertionText
                        guard !text.isEmpty else { return }
                        onInsertText(text)
                        onRecordHeartbeat()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.insertionText.isEmpty ? "Untitled Item" : item.insertionText)
                                .lineLimit(2)
                                .font(.subheadline)
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            onRecordHeartbeat()
            viewModel.load()
        }
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
    }
}
