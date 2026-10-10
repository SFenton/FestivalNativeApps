import SwiftUI
import FestivalDesign
#if os(iOS)
import UIKit
#endif

// MARK: - Glass surface policy

/// How strongly a content surface should read as glass.
///
/// iOS/macOS 26+ render every role with system Liquid Glass. Earlier systems
/// fall back to a dark frosted material so the Fluent "frosted card" look of
/// the web app is preserved without Liquid Glass. See
/// `.agents/design/apple/liquid-glass.md` for which surfaces use which role.
///
/// Content cards and custom floating controls no longer use glass (issue #291): they
/// draw the material card (``View/festivalCard(cornerRadius:)``,
/// ``View/festivalCardCapsule()``). Glass ships on the drawer (``overlay``), the
/// iPhone Duo bottom search field (``control``, owner-approved variant, issue #358) and
/// the backing of the system navigation-bar drawer search field
/// (``SearchFieldBacking``, issue #559); ``card`` remains for the Debug A/B comparison
/// and hosted-capture canaries.
public enum FestivalGlassRole: Sendable {
    /// The Liquid Glass card the material card replaced (Debug A/B comparison only).
    case card
    /// Regular Liquid Glass for a floating control: the iPhone Duo bottom search field
    /// (issue #358) and the Debug A/B comparison of the material capsule.
    case control
    /// Modal and drawer backgrounds that must stay dark enough for contrast.
    case overlay
}

// MARK: - Surface policy

/// Which surface a ``FestivalGlassModifier`` draws for the current accessibility
/// settings and OS.
///
/// surface-materials R4: Reduce Transparency or increased contrast yields an opaque
/// surface with a visible border. Both the system settings and the app's own
/// Reduce Transparency and Increase Contrast toggles count (issue #358: system
/// Increase Contrast had left the Duo bottom search field on Liquid Glass).
enum FestivalGlassSurface: Equatable, Sendable {
    /// Opaque `cardBackground` with a `borderSubtle` stroke.
    case opaque
    /// System Liquid Glass (iOS/macOS 26+).
    case glass
    /// The pre-26 frosted material with the glass rim.
    case frosted

    /// Resolve the surface.
    ///
    /// - Parameters:
    ///   - reduceTransparency: System Reduce Transparency.
    ///   - systemContrast: System Increase Contrast (`colorSchemeContrast`).
    ///   - lessTransparency: The app's Reduce Transparency toggle.
    ///   - moreContrast: The app's Increase Contrast toggle.
    ///   - glassAvailable: Whether the OS draws Liquid Glass.
    /// - Returns: ``opaque`` whenever any accessibility setting asks for it, else
    ///   ``glass`` or, before iOS/macOS 26, ``frosted``.
    nonisolated static func resolve(
        reduceTransparency: Bool, systemContrast: ColorSchemeContrast,
        lessTransparency: Bool, moreContrast: Bool, glassAvailable: Bool
    ) -> Self {
        if reduceTransparency || systemContrast == .increased || lessTransparency || moreContrast {
            return .opaque
        }
        return glassAvailable ? .glass : .frosted
    }

    /// Whether this OS draws Liquid Glass (iOS/macOS 26+).
    nonisolated static var glassAvailable: Bool {
        if #available(iOS 26.0, macOS 26.0, *) { return true }
        return false
    }
}

// MARK: - Accessibility settings

/// The system and in-app settings that choose a ``FestivalGlassSurface`` (R4), read
/// once for every glass consumer.
struct FestivalGlassSettings: DynamicProperty {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false

    /// The surface for the current settings on this OS.
    var surface: FestivalGlassSurface {
        FestivalGlassSurface.resolve(
            reduceTransparency: reduceTransparency, systemContrast: systemContrast,
            lessTransparency: lessTransparency, moreContrast: moreContrast,
            glassAvailable: FestivalGlassSurface.glassAvailable
        )
    }

    /// The backing for a system drawer search field (``SearchFieldBacking``, #559).
    var searchFieldBacking: SearchFieldBacking {
        SearchFieldBacking.resolve(surface, glassAvailable: FestivalGlassSurface.glassAvailable)
    }
}

