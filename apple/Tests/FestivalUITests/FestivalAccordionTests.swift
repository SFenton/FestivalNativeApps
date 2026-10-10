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

/// Content that is laid out but transparent takes no clicks (R4): a click on the row's spot
/// while it is waiting to fade in does nothing, and the same click lands once it shows.
@MainActor
@Test func transparentAccordionContentIsNotHittable() async throws {
    let size = CGSize(width: 320, height: 160)
    let presses = AccordionPressCounter()
    var opening = FestivalAccordionState<Bool>(nil)
    opening.request(true)
    opening.apply(.open)
    var target: CGPoint?
    for (state, hittable) in [(FestivalAccordionState<Bool>(expanded: true), true), (opening, false)] {
        let host = nativeHostedView(
            VStack(alignment: .leading, spacing: 0) {
                Text("Accordion Header").frame(height: 40)
                FestivalAccordionContent(state) {
                    // A filter switch, like the accordions' rows (AppKit-backed on macOS).
                    Toggle("Accordion Row", isOn: Binding(get: { false }, set: { _ in presses.count += 1 }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .frame(height: 44)
                        .accessibilityIdentifier("fst.test.accordion.press")
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
        // Still 10,000 pt off screen; AppKit delivers clicks only to an ordered-in window.
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: ["Accordion Header"])
        if hittable {
            // The opaque row's own frame; the transparent one is laid out in the same place.
            let frame = try #require(nativeHostedAccessibilityFrame("fst.test.accordion.press", in: host))
            target = CGPoint(x: frame.midX, y: frame.midY)
        } else {
            #expect(nativeHostedAccessibilityElement("fst.test.accordion.press", in: host) == nil)
        }
        let before = presses.count
        nativeHostedClick(try #require(target), in: host, window: window)
        try await nativeHostedSettle(host)
        #expect(presses.count - before == (hittable ? 1 : 0), "hittable: \(hittable)")
    }
}

/// Closing a disclosure group speaks Collapsed at once (R4), while its rows are still laid
/// out and fading; the group collapses only after the fade.
@MainActor
@Test func closingDisclosureAnnouncesCollapsedBeforeTheFadeEnds() async throws {
    let model = AccordionHarnessModel()
    model.isOn = true
    let size = CGSize(width: 360, height: 220)
    let host = nativeHostedView(DisclosureHarness(model: model), size: size)
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: ["Disclosure Row"])
    func header() -> NSObject? {
        nativeHostedAccessibilityElement(in: host) {
            nativeHostedAccessibilityString($0, "accessibilityLabel") == "Disclosure Header"
        }
    }
    func spoken(_ element: NSObject) -> String {
        // macOS: the label's value is the disclosure triangle's value description.
        let description = nativeHostedAccessibilityString(element, "accessibilityValueDescription")
        return description.isEmpty ? nativeHostedAccessibilityString(element, "accessibilityValue") : description
    }
    let expanded = try #require(header())
    #expect(spoken(expanded) == "Expanded")
    #expect(model.phases.last == .settled(true))

    // The same request the disclosure's binding makes on a tap (hosted AppKit ignores
    // synthetic presses on SwiftUI's disclosure triangle).
    model.isOn = false
    let clock = ContinuousClock()
    let pressed = clock.now
    var collapsedWhileOpen = false
    while clock.now - pressed < .seconds(2) {
        try await Task.sleep(for: .milliseconds(5))
        host.layoutSubtreeIfNeeded()
        if let element = header(), spoken(element) == "Collapsed" {
            // Still laid out: the fade-out has not finished.
            collapsedWhileOpen = model.phases.last?.isOpen == true
            break
        }
    }
    #expect(collapsedWhileOpen, "Collapsed only after the fade; phases: \(model.phases)")
    try await nativeHostedSettle(host) { model.phases.last == .settled(false) }
    #expect(model.phases.last == .settled(false))
    #expect(header().map(spoken) == "Collapsed")
}

@Test func accordionHeaderSpeaksTheRequestedState() {
    #expect(FestivalAccordionAccessibility.value(isExpanded: true) == "Expanded")
    #expect(FestivalAccordionAccessibility.value(isExpanded: false) == "Collapsed")
    #expect(SettingsChoiceAccessibility.value(selected: "Text", isExpanded: true) == "Text, Expanded")
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

@MainActor
private final class AccordionPressCounter {
    var count = 0
}

/// Click (mouse down and up) at a point of a hosted view.
///
/// - Parameters:
///   - point: Host top-left points.
///   - host: The hosting view.
///   - window: Its window.
@MainActor
private func nativeHostedClick(_ point: CGPoint, in host: NSView, window: NSWindow) {
    let location = host.convert(host.isFlipped ? point : CGPoint(x: point.x, y: host.bounds.height - point.y), to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        if let event = NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ) {
            window.sendEvent(event)
        }
    }
}

private struct DisclosureHarness: View {
    let model: AccordionHarnessModel
    @State private var accordion = FestivalAccordionState<Bool>(expanded: true)
    @State private var sequence: Task<Void, Never>?

    var body: some View {
        Form {
            FestivalDisclosureGroup(state: $accordion) {
                Text("Disclosure Row")
            } label: {
                Text("Disclosure Header")
            }
        }
        .formStyle(.grouped)
        .preferredColorScheme(.dark)
        .onAppear { model.phases.append(accordion.phase) }
        .onChange(of: accordion.phase) { _, phase in model.phases.append(phase) }
        .onChange(of: model.isOn) { _, isOn in
            FestivalAccordionState.move(
                $accordion, to: isOn ? true : nil, reduceMotion: false, sequence: $sequence
            )
        }
    }
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
