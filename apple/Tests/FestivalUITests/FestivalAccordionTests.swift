#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalUI
import FestivalDesign

// MARK: - Choreography (pattern `accordion`, issue #561)

@Test func accordionOpensContainerThenFadesContentIn() {
    let steps = AccordionChoreography.plan(expanded: true, from: .settled(false), reduceMotion: false)
    #expect(steps == [
        .init(delay: 0, change: .open),
        .init(delay: AccordionChoreography.resizeDuration, change: .showContent),
    ])
}

@Test func accordionFadesContentOutThenClosesContainer() {
    let steps = AccordionChoreography.plan(expanded: false, from: .settled(true), reduceMotion: false)
    #expect(steps == [
        .init(delay: 0, change: .hideContent),
        .init(delay: AccordionChoreography.fadeDuration, change: .close),
    ])
}

@Test func accordionReversesFromWhereTheMotionIs() {
    let openHidden = AccordionChoreography.Phase(isOpen: true, showsContent: false)
    // Reopened while the close was still fading: only the fade-in remains.
    #expect(AccordionChoreography.plan(expanded: true, from: openHidden, reduceMotion: false)
        == [.init(delay: 0, change: .showContent)])
    // Closed before the content faded in: the container closes at once.
    #expect(AccordionChoreography.plan(expanded: false, from: openHidden, reduceMotion: false)
        == [.init(delay: 0, change: .close)])
    #expect(AccordionChoreography.plan(expanded: true, from: .settled(true), reduceMotion: false).isEmpty)
    #expect(AccordionChoreography.plan(expanded: false, from: .settled(false), reduceMotion: false).isEmpty)
}

@Test func accordionMotionMatchesWebQuickFade() {
    // Web `QUICK_FADE_MS` (150 ms) per half; together the web `CollapseOnExit` 300 ms exit.
    #expect(AccordionChoreography.resizeDuration == 0.15)
    #expect(AccordionChoreography.fadeDuration == 0.15)
    #expect(AccordionChoreography.resizeDuration + AccordionChoreography.fadeDuration == 0.3)
}

@Test func accordionPhaseFollowsEachChange() {
    var phase = AccordionChoreography.Phase.settled(false)
    let sequence = AccordionChoreography.plan(expanded: true, from: phase, reduceMotion: false)
        + AccordionChoreography.plan(expanded: false, from: .settled(true), reduceMotion: false)
    var seen: [AccordionChoreography.Phase] = []
    for step in sequence {
        phase = phase.applying(step.change)
        seen.append(phase)
    }
    #expect(seen == [
        .init(isOpen: true, showsContent: false),
        .init(isOpen: true, showsContent: true),
        .init(isOpen: true, showsContent: false),
        .init(isOpen: false, showsContent: false),
    ])
}

@Test func accordionStateSwapsContentInPlaceWhileOpen() {
    var state = FestivalAccordionState<String>("Lead")
    state.request("Bass")
    #expect(state.shown == "Bass")
    #expect(state.showsContent)
    #expect(AccordionChoreography.plan(expanded: true, from: state.phase, reduceMotion: false).isEmpty)

    var closed = FestivalAccordionState<String>(nil)
    closed.request("Drums")
    // Nothing is laid out until the planned `open` step.
    #expect(closed.shown == nil)
    closed.apply(.open)
    #expect(closed.shown == "Drums")
    #expect(!closed.showsContent)
    closed.apply(.showContent)
    #expect(closed.phase == .settled(true))
    closed.request(nil)
    #expect(closed.shown == "Drums")
    closed.apply(.hideContent)
    closed.apply(.close)
    #expect(closed.shown == nil)
    #expect(closed.phase == .settled(false))
}

@Test func accordionBoolStateReportsRequestedDisclosure() {
    var state = FestivalAccordionState(expanded: false)
    #expect(!state.isExpanded)
    state.request(true)
    // VoiceOver hears the new state at once, while the sequence still runs.
    #expect(state.isExpanded)
    #expect(FestivalAccordionState(expanded: true).phase == .settled(true))
}

// MARK: - Reduce Motion (accessibility)

