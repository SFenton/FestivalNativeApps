import CoreGraphics
import Foundation
import QuartzCore
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Helpers

/// A slot moving through `preset` since `start`.
private func movingLayer(
    _ preset: ArtworkMotionPreset, start: Date, fadeStart: Date? = nil
) -> ArtworkBackdropState.Layer {
    ArtworkBackdropState.Layer(
        id: 0, visible: true, moving: true, motion: preset,
        fadeStart: fadeStart, motionStart: start
    )
}

// MARK: - Pose

/// The Core Animation transform (about the layer's center) moves every point exactly where
/// the SwiftUI `CarouselMotionEffect` puts it, so both platforms draw the same frame.
@Test func carouselSlotPoseMatchesTheSwiftUIMotionEffect() {
    let size = CGSize(width: 402, height: 874)
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    for preset in ArtworkMotionPreset.all {
        for fraction in [0, 0.37, 1] {
            let effect: ProjectionTransform = CarouselMotionEffect(
                fraction: fraction, motion: preset
            ).effectValue(size: size)
            let pose: CATransform3D = CarouselSlotPose(preset, at: fraction).transform
            for point in [CGPoint.zero, CGPoint(x: 100, y: 700), CGPoint(x: 402, y: 874)] {
                let ex: CGFloat = effect.m11 * point.x + effect.m21 * point.y + effect.m31
                let ey: CGFloat = effect.m12 * point.x + effect.m22 * point.y + effect.m32
                let swiftUI = CGPoint(x: ex, y: ey)
                let lx: CGFloat = point.x - center.x
                let ly: CGFloat = point.y - center.y
                let cx: CGFloat = center.x + pose.m11 * lx + pose.m21 * ly + pose.m41
                let cy: CGFloat = center.y + pose.m12 * lx + pose.m22 * ly + pose.m42
                let coreAnimation = CGPoint(x: cx, y: cy)
                #expect(abs(swiftUI.x - coreAnimation.x) < 0.001)
                #expect(abs(swiftUI.y - coreAnimation.y) < 0.001)
            }
        }
    }
}

// MARK: - Plan

/// Mid-motion, the slot joins the shared six-second journey where the clock says it is.
@Test func carouselSlotPlanJoinsARunningMotionInStep() {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)
    let preset = ArtworkMotionPreset.all[2]
    let plan = CarouselSlotPlan(
        layer: movingLayer(preset, start: now.addingTimeInterval(-3)),
        isActive: false, animate: true, now: now
    )
    #expect(plan.pose == CarouselSlotPose(preset, at: 0.5))
    #expect(plan.motion == CarouselSlotPlan.Motion(
        preset: preset, from: CarouselSlotPose(preset, at: 0), to: CarouselSlotPose(preset, at: 1),
        duration: 6, elapsed: 3
    ))
    #expect(plan.opacity == 1 && plan.fade == nil)
    #expect(plan.isAnimating)
}

/// A motion starting later keeps its start pose until then (negative elapsed time).
@Test func carouselSlotPlanHoldsAFutureMotionAtItsStart() {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)
    let preset = ArtworkMotionPreset.all[0]
    let plan = CarouselSlotPlan(
        layer: movingLayer(preset, start: now.addingTimeInterval(0.5)),
        isActive: false, animate: true, now: now
    )
    #expect(plan.pose == CarouselSlotPose(preset, at: 0))
    #expect(plan.motion?.elapsed == -0.5)
}

/// Paused, finished, or off-screen slots are still images at the clock's current pose.
@Test func carouselSlotPlanIsStillWhenPausedFinishedOrOffScreen() {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)
    let preset = ArtworkMotionPreset.all[4]
    let paused = ArtworkBackdropState.Layer(
        id: 1, visible: true, moving: false, motion: preset, motionFraction: 0.4
    )
    let pausedPlan = CarouselSlotPlan(layer: paused, isActive: true, animate: true, now: now)
    #expect(pausedPlan.pose == CarouselSlotPose(preset, at: 0.4))
    #expect(!pausedPlan.isAnimating && pausedPlan.opacity == 1)

    let finished = CarouselSlotPlan(
        layer: movingLayer(preset, start: now.addingTimeInterval(-7)),
        isActive: false, animate: true, now: now
    )
    #expect(finished.pose == CarouselSlotPose(preset, at: 1))
    #expect(!finished.isAnimating)

    let offScreen = CarouselSlotPlan(
        layer: movingLayer(
            preset, start: now.addingTimeInterval(-1.5), fadeStart: now.addingTimeInterval(-0.5)
        ),
        isActive: true, animate: false, now: now
    )
    #expect(offScreen.pose == CarouselSlotPose(preset, at: 0.25))
    #expect(offScreen.opacity == BackdropEasing.inOut(0.5))
    #expect(!offScreen.isAnimating)
}

