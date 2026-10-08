import Foundation

// MARK: - Placement

/// Where Attach Media › Photo Library opens on the feedback form (issue #373).
///
/// HIG (Designing for iPadOS): "minimize modal interfaces and full-screen transitions,
/// keeping controls reachable without obscuring content". HIG (Designing for iPhone Duo):
/// more space "may expose another level if it makes sense for your content … both side by
/// side open". So at regular width on iPad and the iPhone Duo inner display the photo
/// library is the system picker shown inline in a pane beside the form; iPhone, compact
/// windows and the Mac keep the system picker presented over the form. The Files picker
/// has no inline form on any platform, so Choose File… always presents it.
enum FeedbackPhotoLibraryPlacement: Equatable, Sendable {
    /// The system photo picker is presented over the form (iPhone, compact windows, Mac).
    case presented
    /// The system photo picker is shown inline in a pane beside the form.
    case beside

    /// Placement for a window.
    ///
    /// - Parameters:
    ///   - isMac: Running as the macOS app (the Mac keeps its window sheet).
    ///   - windowWidthClass: The window's width class (iPad and the Duo inner display are
    ///     regular; iPhone, the folded Duo and narrow iPad windows are compact).
    /// - Returns: ``beside`` only for a regular-width iPad or Duo window.
    static func resolve(isMac: Bool, windowWidthClass: WidthClass) -> Self {
        !isMac && windowWidthClass == .regular ? .beside : .presented
    }
}

// MARK: - Inline selection links

/// Keeps the inline photo library's selection and the form's attachments in step: a photo
/// ticked in the library becomes an attachment, unticking it removes that attachment, and
/// removing the attachment from the form unticks it (issue #373).
///
/// `Key` is the picker item (`PhotosPickerItem` in the app; any hashable value in tests).
struct FeedbackPickerLinks<Key: Hashable> {
    /// Attachment made from each ticked library item.
    private(set) var attachmentIDs: [Key: UUID] = [:]

    /// Items ticked or unticked between two selections.
    ///
    /// - Parameters:
    ///   - old: Selection before the change.
    ///   - new: Selection after the change.
    /// - Returns: Newly ticked items in selection order, and items no longer ticked.
    static func changes(from old: [Key], to new: [Key]) -> (added: [Key], removed: [Key]) {
        let before = Set(old)
        let after = Set(new)
        var seen = Set<Key>()
        let added = new.filter { !before.contains($0) && seen.insert($0).inserted }
        let removed = old.filter { !after.contains($0) }
        return (added, removed)
    }

    /// Record the attachment made from a ticked item.
    ///
    /// - Parameters:
    ///   - key: The library item.
    ///   - attachmentID: The attachment admitted for it.
    mutating func link(_ key: Key, to attachmentID: UUID) {
        attachmentIDs[key] = attachmentID
    }

    /// Forget an unticked item.
    ///
    /// - Parameter key: The library item.
    /// - Returns: The attachment to remove, or nil when none was admitted for it.
    mutating func unlink(_ key: Key) -> UUID? {
        attachmentIDs.removeValue(forKey: key)
    }

    /// Forget the item behind an attachment removed from the form.
    ///
    /// - Parameter attachmentID: The removed attachment.
    /// - Returns: The library item to untick, or nil when it came from elsewhere.
    mutating func unlink(attachmentID: UUID) -> Key? {
        guard let key = attachmentIDs.first(where: { $0.value == attachmentID })?.key else {
            return nil
        }
        attachmentIDs[key] = nil
        return key
    }

    /// Drop links whose attachments are gone (discarded or removed by other means).
    ///
    /// - Parameter attachmentIDs: Attachments still on the form.
    /// - Returns: Items to untick.
    mutating func prune(keeping attachmentIDs: Set<UUID>) -> [Key] {
        let stale = self.attachmentIDs.filter { !attachmentIDs.contains($0.value) }.map(\.key)
        for key in stale { self.attachmentIDs[key] = nil }
        return stale
    }
}
