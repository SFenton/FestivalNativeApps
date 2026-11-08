#if os(iOS)
import Testing
import UIKit
@testable import FestivalUI

extension UKFoundationTests {
    @MainActor
    struct UKFeedbackPhotoSelectionTests {
        private func item(_ identifier: String) -> UKFeedbackPhotoSelection.Item {
            .init(identifier: identifier, provider: NSItemProvider())
        }

        @Test
        func removingAnAttachmentUnticksItsNativeSelection() async throws {
            let id = UUID()
            var imported = false
            var removed: [UUID] = []
            var deselected: [[String]] = []
            let selection = UKFeedbackPhotoSelection(
                importItem: { _ in imported = true; return id }, remove: { removed.append($0) }
            )
            selection.onDeselect = { deselected.append($0) }
            selection.apply([item("photo")])
            try await UKHostedWindow.wait { imported }

            selection.removeAttachment(id: id)

            #expect(selection.selected.isEmpty)
            #expect(removed == [id])
            #expect(deselected == [["photo"]])
        }

        @Test
        func untickingDuringCopyRemovesALateAdmittedAttachment() async throws {
            var pending: CheckedContinuation<UUID?, Never>?
            var removed: [UUID] = []
            let selection = UKFeedbackPhotoSelection(
                importItem: { _ in await withCheckedContinuation { pending = $0 } },
                remove: { removed.append($0) }
            )
            selection.apply([item("photo")])
            try await UKHostedWindow.wait { pending != nil }
            selection.apply([])
            let late = UUID()
            pending?.resume(returning: late)
            try await UKHostedWindow.wait { removed == [late] }

            #expect(selection.selected.isEmpty)
        }

        @Test
        func staleCopyDoesNotClobberARetickedAsset() async throws {
            var pending: [CheckedContinuation<UUID?, Never>] = []
            var completed = 0
            var removed: [UUID] = []
            var deselected: [[String]] = []
            let selection = UKFeedbackPhotoSelection(
                importItem: { _ in
                    let result: UUID? = await withCheckedContinuation { pending.append($0) }
                    completed += 1
                    return result
                },
                remove: { removed.append($0) }
            )
            selection.onDeselect = { deselected.append($0) }
            selection.apply([item("photo")])
            try await UKHostedWindow.wait { pending.count == 1 }
            selection.apply([])
            selection.apply([item("photo")])
            try await UKHostedWindow.wait { pending.count == 2 }
            let old = UUID()
            pending[0].resume(returning: old)
            try await UKHostedWindow.wait { removed == [old] }
            let current = UUID()
            pending[1].resume(returning: current)
            try await UKHostedWindow.wait { completed == 2 }

            selection.removeAttachment(id: current)

            #expect(selection.selected.isEmpty)
            #expect(removed == [old, current])
            #expect(deselected == [["photo"]])
        }

        @Test
        func refusedMediaIsUntickedWithoutAStaleSelection() async throws {
            var deselected: [[String]] = []
            let selection = UKFeedbackPhotoSelection(importItem: { _ in nil }, remove: { _ in })
            selection.onDeselect = { deselected.append($0) }

            selection.apply([item("refused")])
            try await UKHostedWindow.wait { !deselected.isEmpty }

            #expect(selection.selected.isEmpty)
            #expect(deselected == [["refused"]])
        }

        @Test
        func closingTheFormRejectsALateCopy() async throws {
            var pending: CheckedContinuation<UUID?, Never>?
            var removed: [UUID] = []
            let selection = UKFeedbackPhotoSelection(
                importItem: { _ in await withCheckedContinuation { pending = $0 } },
                remove: { removed.append($0) }
            )
            selection.apply([item("photo")])
            try await UKHostedWindow.wait { pending != nil }
            selection.close()
            let late = UUID()
            pending?.resume(returning: late)
            try await UKHostedWindow.wait { removed == [late] }

            #expect(selection.selected.isEmpty)
        }
    }
}
#endif