@Test func accordionUnderReduceMotionKeepsOnlyTheFade() {
    #expect(AccordionChoreography.animation(for: .open, reduceMotion: true) == nil)
    #expect(AccordionChoreography.animation(for: .close, reduceMotion: true) == nil)
    #expect(AccordionChoreography.animation(for: .showContent, reduceMotion: true) != nil)
    #expect(AccordionChoreography.animation(for: .hideContent, reduceMotion: true) != nil)
    #expect(AccordionChoreography.animation(for: .open, reduceMotion: false) != nil)
    let steps = AccordionChoreography.plan(expanded: true, from: .settled(false), reduceMotion: true)
    #expect(steps.map(\.change) == [.open, .showContent])
    #expect(steps[1].delay == AccordionChoreography.reducedMotionSettle)
    #expect(steps[1].delay < AccordionChoreography.resizeDuration)
}

// MARK: - Hosted accessibility

/// Content that is laid out but not yet faded in is hidden from VoiceOver; once shown, it is
/// read after its header.
@MainActor
@Test func accordionContentIsHiddenFromVoiceOverUntilItFadesIn() async throws {
    let size = CGSize(width: 320, height: 160)
    var opening = FestivalAccordionState<Bool>(nil)
    opening.request(true)
    opening.apply(.open)
    for (state, readable) in [(opening, false), (FestivalAccordionState<Bool>(expanded: true), true)] {
        let host = nativeHostedView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Accordion Header").accessibilityIdentifier("fst.test.accordion.header")
                FestivalAccordionContent(state) {
                    Text("Accordion Row").accessibilityIdentifier("fst.test.accordion.row")
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: ["Accordion Header"])
        let row = nativeHostedAccessibilityElement("fst.test.accordion.row", in: host)
        #expect((row != nil) == readable)
        #expect(nativeHostedAccessibility(host).contains("Accordion Row") == readable)
        if readable, let row,
           let header = nativeHostedAccessibilityFrame("fst.test.accordion.header", in: host),
           let rowFrame = nativeHostedAccessibilityFrame(of: row, in: host) {
            #expect(header.minY < rowFrame.minY)
        }
    }
}

/// The system disclosure group keeps its header readable and shows its rows when expanded.
@MainActor
@Test func festivalDisclosureGroupKeepsSystemDisclosureAndRows() async throws {
    let size = CGSize(width: 360, height: 220)
    let host = nativeHostedView(
        Form {
            FestivalDisclosureGroup(initiallyExpanded: true) {
                Text("Disclosure Row").accessibilityIdentifier("fst.test.disclosure.row")
            } label: {
                Text("Disclosure Header")
            }
        }
        .formStyle(.grouped)
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let expected = ["Disclosure Header", "Disclosure Row"]
    let image = try await nativeHostedSettle(host, untilText: expected)
    assertRendersContent(host, image: image, containing: expected)
}

/// A driven accordion runs open → fade in, then fade out → close, in that order.
@MainActor
@Test func drivenAccordionSequencesOpenThenFadeAndFadeThenClose() async throws {
    let model = AccordionHarnessModel()
    let size = CGSize(width: 320, height: 160)
    let host = nativeHostedView(AccordionHarness(model: model), size: size)
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: ["Harness Anchor"])
    #expect(model.phases.last == .settled(false))

    model.isOn = true
    try await nativeHostedSettle(host, untilText: ["Harness Row"])
    try await nativeHostedSettle(host) { model.phases.last == .settled(true) }
    model.isOn = false
    try await nativeHostedSettle(host, untilText: ["Harness Anchor"], excluding: ["Harness Row"])
    try await nativeHostedSettle(host) { model.phases.last == .settled(false) }

    var deduplicated: [AccordionChoreography.Phase] = []
    for phase in model.phases where deduplicated.last != phase { deduplicated.append(phase) }
    #expect(deduplicated == [
        .settled(false),
        .init(isOpen: true, showsContent: false),
        .settled(true),
        .init(isOpen: true, showsContent: false),
        .settled(false),
    ])
}

@MainActor @Observable
private final class AccordionHarnessModel {
    var isOn = false
    var phases: [AccordionChoreography.Phase] = []
}

private struct AccordionHarness: View {
    let model: AccordionHarnessModel
    @State private var accordion = FestivalAccordionState<Bool>(nil)

    var body: some View {
        VStack(alignment: .leading) {
            Text("Harness Anchor")
                .festivalAccordion($accordion, follows: model.isOn ? true : nil)
            FestivalAccordionContent(accordion) { Text("Harness Row") }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BrandTokens.cardBackground)
        .onAppear { model.phases.append(accordion.phase) }
        .onChange(of: accordion.phase) { _, phase in model.phases.append(phase) }
    }
}
#endif
