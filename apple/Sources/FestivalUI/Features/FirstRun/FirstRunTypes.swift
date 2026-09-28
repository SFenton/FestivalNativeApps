import SwiftUI

// MARK: - FirstRunGateContext

/// Native subset of the web's `FirstRunGateContext`
/// (`FortniteFestivalWeb/src/firstRun/types.ts`): predicates a slide's `gate`
/// closure can inspect before it is offered.
struct FirstRunGateContext: Equatable {
    /// True when a player profile is currently selected.
    var hasPlayer: Bool
    /// True when `FST_DEBUG_FIRST_RUN=force` bypasses seen-state for screenshots/QA.
    var alwaysShow: Bool = false
}

// MARK: - FirstRunSlideDef

/// One page of a first-run carousel; native port of the web's `FirstRunSlideDef`.
struct FirstRunSlideDef: Identifiable {
    /// Stable identifier used as the seen-state key, e.g. `"playerhistory-score-list"`.
    let id: String
    /// Bump only when users who already dismissed this slide should see it again.
    let version: Int
    /// Slide title, shown under the demo content.
    let title: String
    /// Slide description, shown under the title.
    let description: String
    /// Predicate — the slide is offered only when this returns true. Nil means "always".
    let gate: ((FirstRunGateContext) -> Bool)?
    /// Illustrative demo content for the slide.
    let render: () -> AnyView

    /// Create a slide definition.
    ///
    /// - Parameters:
    ///   - id: Stable seen-state key.
    ///   - version: Replay-contract version; bump to force a reshow.
    ///   - title: Slide title.
    ///   - description: Slide description.
    ///   - gate: Optional visibility predicate.
    ///   - render: Illustrative content builder.
    init(
        id: String, version: Int, title: String, description: String,
        gate: ((FirstRunGateContext) -> Bool)? = nil,
        @ViewBuilder render: @escaping () -> some View
    ) {
        self.id = id
        self.version = version
        self.title = title
        self.description = description
        self.gate = gate
        self.render = { AnyView(render()) }
    }
}
