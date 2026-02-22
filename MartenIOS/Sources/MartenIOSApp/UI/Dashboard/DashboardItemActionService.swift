import CoreData
import Foundation
import MartenCore

@MainActor
final class DashboardItemActionService {
    private let clipboardWriter: any DashboardClipboardWriting
    private let copyTextBuilder: DashboardCopyTextBuilder
    private let sharePayloadBuilder: DashboardSharePayloadBuilder

    init(dependencies: DashboardDependencies) {
        clipboardWriter = dependencies.clipboardWriter
        copyTextBuilder = DashboardCopyTextBuilder()
        sharePayloadBuilder = DashboardSharePayloadBuilder(
            fileManager: dependencies.fileManager,
            imageLoader: dependencies.imageLoader
        )
    }

    func copyItems(
        objectIDs: [NSManagedObjectID],
        resolver: any DashboardClipItemResolving,
        commandService: ClipItemCommandService,
        mode: DashboardCopyMode
    ) async -> String? {
        let items = resolver.resolveItems(from: objectIDs)
        let text = copyTextBuilder.buildText(for: items, mode: mode)
        guard !text.isEmpty else { return nil }

        clipboardWriter.setString(text)
        try? await commandService.markItemsUsed(objectIDs: objectIDs)
        return text
    }

    func shareItems(objectIDs: [NSManagedObjectID], resolver: any DashboardClipItemResolving) -> [Any] {
        let items = resolver.resolveItems(from: objectIDs)
        return sharePayloadBuilder.payloads(for: items)
    }

    func sharePayloads(for items: [ClipItem]) -> [Any] {
        sharePayloadBuilder.payloads(for: items)
    }
}

