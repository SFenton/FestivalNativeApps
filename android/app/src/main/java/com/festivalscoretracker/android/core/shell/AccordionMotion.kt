package com.festivalscoretracker.android.core.shell

// region Accordion motion

/**
 * One step of an accordion's open or close sequence.
 *
 * @property kind What moves.
 * @property delayMillis Start, from the toggle.
 * @property durationMillis Length.
 */
data class AccordionStep(val kind: Kind, val delayMillis: Int, val durationMillis: Int) {
    /** What an accordion step animates. */
    enum class Kind {
        /** The container's height grows or collapses. */
        Height,

        /** The content's opacity. */
        Fade,
    }

    /** End, from the toggle. */
    val endMillis: Int get() = delayMillis + durationMillis
}

/**
 * Pure timing rules for every accordion-style reveal (`ui/common/AccordionReveal.kt`;
 * `load-transition` R10, owner-approved variant, issue #561): opening grows the container
 * first and then fades the content in; closing fades the content out first and then
 * collapses the container. Under reduced motion it opens and closes at once, with no height
 * motion or fade (R6; the selector panel and Apple SettingsChoiceRow precedent).
 */
object AccordionMotion {
    /** Height step (web `Accordion` `QUICK_FADE_MS`; Material 3 "Short 3 | 150ms | Small transitions"). */
    const val HEIGHT_MS = 150

    /** Content fade step (web `CollapseOnExit` `opacity 150ms`). */
    const val FADE_MS = 150

    /**
     * The opening sequence.
     *
     * @param reduceMotion Remove animations / Reduce Motion.
     * @return Steps in start order: height then fade; none under reduced motion.
     */
    fun opening(reduceMotion: Boolean): List<AccordionStep> =
        if (reduceMotion) {
            emptyList()
        } else {
            listOf(
                AccordionStep(AccordionStep.Kind.Height, 0, HEIGHT_MS),
                AccordionStep(AccordionStep.Kind.Fade, HEIGHT_MS, FADE_MS),
            )
        }

    /**
     * The closing sequence.
     *
     * @param reduceMotion Remove animations / Reduce Motion.
     * @return Steps in start order: fade then height; none under reduced motion.
     */
    fun closing(reduceMotion: Boolean): List<AccordionStep> =
        if (reduceMotion) {
            emptyList()
        } else {
            listOf(
                AccordionStep(AccordionStep.Kind.Fade, 0, FADE_MS),
                AccordionStep(AccordionStep.Kind.Height, FADE_MS, HEIGHT_MS),
            )
        }

    /**
     * Total length of a sequence.
     *
     * @param steps A sequence from [opening] or [closing].
     * @return Milliseconds until the last step ends.
     */
    fun totalMillis(steps: List<AccordionStep>): Int = steps.maxOfOrNull { it.endMillis } ?: 0

    /**
     * The step of [kind] in [steps], if the sequence animates it.
     *
     * @param steps A sequence.
     * @param kind What moves.
     * @return The step, or null when it doesn't move.
     */
    fun step(steps: List<AccordionStep>, kind: AccordionStep.Kind): AccordionStep? = steps.firstOrNull { it.kind == kind }
}

// endregion
