import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Privacy policy sheet

/// Settings › Privacy Policy (issue #98): the shared policy text in a modal sheet.
///
/// Renders ``PrivacyPolicy/current`` (the copy of `contracts/privacy-policy.json`) verbatim:
/// the effective date, then each section's heading and its paragraphs and bullet lists, with
/// short bullet labels in bold and web addresses as links. It is built on ``FestivalModal`` (inline title, system Close top-right) and
/// presented with `festivalSheet(.large)`, so iPhone also dismisses with a downward swipe,
/// iPad and unfolded Duo get the centred form sheet, and the Mac gets a window-modal sheet.
///
/// HIG Modality: "Always provide an obvious, platform-conventional dismissal … Identify the
/// task with a title". Text uses Dynamic Type styles, headings carry the header trait and
/// the text is selectable.
struct PrivacyPolicySheet: View {
    let policy: PrivacyPolicy

    /// Create the sheet.
    ///
    /// - Parameter policy: Policy to show; the current one by default (hosted tests inject).
    init(policy: PrivacyPolicy = .current) {
        self.policy = policy
    }

    var body: some View {
        FestivalModal(policy.title, closeIdentifier: "fst.privacy-policy.close") {
            ScrollView {
                PrivacyPolicyContent(policy: policy)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
            .accessibilityIdentifier("fst.privacy-policy.content")
        }
        #if os(macOS)
        // HIG Sheets (macOS): "Present a sheet in a reasonable default size". A scroll view
        // has no ideal size, so give the sheet one that fits inside the Settings window.
        .frame(minWidth: 480, idealWidth: 620, minHeight: 420, idealHeight: 560)
        #endif
        .festivalSheet(.large)
    }
}

// MARK: - Policy content

/// The policy's effective date and sections, shared by ``PrivacyPolicySheet`` and the
/// list/detail Settings' Privacy Policy pane (issue #371), which shows it inline on the
/// right instead of a sheet. The caller scrolls and pads it.
struct PrivacyPolicyContent: View {
    let policy: PrivacyPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(policy.effectiveDateText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FestivalText.primary)
                .accessibilityIdentifier("fst.privacy-policy.effective-date")
            ForEach(policy.sections) { section in
                sectionView(section)
            }
        }
        .textSelection(.enabled)
        .tint(BrandTokens.accentBlue)
    }

    // MARK: - Blocks

    private func sectionView(_ section: PrivacyPolicy.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.headline)
                .foregroundStyle(FestivalText.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("fst.privacy-policy.section.\(section.id)")
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder private func blockView(_ block: PrivacyPolicy.Block) -> some View {
        switch block {
        case .paragraph(let text):
            bodyText(PrivacyPolicy.styledText(text, boldLead: false))
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "•")
                            .font(.body)
                            .foregroundStyle(FestivalText.primary)
                            .accessibilityHidden(true)
                        bodyText(PrivacyPolicy.styledText(item, boldLead: true))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func bodyText(_ text: AttributedString) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(FestivalText.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
