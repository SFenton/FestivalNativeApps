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
        #if os(iOS)
        _image = State(initialValue: previewImage.map(UIImage.init(cgImage:)))
        #else
        _image = State(initialValue: previewImage.map {
            NSImage(cgImage: $0, size: NSSize(width: size, height: size))
        })
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
                ProgressView()
                    .accessibilityLabel("Loading album artwork")
            }
        }
        .frame(width: size, height: size)
        .background(BrandTokens.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: raw) { await load() }
        .onChange(of: raw) { _, _ in
            image = nil
            failure = nil
            fromMemory = false
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
        do {
            let result = try await session.preparedArtwork(
                raw: raw, maxPixels: Int(size * 3)
            )
            try Task.checkCancellation()
            #if os(iOS)
            let decoded = UIImage(cgImage: result.image)
            #else
            let decoded = NSImage(
                cgImage: result.image, size: NSSize(width: size, height: size)
            )
            #endif
            image = decoded
            fromMemory = result.fromMemory
            failure = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            image = nil
            failure = error.localizedDescription
        }
    }
}
