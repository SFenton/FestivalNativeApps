import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Settings value row

/// The read-only Settings title/value row (pattern `settings-value-row`): Version's App
/// Version, Build Configuration and Service Version, and Service Info's Leaderboard Service
/// State.
///
/// The value sits at the row's end while the title, a 12 pt gap and the value fit at their
/// natural widths, and otherwise stacks 4 pt under the title and supporting text (R1, R2).
/// The row is one non-interactive accessibility element read title → supporting → value
/// (R3): VoiceOver otherwise reads the title and value as two unrelated texts (HIG
/// VoiceOver: "Specify how elements are grouped, ordered or linked where relationships are
/// only visual", should).
struct SettingsValueRow<Value: View>: View {
    private let title: String
    private let detail: String?
    private let spokenValue: String
    private let identifier: String
    private let value: Value

    /// Create a row with a custom trailing value (text plus a spinner, for example).
    ///
    /// - Parameters:
    ///   - title: Title Case row name.
    ///   - detail: Optional sentence-case supporting text under the title.
    ///   - spokenValue: The value as VoiceOver reads it.
    ///   - identifier: The row's accessibility identifier (`fst.settings.*`).
    ///   - value: The trailing (or stacked) value view.
    init(
        _ title: String, detail: String? = nil, spokenValue: String, identifier: String,
        @ViewBuilder value: () -> Value
    ) {
        self.title = title
        self.detail = detail
        self.spokenValue = spokenValue
        self.identifier = identifier
        self.value = value()
    }

    var body: some View {
        SettingsValueRowLayout {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(FestivalText.primary)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(FestivalText.primary)
            }
            value
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        // Static text (no button or other role, R3); without it the Mac tree reports an
        // unknown role and drops the value.
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(SettingsValueRowLayout.spokenLabel(title: title, detail: detail))
        .accessibilityValue(spokenValue)
        .accessibilityIdentifier(identifier)
    }
}

extension SettingsValueRow where Value == SettingsValueText {
    /// Create a row whose value is plain text.
    ///
    /// - Parameters:
    ///   - title: Title Case row name.
    ///   - value: The displayed value.
    ///   - spokenValue: The value as VoiceOver reads it, when it differs from the text
    ///     (e.g. `AppBuildInfo.spokenVersionText`); nil reads `value`.
    ///   - identifier: The row's accessibility identifier (`fst.settings.*`).
    init(_ title: String, value: String, spokenValue: String? = nil, identifier: String) {
        self.init(title, spokenValue: spokenValue ?? value, identifier: identifier) {
            SettingsValueText(text: value)
        }
    }
}

/// A value row's plain text value, in the body style and primary text.
struct SettingsValueText: View {
    let text: String

    var body: some View {
        Text(text).foregroundStyle(FestivalText.primary)
    }
}

/// Settings → Version → App Version: `0.1.0 (42) · 42edc57` on a release-stamped build
/// (issue #3), read as "App Version, 0.1.0, build 42, commit 42edc57".
struct SettingsAppVersionRow: View {
    /// The bundle's Info.plist dictionary (`Bundle.main.infoDictionary` in the app).
    let info: [String: Any]?

    var body: some View {
        SettingsValueRow(
            "App Version", value: AppBuildInfo.versionText(info),
            spokenValue: AppBuildInfo.spokenVersionText(info), identifier: "fst.settings.app-version"
        )
    }
}

// MARK: - Layout

/// Places a value row's title, optional supporting text and value: inline when the title
/// and value fit side by side at their natural widths, stacked otherwise (R1). Subviews are
/// title, then supporting text when present, then the value (last).
struct SettingsValueRowLayout: Layout {
    /// Gap between the title column and an inline value (R2).
    static let inlineGap: CGFloat = 12
    /// Spacing between title, supporting text and a stacked value (R2).
    static let stackSpacing: CGFloat = 4

    /// Whether the value stays beside the title. Supporting text never counts: it wraps
    /// under the title.
    ///
    /// - Parameters:
    ///   - titleWidth: The title's natural (unwrapped) width.
    ///   - valueWidth: The value's natural width.
    ///   - available: The row's content width, or nil when unconstrained.
    /// - Returns: True when title + gap + value fit the row.
    static func fitsInline(titleWidth: CGFloat, valueWidth: CGFloat, available: CGFloat?) -> Bool {
        guard let available, available.isFinite else { return true }
        return titleWidth + inlineGap + valueWidth <= available
    }

    /// The row's accessibility label: the title, then its supporting text (R3).
    ///
    /// - Parameters:
    ///   - title: Row title.
    ///   - detail: Optional supporting text.
    /// - Returns: `"Title"` or `"Title, supporting text"`.
    static func spokenLabel(title: String, detail: String?) -> String {
        guard let detail, !detail.isEmpty else { return title }
        return "\(title), \(detail)"
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, arrangement.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading, proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// The row size and each subview's frame, in subview order.
    private func arrange(width: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        guard let title = subviews.first, let value = subviews.last, subviews.count >= 2 else {
            return (.zero, subviews.map { _ in .zero })
        }
        let detail = subviews.count > 2 ? subviews[1] : nil
        let titleIdeal = title.sizeThatFits(.unspecified)
        let valueIdeal = value.sizeThatFits(.unspecified)
        let available = width.flatMap { $0.isFinite ? $0 : nil }

        if Self.fitsInline(titleWidth: titleIdeal.width, valueWidth: valueIdeal.width, available: available) {
            let leadingWidth = available.map { max(0, $0 - Self.inlineGap - valueIdeal.width) }
                ?? max(titleIdeal.width, detail?.sizeThatFits(.unspecified).width ?? 0)
            let titleSize = title.sizeThatFits(ProposedViewSize(width: leadingWidth, height: nil))
            let detailSize = detail?.sizeThatFits(ProposedViewSize(width: leadingWidth, height: nil))
            let leadingHeight = titleSize.height + (detailSize.map { Self.stackSpacing + $0.height } ?? 0)
            let height = max(leadingHeight, valueIdeal.height)
            let total = available ?? (leadingWidth + Self.inlineGap + valueIdeal.width)
            let top = (height - leadingHeight) / 2
            var frames = [CGRect(x: 0, y: top, width: leadingWidth, height: titleSize.height)]
            if let detailSize {
                frames.append(CGRect(
                    x: 0, y: top + titleSize.height + Self.stackSpacing, width: leadingWidth, height: detailSize.height
                ))
            }
            frames.append(CGRect(
                x: total - valueIdeal.width, y: (height - valueIdeal.height) / 2,
                width: valueIdeal.width, height: valueIdeal.height
            ))
            return (CGSize(width: total, height: height), frames)
        }

        let rowWidth = available ?? titleIdeal.width
        var frames: [CGRect] = []
        var y: CGFloat = 0
        for subview in [title, detail, value].compactMap({ $0 }) {
            if !frames.isEmpty { y += Self.stackSpacing }
            let size = subview.sizeThatFits(ProposedViewSize(width: rowWidth, height: nil))
            frames.append(CGRect(x: 0, y: y, width: min(size.width, rowWidth), height: size.height))
            y += size.height
        }
        return (CGSize(width: rowWidth, height: y), frames)
    }
}