// MARK: - Modifier

/// Apply the shared Festival glass treatment inside a shape.
struct FestivalGlassModifier<S: Shape>: ViewModifier {
    let role: FestivalGlassRole
    let shape: S
    let interactive: Bool
    private var settings = FestivalGlassSettings()

    /// Pick system glass when available and allowed, otherwise an opaque-enough fallback.
    ///
    /// - Parameter content: Surface content to decorate.
    /// - Returns: Content with a glass, frosted or opaque background clipped to `shape`.
    @ViewBuilder
    func body(content: Content) -> some View {
        switch settings.surface {
        case .opaque:
            content.background(BrandTokens.cardBackground, in: shape)
                .overlay(shape.stroke(BrandTokens.borderSubtle, lineWidth: 1))
        case .glass:
            if #available(iOS 26.0, macOS 26.0, *) {
                content.glassEffect(glass, in: shape)
            } else {
                content
            }
        case .frosted:
            content
                .background(fallbackTint, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(BrandTokens.glassBorder, lineWidth: 1))
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var glass: Glass {
        let base: Glass = switch role {
        case .card: .regular.tint(BrandTokens.cardBackground.opacity(0.35))
        case .control: .regular
        case .overlay: .regular.tint(BrandTokens.cardBackground.opacity(0.7))
        }
        return interactive ? base.interactive() : base
    }

    private var fallbackTint: Color {
        switch role {
        case .card: BrandTokens.surfaceFrosted
        case .control: BrandTokens.surfaceFrosted.opacity(0.6)
        case .overlay: BrandTokens.cardBackground.opacity(0.85)
        }
    }
}

public extension View {
    /// Render this view on a Festival glass surface.
    ///
    /// - Parameters:
    ///   - role: Semantic surface role; controls tint and fallback opacity.
    ///   - cornerRadius: Continuous corner radius of the surface.
    ///   - interactive: Whether iOS 26 glass should respond to touches.
    /// - Returns: The decorated view.
    func festivalGlass(
        _ role: FestivalGlassRole = .card,
        cornerRadius: CGFloat = 16,
        interactive: Bool = false
    ) -> some View {
        modifier(FestivalGlassModifier(
            role: role,
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            interactive: interactive
        ))
    }

    /// Render this view on a capsule-shaped Festival glass surface.
    ///
    /// - Parameters:
    ///   - role: Semantic surface role.
    ///   - interactive: Whether iOS 26 glass should respond to touches.
    /// - Returns: The decorated view.
    func festivalGlassCapsule(
        _ role: FestivalGlassRole = .control,
        interactive: Bool = false
    ) -> some View {
        modifier(FestivalGlassModifier(role: role, shape: Capsule(), interactive: interactive))
    }
}

// MARK: - Grouping

/// Groups adjacent glass surfaces so iOS 26 can blend and morph them together.
///
/// Material cards (``View/festivalCard(cornerRadius:)``) never merge; do not wrap them.
///
/// On earlier systems this is a plain container.
public struct FestivalGlassGroup<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    /// Create a group of related glass surfaces.
    ///
    /// - Parameters:
    ///   - spacing: Distance at which neighbouring glass shapes start to merge.
    ///   - content: Glass-decorated children.
    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - System search field backing

/// What a system search field in the navigation-bar drawer draws behind its glyph and
/// text (issue #559).
///
/// On iOS 26/27 UIKit gives a drawer search field a flat `tertiarySystemFill` while the
/// list sits at its top edge and turns it into Liquid Glass only once content scrolls
/// under the bar, so the field changed material as the page scrolled. The backing gives
/// the field the regular Liquid Glass of the iPhone Duo bottom search field (#358) at
/// every scroll position, and the same opaque `cardBackground` + `borderSubtle` capsule
/// under Reduce Transparency or Increase Contrast, system or in-app (R4). Earlier
/// systems keep the classic system field.
enum SearchFieldBacking: Equatable, Sendable {
    /// No backing: the system field as UIKit draws it.
    case none
    /// Regular Liquid Glass.
    case glass
    /// Opaque `cardBackground` with a 1 pt `borderSubtle` stroke.
    case opaque

