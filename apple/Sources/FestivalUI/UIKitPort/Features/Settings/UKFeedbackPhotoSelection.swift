#if os(iOS)
import UIKit

/// Reconciles continuous native photo selections with the form's admitted attachments.
@MainActor
final class UKFeedbackPhotoSelection {
    struct Item {
        let identifier: String
        let provider: NSItemProvider
    }

    private struct Import: Sendable {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let importItem: @MainActor (NSItemProvider) async -> UUID?
    private let remove: (UUID) -> Void
    private var links = FeedbackPickerLinks<String>()
    private var imports: [String: Import] = [:]
    private var closed = false
    private(set) var selected: [String] = []
    var onDeselect: (([String]) -> Void)?

    /// Connects native providers to the existing model's admission and removal operations.
    init(importItem: @escaping @MainActor (NSItemProvider) async -> UUID?, remove: @escaping (UUID) -> Void) {
        self.importItem = importItem
        self.remove = remove
    }

    deinit { imports.values.forEach { $0.task.cancel() } }

    /// Mirrors the complete current selection, preserving native selection order.
    func apply(_ items: [Item]) {
        guard !closed else { return }
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.identifier).inserted }
        let next = unique.map(\.identifier)
        let changes = FeedbackPickerLinks<String>.changes(from: selected, to: next)
        selected = next
        for key in changes.removed {
            imports.removeValue(forKey: key)?.task.cancel()
            if let id = links.unlink(key) { remove(id) }
        }
        for item in unique where changes.added.contains(item.identifier) {
            start(item)
        }
    }

    /// Removes a form attachment and unticks its corresponding library asset.
    func removeAttachment(id: UUID) {
        if let key = links.unlink(attachmentID: id) {
            selected.removeAll { $0 == key }
            imports.removeValue(forKey: key)?.task.cancel()
            onDeselect?([key])
        }
        remove(id)
    }

    /// Clears library ticks for attachments removed outside the photo picker.
    func prune(keeping ids: Set<UUID>) {
        let removed = links.prune(keeping: ids)
        guard !removed.isEmpty else { return }
        let stale = Set(removed)
        selected.removeAll { stale.contains($0) }
        onDeselect?(removed)
    }

    /// Cancels pending copies; a late admitted result is removed rather than resurrected.
    func close() {
        closed = true
        imports.values.forEach { $0.task.cancel() }
        imports.removeAll()
        selected = []
        links = FeedbackPickerLinks()
    }

    private func start(_ item: Item) {
        let token = UUID()
        let load = importItem
        let remove = remove
        let task = Task { @MainActor [weak self] in
            let id = await load(item.provider)
            guard let self else {
                if let id { remove(id) }
                return
            }
            guard !closed, !Task.isCancelled, imports[item.identifier]?.token == token,
                  selected.contains(item.identifier) else {
                if let id { remove(id) }
                return
            }
            imports[item.identifier] = nil
            if let id {
                links.link(item.identifier, to: id)
            } else {
                selected.removeAll { $0 == item.identifier }
                onDeselect?([item.identifier])
            }
        }
        imports[item.identifier] = Import(token: token, task: task)
    }
}
#endif
