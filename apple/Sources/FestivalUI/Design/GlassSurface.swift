import SwiftUI
import FestivalDesign

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
/// ``View/festivalCardCapsule()``). Only the drawer (``overlay``) ships glass; ``card``
/// and ``control`` remain for the Debug A/B comparison and hosted-capture canaries.
public enum FestivalGlassRole: Sendable {
    /// The Liquid Glass card the material card replaced (Debug A/B comparison only).
    case card
    /// The Liquid Glass control capsule the material capsule replaced (Debug A/B only).
    case control
    /// Modal and drawer backgrounds that must stay dark enough for contrast.
    case overlay
}

// MARK: - Modifier

/// Apply the shared Festival glass treatment inside a shape.
struct FestivalGlassModifier<S: Shape>: ViewModifier {
    let role: FestivalGlassRole
    let shape: S
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false

    /// Pick system glass when available and allowed, otherwise an opaque-enough fallback.
    ///
    /// - Parameter content: Surface content to decorate.
    /// - Returns: Content with a glass or frosted background clipped to `shape`.
    func body(content: Content) -> some View {
        if reduceTransparency || lessTransparency || moreContrast {
            content.background(BrandTokens.cardBackground, in: shape)
                .overlay(shape.stroke(BrandTokens.borderSubtle, lineWidth: 1))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
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