    /// The backing for a resolved surface.
    ///
    /// - Parameters:
    ///   - surface: The ``FestivalGlassSurface`` for the current settings.
    ///   - glassAvailable: Whether the OS draws Liquid Glass.
    /// - Returns: ``none`` before iOS 26, whose system field never switches to glass.
    nonisolated static func resolve(_ surface: FestivalGlassSurface, glassAvailable: Bool) -> Self {
        guard glassAvailable else { return .none }
        switch surface {
        case .glass: return .glass
        case .opaque: return .opaque
        case .frosted: return .none
        }
    }

    /// Whether a push or pop of the field's page needs the system search-field fill.
    ///
    /// A navigation transition slides a portal of the search bar that draws neither the
    /// system glass nor this glass backing (issue #544), so the fill stands in for them.
    /// An opaque backing draws in the portal and needs none.
    ///
    /// - Parameter contentUnderBar: Whether content is scrolled under the bar, when the
    ///   system field draws its own glass.
    /// - Returns: True while either glass is showing.
    nonisolated func needsTransitionFill(contentUnderBar: Bool) -> Bool {
        switch self {
        case .glass: true
        case .opaque: false
        case .none: contentUnderBar
        }
    }
}

#if os(iOS)
/// The capsule that draws a ``SearchFieldBacking`` inside a system `UISearchTextField`,
/// below its glyph, prompt and text.
///
/// It is decoration only: it takes no touches and is hidden from accessibility, so the
/// field keeps its system focus, clear button, keyboard and VoiceOver search-field role.
@available(iOS 26.0, *)
final class SearchFieldBackingView: UIView {
    private(set) var backing: SearchFieldBacking = .none
    private var glassView: UIVisualEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cornerConfiguration = .capsule()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Draw a backing.
    ///
    /// - Parameter backing: Glass or the opaque fallback (``SearchFieldBacking/none``
    ///   clears it).
    func render(_ backing: SearchFieldBacking) {
        guard backing != self.backing else { return }
        self.backing = backing
        glassView?.removeFromSuperview()
        glassView = nil
        backgroundColor = nil
        layer.borderWidth = 0
        switch backing {
        case .glass:
            let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            glass.frame = bounds
            glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            glass.cornerConfiguration = .capsule()
            glass.isUserInteractionEnabled = false
            addSubview(glass)
            glassView = glass
        case .opaque:
            backgroundColor = UIColor(BrandTokens.cardBackground)
            layer.borderColor = UIColor(BrandTokens.borderSubtle).cgColor
            layer.borderWidth = 1
        case .none:
            break
        }
    }

    /// Install, update or remove the backing of a system search field.
    ///
    /// The backing becomes the field's bottom subview, and the field's own fill is cleared
    /// so the flat `tertiarySystemFill` no longer tints the capsule at the top edge.
    ///
    /// - Parameters:
    ///   - backing: The backing to draw.
    ///   - field: The search bar's text field.
    static func apply(_ backing: SearchFieldBacking, to field: UISearchTextField) {
        let existing = field.subviews.lazy.compactMap { $0 as? SearchFieldBackingView }.first
        guard backing != .none else {
            if let existing {
                existing.removeFromSuperview()
                field.backgroundColor = nil
            }
            return
        }
        let view = existing ?? SearchFieldBackingView(frame: field.bounds)
        if view.superview !== field || field.subviews.first !== view {
            field.insertSubview(view, at: 0)
        }
        view.frame = field.bounds
        view.render(backing)
        field.backgroundColor = .clear
    }

    /// The backing a field draws now.
    ///
    /// - Parameter field: The search bar's text field.
    /// - Returns: ``SearchFieldBacking/none`` when it has no backing.
    static func backing(of field: UISearchTextField) -> SearchFieldBacking {
        field.subviews.lazy.compactMap { $0 as? SearchFieldBackingView }.first?.backing ?? .none
    }
}
#endif
