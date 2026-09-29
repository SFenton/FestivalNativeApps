import Foundation
import Testing
@testable import FestivalCore

// MARK: - Row contents and states

@Test func hiddenInstrumentsLeaveTheRowAndDropTheirSelection() {
    let selection = InstrumentSelection(instruments: [.lead, .bass, .karaoke], hidden: [.karaoke])
    #expect(selection.available == [.lead, .bass])
    #expect(selection.effectiveSelection(.karaoke) == nil)
    #expect(selection.effectiveSelection(.drums) == nil)
    #expect(selection.effectiveSelection(.bass) == .bass)
}

@Test func buttonStatePrefersSelectionThenDisabledThenMuted() {
    let selection = InstrumentSelection(
        instruments: [.lead, .bass, .drums, .vocals], disabled: [.bass, .vocals], muted: [.drums, .vocals]
    )
    #expect(selection.state(of: .lead, selected: .lead) == .selected)
    #expect(selection.state(of: .bass, selected: .lead) == .disabled)
    #expect(selection.state(of: .drums, selected: .lead) == .muted)
    #expect(selection.state(of: .vocals, selected: nil) == .disabled)
    #expect(selection.state(of: .drums, selected: .drums) == .selected)
}

// MARK: - Full row presses

@Test func tappingTheSelectedButtonClearsItUnlessRequired() {
    let optional = InstrumentSelection(instruments: [.lead, .bass])
    #expect(optional.pressing(.lead, selected: .lead) == .some(nil))
    #expect(optional.pressing(.bass, selected: .lead) == .some(.bass))

    let required = InstrumentSelection(instruments: [.lead, .bass], required: true)
    #expect(required.pressing(.lead, selected: .lead) == .some(.lead))
}

@Test func disabledAndHiddenButtonsIgnorePresses() {
    let selection = InstrumentSelection(instruments: [.lead, .bass, .drums], hidden: [.drums], disabled: [.bass])
    #expect(selection.pressing(.bass, selected: .lead) == nil)
    #expect(selection.pressing(.drums, selected: .lead) == nil)
}

@Test func mutedButtonsStaySelectable() {
    let selection = InstrumentSelection(instruments: [.lead, .bass], muted: [.bass])
    #expect(selection.pressing(.bass, selected: nil) == .some(.bass))
}

// MARK: - Compact mode

@Test func autoCompactMatchesTheWebWidthRule() {
    let five = InstrumentSelection(instruments: [.lead, .bass, .drums, .vocals, .proLead])
    // 5 × 64 + 4 × 12 = 368.
    #expect(five.needsCompact(width: 367, buttonWidth: 64, gap: 12))
    #expect(!five.needsCompact(width: 368, buttonWidth: 64, gap: 12))
    #expect(!five.needsCompact(width: 0, buttonWidth: 64, gap: 12))
    #expect(!InstrumentSelection(instruments: []).needsCompact(width: 10, buttonWidth: 64, gap: 12))
}

@Test func arrowsCycleTheSelectionWrappingAndSkippingDisabled() {
    let selection = InstrumentSelection(instruments: [.lead, .bass, .drums, .vocals], disabled: [.bass])
    #expect(selection.cycle(.next, selected: .lead, previewIndex: 0) == .select(.drums))
    #expect(selection.cycle(.next, selected: .vocals, previewIndex: 0) == .select(.lead))
    #expect(selection.cycle(.previous, selected: .drums, previewIndex: 0) == .select(.lead))
    #expect(selection.cycle(.previous, selected: .lead, previewIndex: 0) == .select(.vocals))
}

@Test func arrowsWithNothingSelectedPickTheEdgeOrMoveThePreview() {
    let immediate = InstrumentSelection(instruments: [.lead, .bass, .drums], disabled: [.lead])
    #expect(immediate.cycle(.next, selected: nil, previewIndex: 0) == .select(.bass))
    #expect(immediate.cycle(.previous, selected: nil, previewIndex: 0) == .select(.drums))

    let deferred = InstrumentSelection(instruments: [.lead, .bass, .drums], deferSelection: true)
    #expect(deferred.cycle(.next, selected: nil, previewIndex: 2) == .preview(0))
    #expect(deferred.cycle(.previous, selected: nil, previewIndex: 0) == .preview(2))
    // Once something is selected, deferred arrows cycle the selection itself.
    #expect(deferred.cycle(.next, selected: .lead, previewIndex: 0) == .select(.bass))
}

@Test func arrowsDoNothingWhenEveryInstrumentIsDisabledOrTheRowIsEmpty() {
    let allDisabled = InstrumentSelection(instruments: [.lead, .bass], disabled: [.lead, .bass])
    #expect(allDisabled.cycle(.next, selected: nil, previewIndex: 0) == .none)
    #expect(InstrumentSelection(instruments: []).cycle(.next, selected: nil, previewIndex: 0) == .none)
}

@Test func compactCentreShowsTheSelectionOrPreviewAndCommitsIt() {
    let selection = InstrumentSelection(instruments: [.lead, .bass, .drums], deferSelection: true)
    #expect(selection.compactCentre(selected: .drums, previewIndex: 0) == .drums)
    #expect(selection.compactCentre(selected: nil, previewIndex: 1) == .bass)
    #expect(selection.compactCentre(selected: nil, previewIndex: 9) == .lead)
    #expect(selection.pressingCentre(selected: nil, previewIndex: 1) == .some(.bass))
    #expect(selection.pressingCentre(selected: .bass, previewIndex: 1) == .some(nil))

    let required = InstrumentSelection(instruments: [.lead, .bass], required: true)
    #expect(required.pressingCentre(selected: .bass, previewIndex: 0) == .some(.bass))

    let disabledCentre = InstrumentSelection(instruments: [.lead, .bass], disabled: [.lead])
    #expect(disabledCentre.pressingCentre(selected: nil, previewIndex: 0) == nil)
    #expect(InstrumentSelection(instruments: []).compactCentre(selected: nil, previewIndex: 0) == nil)
}