/// Only the top slot fades in, from wherever the shared one-second fade has reached.
@Test func carouselSlotPlanFadesOnlyTheActiveSlot() {
    let now = Date(timeIntervalSinceReferenceDate: 1_000)
    let preset = ArtworkMotionPreset.all[1]
    let layer = movingLayer(
        preset, start: now.addingTimeInterval(-0.25), fadeStart: now.addingTimeInterval(-0.25)
    )
    let top = CarouselSlotPlan(layer: layer, isActive: true, animate: true, now: now)
    #expect(top.fade == CarouselSlotPlan.Fade(duration: 1, elapsed: 0.25))
    #expect(top.opacity == BackdropEasing.inOut(0.25))

    let below = CarouselSlotPlan(layer: layer, isActive: false, animate: true, now: now)
    #expect(below.fade == nil && below.opacity == 1)

    let faded = movingLayer(
        preset, start: now.addingTimeInterval(-2), fadeStart: now.addingTimeInterval(-2)
    )
    let done = CarouselSlotPlan(layer: faded, isActive: true, animate: true, now: now)
    #expect(done.fade == nil && done.opacity == 1)
}

// MARK: - Keyframes

/// Keyframes are sampled at the 30 fps cap, end exactly on the journey's endpoints and
/// follow the backdrop's easing.
@Test func carouselSlotKeyframesSampleAtTheFrameRateCap() {
    #expect(CarouselSlotPlan.preferredFramesPerSecond == 30)
    let fractions = CarouselSlotPlan.keyframeFractions(duration: 6)
    #expect(fractions.count == 181)
    #expect(fractions.first == 0 && fractions.last == 1)
    #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 < $1 })
    #expect(CarouselSlotPlan.keyframeFractions(duration: 0).count == 2)

    let fade = CarouselSlotPlan.fadeKeyframes(duration: 1)
    #expect(fade.count == 31)
    #expect(fade.first == 0 && fade.last == 1)
    #expect(fade[15] == BackdropEasing.inOut(0.5))

    let preset = ArtworkMotionPreset.all[6]
    let poses = CarouselSlotPlan.motionKeyframes(preset, duration: 6)
    #expect(poses.first == CarouselSlotPose(preset, at: 0))
    #expect(poses.last == CarouselSlotPose(preset, at: 1))
    #expect(poses[90] == CarouselSlotPose(preset, at: 0.5))
}

/// Re-planning (which restarts Core Animation) happens only when slot timing changes.
@Test func carouselSlotKeyChangesOnlyWithTiming() throws {
    let image = try #require(CGContext(
        data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )?.makeImage())
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    let layer = movingLayer(ArtworkMotionPreset.all[0], start: start)
    let key = CarouselSlotKey(image: image, layer: layer, isActive: true, animate: true)
    #expect(key == CarouselSlotKey(image: image, layer: layer, isActive: true, animate: true))
    #expect(key != CarouselSlotKey(image: image, layer: layer, isActive: true, animate: false))
    #expect(key != CarouselSlotKey(image: image, layer: layer, isActive: false, animate: true))
    var paused = layer
    paused.moving = false
    paused.motionFraction = 0.5
    #expect(key != CarouselSlotKey(image: image, layer: paused, isActive: true, animate: true))
}

// MARK: - Sheet coverage and first-run pulses

/// The backdrop pauses while any sheet is up and never under-counts on extra dismissals.
@MainActor
@Test func sheetCoverageCountsNestedSheets() {
    let coverage = FestivalSheetCoverage()
    #expect(!coverage.isCovered)
    coverage.begin()
    coverage.begin()
    coverage.end()
    #expect(coverage.isCovered)
    coverage.end()
    coverage.end()
    #expect(!coverage.isCovered && coverage.count == 0)
}

/// First-run glow pulses loop only on the visible slide with motion allowed.
@Test func firstRunPulseRunsOnlyOnTheVisibleSlide() {
    #expect(FirstRunPulsePolicy.runs(slideActive: true, reduceMotion: false, stillBackground: false))
    #expect(!FirstRunPulsePolicy.runs(slideActive: false, reduceMotion: false, stillBackground: false))
    #expect(!FirstRunPulsePolicy.runs(slideActive: true, reduceMotion: true, stillBackground: false))
    #expect(!FirstRunPulsePolicy.runs(slideActive: true, reduceMotion: false, stillBackground: true))
}
