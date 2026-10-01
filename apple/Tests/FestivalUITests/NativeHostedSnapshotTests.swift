#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Harness self-tests

/// A tinted `festivalGlass` card over a flat brand surface, like every page's cards.
private struct TintedGlassProbe: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Harness Probe Title").font(.title.bold())
            Text("Glass card body text")
                .padding(16)
                .festivalGlass(.card, cornerRadius: 22)
        }
        .padding(24)
        .frame(width: 360, height: 240, alignment: .topLeading)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark)
    }
}

/// Whether the test process runs in a virtual machine (`kern.hv_vmm_present`).
///
/// - Returns: `true` on VMs such as GitHub-hosted macOS runners.
private func nativeHostedRunsInVirtualMachine() -> Bool {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0) == 0 && value == 1
}

/// Pins the root cause of blank full-page captures and proves the harness fix.
///
/// Without the fallback, tinted Liquid Glass anywhere in the tree makes the
/// *whole* `cacheDisplay` capture transparent — title, background and all. If
/// this canary starts failing because the unforced capture has content, AppKit
/// fixed the limitation: revisit `NativeHostedRoot` and the hosted-snapshot docs.
@MainActor
@Test func hostedHarnessForcesGlassFallbackBecauseTintedGlassCapturesBlank() async throws {
    let size = CGSize(width: 360, height: 240)
    let real = nativeHostedView(TintedGlassProbe(), size: size, forceGlassFallback: false)
    let realWindow = nativeHostedWindow(real, size: size)
    let realImage = try await nativeHostedSettle(real)
    let forced = nativeHostedView(TintedGlassProbe(), size: size)
    let forcedWindow = nativeHostedWindow(forced, size: size)
    let forcedImage = try await nativeHostedSettle(forced, untilText: ["Harness Probe Title"])
    // Hosted CI runners are VMs whose paravirtual GPU composites tinted glass into the capture, so the
    // limitation only reproduces (and the canary only means something) on physical Macs.
    if #available(macOS 26.0, *), !nativeHostedRunsInVirtualMachine() {
        #expect(
            nativeHostedContent(realImage).nonBackgroundFraction == 0,
            "Tinted Liquid Glass now captures; revisit NativeHostedRoot's forced fallback"
        )
    }
    let content = assertRendersContent(
        forced, image: forcedImage, minimumNonBackgroundFraction: 0.05,
        containing: ["Harness Probe Title", "Glass card body text"]
    )
    #expect(content.background.a == 255)
    withExtendedLifetime((realWindow, forcedWindow)) {}
}

/// A transparent, never-painted capture measures as blank and fails the assertion.
@MainActor
@Test func hostedContentAssertionRejectsBlankAndAcceptsText() async throws {
    let size = CGSize(width: 300, height: 200)
    let blank = nativeHostedView(Color.clear.frame(width: 300, height: 200), size: size)
    let blankImage = try nativeHostedImage(blank)
    #expect(nativeHostedContent(blankImage).nonBackgroundFraction == 0)
    withKnownIssue("A blank capture must fail both coverage checks and the text check") {
        assertRendersContent(blank, image: blankImage, containing: ["Anything"])
    }

    let text = nativeHostedView(
        Text("Visible Evidence").font(.largeTitle).foregroundStyle(.white)
            .frame(width: 300, height: 200).background(Color.black),
        size: size
    )
    let textImage = try await nativeHostedSettle(text, untilText: ["Visible Evidence"])
    let measured = assertRendersContent(
        text, image: textImage, containing: ["Visible Evidence"], notContaining: ["Loading"]
    )
    #expect(measured.inkFraction > 0.01)
}

/// List rows live in nested `NSTableView` cell hosts the root's accessibility
/// children do not reach; the walk must follow AppKit subviews too.
@MainActor
@Test func hostedAccessibilityReadsAppKitListRows() async throws {
    let size = CGSize(width: 320, height: 300)
    let host = nativeHostedView(
        List(["Alpha Row", "Beta Row"], id: \.self) { Text($0) }
            .frame(width: 320, height: 300),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    try await nativeHostedSettle(host, untilText: ["Alpha Row", "Beta Row"])
    #expect(nativeHostedAccessibility(host).contains("Beta Row"))
    withExtendedLifetime(window) {}
}

/// A readiness predicate that never holds is reported rather than silently captured.
@MainActor
@Test func hostedSettleReportsReadinessTimeout() async throws {
    let host = nativeHostedView(
        Text("Static").frame(width: 100, height: 40), size: CGSize(width: 100, height: 40)
    )
    await withKnownIssue("Readiness never holds, so the settle records a timeout") {
        _ = try await nativeHostedSettle(host, timeout: .milliseconds(200)) { false }
    }
}
#endif
