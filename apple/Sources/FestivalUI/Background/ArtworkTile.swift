import Foundation
import ImageIO
import SwiftUI
import FestivalCore
import FestivalDesign
#if os(iOS)
import UIKit
private typealias PlatformImage = UIImage
#else
import AppKit
private typealias PlatformImage = NSImage
#endif

/// CGImage is immutable after ImageIO creation and safe to transfer to the UI actor.
struct PreparedArtwork: @unchecked Sendable {
    let image: CGImage
}

/// Share bounded ImageIO decoding between foreground tiles and page backgrounds.
enum ArtworkDecoding {
    /// Downsample and decode image bytes off the UI actor.
    ///
    /// - Parameters:
    ///   - data: Validated artwork bytes from the ephemeral process cache.
    ///   - maxPixels: Largest edge after display-scale allowance.
    /// - Returns: Immutable, decoded thumbnail.
    /// - Throws: `FestivalAPIError.invalidArtwork` for invalid data or dimensions.
    static func prepare(_ data: Data, maxPixels: Int) async throws -> PreparedArtwork {
        guard (1...2048).contains(maxPixels) else {
            throw FestivalAPIError.invalidArtwork
        }
        return try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw FestivalAPIError.invalidArtwork
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source, 0, options as CFDictionary
            ) else {
                throw FestivalAPIError.invalidArtwork
            }
            return PreparedArtwork(image: thumbnail)
        }.value
    }
}

/// One thumbnail backed by ephemeral HTTP and a process-lifetime artwork cache.
struct ArtworkTile: View {
    let raw: String?
    let session: FestivalSession
    let size: CGFloat

    @State private var image: PlatformImage?
    @State private var failure: String?
    @State private var fromMemory = false
    /// Path whose decoded art `image` currently shows, so a rebuilt row that drew a
    /// cached cover in its first frame skips the redundant async reload.
    @State private var loadedRaw: String?

    /// Render only requested art, or inject a thumbnail for hosted visual tests.
    ///
    /// - Parameters:
    ///   - raw: Optional service-provided artwork path.
    ///   - session: Shared ephemeral image and API cache.
    ///   - size: Requested logical width/height in points.
    ///   - previewImage: Already decoded image for deterministic visual assertions.
    init(
        raw: String?, session: FestivalSession, size: CGFloat,
        previewImage: CGImage? = nil
    ) {
        self.raw = raw
        self.session = session
        self.size = size
        // Lazy lists rebuild rows as they scroll back in: draw art this session has
        // already decoded in the first frame, with no spinner or second layout pass.
        let cached = previewImage == nil
            ? Self.cachedImage(raw: raw, session: session, size: size) : nil
        _image = State(initialValue: (previewImage ?? cached).map {
            Self.platformImage(from: $0, size: size)
        })
        _fromMemory = State(initialValue: cached != nil)
        _loadedRaw = State(initialValue: cached != nil ? raw : nil)
    }

    /// Longest decoded edge for a tile: three pixels per point covers every display scale.
    ///
    /// - Parameter size: Logical tile edge in points.
    /// - Returns: Bounded pixel edge passed to the decoded-art cache.
    static func decodedEdge(for size: CGFloat) -> Int {
        Int(size * 3)
    }

    /// Decoded art for `raw` that the session already holds, read without suspending.
    ///
    /// - Parameters:
    ///   - raw: Optional service-provided artwork path.
    ///   - session: Shared ephemeral image cache.
    ///   - size: Logical tile edge in points.
    /// - Returns: The cached image, or nil when it still needs loading.
    private static func cachedImage(
        raw: String?, session: FestivalSession, size: CGFloat
    ) -> CGImage? {
        guard let raw, !raw.isEmpty else { return nil }
        return session.cachedArtwork(raw: raw, maxPixels: decodedEdge(for: size))
    }

    /// Wrap a decoded image for UIKit or AppKit presentation.
    ///
    /// - Parameters:
    ///   - image: Immutable decoded image.
    ///   - size: Logical tile edge in points (AppKit's image size).
    /// - Returns: Platform image for this process.
    private static func platformImage(from image: CGImage, size: CGFloat) -> PlatformImage {
        #if os(iOS)
        UIImage(cgImage: image)
        #else
        NSImage(cgImage: image, size: NSSize(width: size, height: size))
        #endif
    }

    var body: some View {
        Group {
            if let image {
                platformImage(image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel(fromMemory ? "Cached album artwork" : "Album artwork")
            } else if let failure {
                Image(systemName: "photo.bad")
                    .accessibilityLabel("Artwork unavailable: \(failure)")
            } else if raw?.isEmpty != false {
                Image(systemName: "music.note")
                    .accessibilityLabel("No album artwork")
            } else {
                FestivalLoadingView(accessibilityLabel: "Loading album artwork")
            }
        }
        .frame(width: size, height: size)
        .background(BrandTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: raw) { await load() }
        .onChange(of: raw) { _, next in
            let cached = Self.cachedImage(raw: next, session: session, size: size)
            image = cached.map { Self.platformImage(from: $0, size: size) }
            failure = nil
            fromMemory = cached != nil
            loadedRaw = cached != nil ? next : nil
        }
    }

    /// Wrap a decoded platform image in one native SwiftUI drawing primitive.
    ///
    /// - Parameter image: UIKit or AppKit image in this process.
    /// - Returns: SwiftUI Image for compositing in a list or detail header.
    private func platformImage(_ image: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }

    /// Downsample and decode off the main actor to bound artwork render cost.
    ///
    /// - Parameters:
    ///   - data: Image bytes from the in-process cache.
    ///   - maxPixels: Longest displayed edge after backing-scale allowance.
    /// - Returns: Immutable thumbnail ready for UIKit or AppKit presentation.
    /// - Throws: `FestivalAPIError.invalidArtwork` for unsupported image data.
    func prepare(_ data: Data, maxPixels: Int) async throws -> PreparedArtwork {
        try await ArtworkDecoding.prepare(data, maxPixels: maxPixels)
    }

    /// Fetch only visible art; failures keep an explicitly labeled placeholder.
    func load() async {
        guard let raw, !raw.isEmpty else { return }
        if loadedRaw == raw, image != nil { return }
        do {
            let result = try await session.preparedArtwork(
                raw: raw, maxPixels: Self.decodedEdge(for: size)
            )
            try Task.checkCancellation()
            image = Self.platformImage(from: result.image, size: size)
            fromMemory = result.fromMemory
            loadedRaw = raw
            failure = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            image = nil
            loadedRaw = nil
            failure = error.localizedDescription
        }
    }
}
