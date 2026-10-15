import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Feedback sending status (issue #634)

/// The feedback form's sending status: the copy for each stage and kind, which stage each
/// form phase shows, and the fades between the form, the status and its stages.
@Suite struct FeedbackSendingChoreographyTests {
    typealias Choreography = FeedbackSendingChoreography
    typealias Presentation = FeedbackSendingChoreography.Presentation

    // MARK: - Copy

    /// The owner's titles and subtitle.
    @Test func copyFollowsTheOwnersWording() {
        #expect(FeedbackSendingStage.uploading.title(for: .bug) == "Uploading Media")
        #expect(FeedbackSendingStage.uploading.title(for: .feature) == "Uploading Media")
        #expect(FeedbackSendingStage.uploading.subtitle(for: .bug) == nil)
        #expect(FeedbackSendingStage.filing.title(for: .bug) == "Filing Issue")
        #expect(FeedbackSendingStage.filing.title(for: .feature) == "Filing Request")
        #expect(FeedbackSendingStage.filing.subtitle(for: .bug)
                == "We\u{2019}re filing your issue. Please wait while we upload it.")
        #expect(FeedbackSendingStage.filing.subtitle(for: .feature)
                == "We\u{2019}re filing your request. Please wait while we upload it.")
        #expect(FeedbackSendingStage.busyLabel(for: .bug) == "Sending your issue")
        #expect(FeedbackSendingStage.busyLabel(for: .feature) == "Sending your request")
    }

    // MARK: - Targets

    /// Editing and a failure show the form; uploading and filing show their stage; a report
    /// without media reads as filing from Submit (R16, as on Android and Windows); a filed
    /// report holds whatever shows while the sheet closes (#565).
    @Test func phasesMapToTargets() {
        typealias Stage = FeedbackSendingStage
        #expect(Stage.target(for: .editing, hasMedia: true) == .form)
        #expect(Stage.target(for: .failed("x"), hasMedia: true) == .form)
        #expect(Stage.target(for: .submitting(0.4), hasMedia: true) == .status(.uploading))
        #expect(Stage.target(for: .submitting(0), hasMedia: false) == .status(.filing))
        #expect(Stage.target(for: .submitting(0.9), hasMedia: false) == .status(.filing))
        #expect(Stage.target(for: .filing, hasMedia: false) == .status(.filing))
        #expect(Stage.target(for: .filing, hasMedia: true) == .status(.filing))
        #expect(Stage.target(for: .finished(.received), hasMedia: false) == nil)
        #expect(Stage.target(for: .finished(.filed(issueNumber: 1, skipped: 0)), hasMedia: true) == nil)
    }

    // MARK: - Plans

    /// Submit: the form fades out over 300 ms with the stage mounted transparent, then the
    /// status fades in over 150 ms and its title is announced.
    @Test func submitFadesTheFormOutThenTheStatusIn() {
        let uploading = FeedbackSendingStage.uploading
        let steps = Choreography.plan(from: .editing, to: .status(uploading), reduceMotion: false)
        #expect(steps == [
            .init(delay: 0, fade: 0.3, presentation: Presentation(
                showsForm: false, showsStatus: false, stage: uploading, showsText: true
            ), announces: false),
            .init(delay: 0.3, fade: 0.15, presentation: .status(uploading), announces: true),
        ])
    }

    /// Upload to filing: only the text fades out and the new text in (150 ms each); the
    /// status, and so the spinner, stays opaque throughout.
    @Test func stageChangeSwapsOnlyTheText() {
        let uploading = FeedbackSendingStage.uploading
        let steps = Choreography.plan(from: .status(uploading), to: .status(.filing), reduceMotion: false)
        #expect(steps == [
            .init(delay: 0, fade: 0.15, presentation: Presentation(
                showsForm: false, showsStatus: true, stage: uploading, showsText: false
            ), announces: false),
            .init(delay: 0.15, fade: 0.15, presentation: .status(.filing), announces: true),
        ])
        #expect(steps.allSatisfy { $0.presentation.showsStatus && !$0.presentation.showsForm })
    }

    /// Stop Sending or a failure: the status fades out, then the form back in, unmounting
    /// the status.
    @Test func returningFadesTheStatusOutThenTheFormIn() {
        let steps = Choreography.plan(from: .status(.filing), to: .form, reduceMotion: false)
        #expect(steps == [
            .init(delay: 0, fade: 0.15, presentation: Presentation(
                showsForm: false, showsStatus: false, stage: .filing, showsText: true
            ), announces: false),
            .init(delay: 0.15, fade: 0.3, presentation: .editing, announces: false),
        ])
    }

    /// Already there: nothing to do.
    @Test func settledTargetsPlanNothing() {
        #expect(Choreography.plan(from: .editing, to: .form, reduceMotion: false).isEmpty)
        #expect(Choreography.plan(from: .status(.filing), to: .status(.filing), reduceMotion: false).isEmpty)
        #expect(Choreography.plan(from: .status(.filing), to: .status(.filing), reduceMotion: true).isEmpty)
    }

    /// Reduce Motion: one immediate step to the end state, still announcing a new stage.
    @Test func reduceMotionSwapsAtOnce() {
        let uploading = FeedbackSendingStage.uploading
        #expect(Choreography.plan(from: .editing, to: .status(uploading), reduceMotion: true)
                == [.init(delay: 0, fade: nil, presentation: .status(uploading), announces: true)])
        #expect(Choreography.plan(from: .status(uploading), to: .status(.filing), reduceMotion: true)
                == [.init(delay: 0, fade: nil, presentation: .status(.filing), announces: true)])
        #expect(Choreography.plan(from: .status(.filing), to: .form, reduceMotion: true)
                == [.init(delay: 0, fade: nil, presentation: .editing, announces: false)])
        #expect(Choreography.animation(nil) == nil)
    }

    /// A new target mid-sequence replans from where the fades are: filing arriving while the
    /// form is still fading out goes straight to the filing status, and Stop Sending while
    /// the text is swapping brings the form back.
    @Test func interruptionsReplanFromTheCurrentPresentation() {
        let uploading = FeedbackSendingStage.uploading
        let formFading = Presentation(showsForm: false, showsStatus: false, stage: uploading, showsText: true)
        #expect(Choreography.plan(from: formFading, to: .status(.filing), reduceMotion: false)
                == [.init(delay: 0, fade: 0.15, presentation: .status(.filing), announces: true)])
        #expect(Choreography.plan(from: formFading, to: .form, reduceMotion: false)
                == [.init(delay: 0, fade: 0.3, presentation: .editing, announces: false)])

        let textHidden = Presentation(showsForm: false, showsStatus: true, stage: uploading, showsText: false)
        #expect(Choreography.plan(from: textHidden, to: .status(.filing), reduceMotion: false)
                == [.init(delay: 0, fade: 0.15, presentation: .status(.filing), announces: true)])
        let back = Choreography.plan(from: textHidden, to: .form, reduceMotion: false)
        #expect(back.map(\.presentation.showsStatus) == [false, false])
        #expect(back.last?.presentation == .editing)
    }

    /// The form stays mounted while it shows or fades either way, and leaves only while the
    /// opaque status covers it, so iOS assistive technology can't reach its rows.
    @Test func formLeavesOnlyUnderTheOpaqueStatus() {
        let uploading = FeedbackSendingStage.uploading
        #expect(Presentation.editing.mountsForm)
        #expect(Presentation(showsForm: false, showsStatus: false, stage: uploading, showsText: true).mountsForm)
        #expect(!Presentation.status(uploading).mountsForm)
        #expect(!Presentation(showsForm: false, showsStatus: true, stage: uploading, showsText: false).mountsForm)
        let back = Choreography.plan(from: .status(.filing), to: .form, reduceMotion: false)
        #expect(back.allSatisfy { $0.presentation.mountsForm })
    }

    /// The fades share the load-transition and accordion timings.
    @Test func timingsMatchTheSharedPatterns() {
        #expect(Choreography.contentOutDuration == 0.3)
        #expect(Choreography.statusInDuration == 0.15)
        #expect(Choreography.textFadeDuration == AccordionChoreography.fadeDuration)
        #expect(Choreography.statusOutDuration == 0.15)
        #expect(Choreography.contentInDuration == 0.3)
    }
}
