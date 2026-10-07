import SwiftUI
import QuickLookThumbnailing
import FestivalCore
import FestivalDesign
#if os(iOS)
import QuickLook
#elseif os(macOS)
import AppKit
#endif

// MARK: - Strip

/// Attached media shown above Attach Media (issue #78): a thumbnail per file that opens
/// in the system viewer (Quick Look on iOS/iPadOS, the default app on macOS) with a
/// remove button. The app never plays or views media itself.
///
/// HIG (File management, Quick Look): "Use its viewer for attachments or files your app
/// cannot open".
struct FeedbackAttachmentStrip: View {
    let attachments: [FeedbackAttachment]
    let onRemove: (FeedbackAttachment) -> Void
    @State private var previewURL: URL?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    FeedbackAttachmentTile(
                        attachment: attachment, position: index + 1,
                        onOpen: { open(attachment) }, onRemove: { onRemove(attachment) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("fst.settings.feedback.attachments")
        #if os(iOS)
        .quickLookPreview($previewURL, in: attachments.map(\.fileURL))
        #endif
    }

    private func open(_ attachment: FeedbackAttachment) {
        #if os(macOS)
        NSWorkspace.shared.open(attachment.fileURL)
        #else
        previewURL = attachment.fileURL
        #endif
    }
}

// MARK: - Tile

/// One thumbnail button plus its remove button, each at least 44 pt.
private struct FeedbackAttachmentTile: View {
    let attachment: FeedbackAttachment
    let position: Int
    let onOpen: () -> Void
    let onRemove: () -> Void
    @State private var thumbnail: CGImage?
    @Environment(\.displayScale) private var displayScale

    private static let side: CGFloat = 76

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                preview
                    .frame(width: Self.side, height: Self.side)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.18))
                    }
                    .overlay(alignment: .bottomLeading) {
                        if attachment.isVideo {
                            Image(systemName: "play.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.black.opacity(0.55), in: Circle())
                                .padding(5)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 10)
            .accessibilityLabel(attachment.accessibilityLabel(position: position))
            .accessibilityHint(openHint)
            .accessibilityIdentifier("fst.settings.feedback.attachment.\(position)")

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 12, y: -12)
            .accessibilityLabel("Remove \(attachment.filename)")
            .accessibilityIdentifier("fst.settings.feedback.attachment.\(position).remove")
        }
        .padding(.trailing, 12)
        .padding(.top, 2)
        .task(id: attachment.fileURL) { await loadThumbnail() }
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: displayScale)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle().fill(.white.opacity(0.08))
                Image(systemName: attachment.isVideo ? "film" : "photo")
                    .font(.title2)
                    .foregroundStyle(FestivalText.primary)
            }
        }
    }

    private var openHint: String {
        #if os(macOS)
        "Opens in the default app"
        #else
        "Opens in Quick Look"
        #endif
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: attachment.fileURL,
            size: CGSize(width: Self.side, height: Self.side),
            scale: displayScale,
            representationTypes: .thumbnail
        )
        thumbnail = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request).cgImage
    }
}
