#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Artwork tile

/// One album-art thumbnail backed by the shared bounded caches: the UIKit counterpart of
/// ``ArtworkTile``.
///
/// Decorative in every state (issue #403): hidden from accessibility, so it never reaches
/// VoiceOver even inside a row that combines its children. A reused cell calls
/// ``configure(raw:session:)`` again; the tile draws art the session already decoded in the
/// first frame, with no spinner, and otherwise loads it through
/// `FestivalSession.preparedArtwork` (cached, bounded, never persisted).
final class UKArtworkTileView: UIView {
    private let imageView = UIImageView()
    private let placeholder = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let size: CGFloat
    private var raw: String?
    private var loadedRaw: String?
    private var task: Task<Void, Never>?

    /// Creates a tile.
    ///
    /// - Parameter size: Logical width and height in points.
    init(size: CGFloat) {
        self.size = size
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        backgroundColor = BrandUIColors.cardBackground
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        placeholder.tintColor = BrandUIColors.textPrimary
        placeholder.contentMode = .center
        spinner.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        for view in [imageView, placeholder, spinner] {
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.isHidden = true
            addSubview(view)
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { CGSize(width: size, height: size) }

    deinit { task?.cancel() }

    // MARK: Configuration

    /// Show a song's artwork.
    ///
    /// - Parameters:
    ///   - raw: Service-provided artwork path, if any.
    ///   - session: Shared ephemeral image and API cache.
    func configure(raw: String?, session: FestivalSession) {
        guard raw != self.raw || loadedRaw == nil else { return }
        task?.cancel()
        self.raw = raw
        loadedRaw = nil
        guard let raw, !raw.isEmpty else {
            show(placeholder: "music.note")
            return
        }
        let edge = ArtworkTile.decodedEdge(for: size)
        if let cached = session.cachedArtwork(raw: raw, maxPixels: edge) {
            show(image: cached)
            loadedRaw = raw
            return
        }
        showLoading()
        task = Task { [weak self] in
            do {
                let result = try await session.preparedArtwork(raw: raw, maxPixels: edge)
                try Task.checkCancellation()
                self?.show(image: result.image)
                self?.loadedRaw = raw
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.show(placeholder: "photo.bad")
            }
        }
    }

    private func show(image: CGImage) {
        imageView.image = UIImage(cgImage: image)
        imageView.isHidden = false
        placeholder.isHidden = true
        spinner.stopAnimating()
        spinner.isHidden = true
    }

    private func show(placeholder symbol: String) {
        imageView.image = nil
        imageView.isHidden = true
        placeholder.image = UIImage(systemName: symbol)
        placeholder.isHidden = false
        spinner.stopAnimating()
        spinner.isHidden = true
    }

    private func showLoading() {
        imageView.image = nil
        imageView.isHidden = true
        placeholder.isHidden = true
        spinner.isHidden = false
        spinner.startAnimating()
    }
}
#endif
