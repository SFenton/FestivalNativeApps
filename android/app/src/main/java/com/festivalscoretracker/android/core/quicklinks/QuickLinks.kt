package com.festivalscoretracker.android.core.quicklinks

import com.festivalscoretracker.android.core.model.Instrument
import kotlin.math.abs

// region Section model

/**
 * One jump target (web `PageQuickLinkItem`).
 *
 * @property id Web item ID (`app-settings`, `instrument:Solo_Guitar`, …).
 * @property title Visible label.
 * @property icon Material icon token (the UI maps it), or null.
 * @property instrument Chart icon instead of [icon].
 * @property depth Nesting depth (0 = top level).
 * @property spokenTitle TalkBack label when it differs (web `landmarkLabel`).
 */
data class QuickLinkSection(
    val id: String,
    val title: String,
    val icon: String? = null,
    val instrument: Instrument? = null,
    val depth: Int = 0,
    val spokenTitle: String? = null,
) {
    /** TalkBack label. */
    val accessibleTitle: String get() = spokenTitle ?: title

    /** Test tag. */
    val testTag: String get() = "fst.quick-links.item.$id"
}

/**
 * A section's vertical extent relative to the top of the scroll viewport, in pixels.
 *
 * @property minY Top edge.
 * @property maxY Bottom edge (never above [minY]).
 */
data class QuickLinkFrame(val minY: Float, val maxY: Float) {
    init {
        require(maxY >= minY) { "maxY < minY" }
    }
}

// endregion

// region Pure rules

/** Quick Links rules (Apple `QuickLinks`, Windows `QuickLinks`; spec "Active-section tracking"). */
object QuickLinks {
    /** Fewest sections that make a jump list useful (native rule: ≥ 2). */
    const val MINIMUM_SECTION_COUNT = 2

    /** Window width (dp) below which the entry opens a bottom sheet rather than a menu (M3 compact). */
    const val SHEET_MAXIMUM_WINDOW_WIDTH_DP = 600

    /**
     * Whether a page shows Quick Links at all.
     *
     * @param sectionCount Sections.
     * @return True for two or more.
     */
    fun isAvailable(sectionCount: Int): Boolean = sectionCount >= MINIMUM_SECTION_COUNT

    /**
     * Whether the entry opens a bottom sheet (compact window) or a menu.
     *
     * @param windowWidthDp Window width.
     * @return True below [SHEET_MAXIMUM_WINDOW_WIDTH_DP].
     */
    fun usesSheet(windowWidthDp: Int): Boolean = windowWidthDp < SHEET_MAXIMUM_WINDOW_WIDTH_DP

    /**
     * Where a separating vertical hinge splits a page (book posture): the page
     * becomes list | hinge | supporting pane, so no row straddles the fold.
     *
     * @param pageLeft Page left edge in window pixels.
     * @param pageWidth Page width in pixels.
     * @param hingeLeft Hinge left edge in window pixels.
     * @param hingeRight Hinge right edge in window pixels.
     * @return (start pane width, hinge width) in pixels, or null when the hinge is outside the page.
     */
    fun hingeSplit(pageLeft: Float, pageWidth: Float, hingeLeft: Float, hingeRight: Float): Pair<Float, Float>? {
        val start = hingeLeft - pageLeft
        val end = hingeRight - pageLeft
        if (start <= 0f || end >= pageWidth || end < start) return null
        return start to (end - start)
    }

    /**
     * Remove duplicate IDs, keeping first occurrences in order.
     *
     * @param sections Candidate sections.
     * @return Ordered unique sections.
     */
    fun ordered(sections: List<QuickLinkSection>): List<QuickLinkSection> = sections.distinctBy { it.id }

    /**
     * Whether any part of a frame is inside the viewport.
     *
     * @param frame Frame, or null when unknown.
     * @param viewportHeight Viewport height.
     * @return Visibility.
     */
    fun isVisible(frame: QuickLinkFrame?, viewportHeight: Float): Boolean =
        frame != null && frame.maxY > 0 && frame.minY < viewportHeight

    /**
     * Whether a frame's top sits in the band a jump can land in.
     *
     * @param frame Frame.
     * @param activationOffset Activation line.
     * @param band Reachable band either side (web ±96 px).
     * @return True inside `[-band, offset + band]`.
     */
    fun isReachable(frame: QuickLinkFrame, activationOffset: Float, band: Float): Boolean =
        frame.minY >= -band && frame.minY <= activationOffset + band

    /**
     * The natural active section: the last one (in list order) whose top is at
     * or above the activation line; sections with unknown frames are skipped;
     * with none past the line, the first section.
     *
     * @param sections Ordered sections.
     * @param frames Known frames.
     * @param activationOffset Activation line.
     * @return Active ID, or null without sections.
     */
    fun naturalActive(sections: List<QuickLinkSection>, frames: Map<String, QuickLinkFrame>, activationOffset: Float): String? {
        if (sections.isEmpty()) return null
        var active = sections.first().id
        val threshold = activationOffset + 1
        for (section in sections) {
            val frame = frames[section.id] ?: continue
            if (frame.minY > threshold) break
            active = section.id
        }
        return active
    }
}

// endregion

// region Tracker

/** Jump phases. */
enum class QuickLinkPhase {
    /** Natural tracking. */
    Idle,

    /** A jump's scroll is running; its target is active. */
    Scrolling,

    /** The jump landed; the target stays active while it plausibly owns the viewport. */
    Owned,
}

/**
 * Active-section state machine with jump ownership (spec steps 1–4; Apple
 * `QuickLinkTracker`). Pure: callers feed frames after layout changes only.
 *
 * @property activationOffset Activation line in pixels.
 * @property band Reachable band in pixels.
 * @property completeThreshold Landing tolerance in pixels.
 */
class QuickLinkTracker(
    private val activationOffset: Float = 16f,
    private val band: Float = 96f,
    private val completeThreshold: Float = 8f,
) {
    /** Current phase. */
    var phase: QuickLinkPhase = QuickLinkPhase.Idle
        private set

    /** Jump target. */
    var target: String? = null
        private set

    /** Active section. */
    var activeId: String? = null
        private set

    private var anchorMinY = 0f
    private var lockWhileVisible = false

    /**
     * Start a jump: the target is active immediately.
     *
     * @param id Target section.
     */
    fun beginJump(id: String) {
        phase = QuickLinkPhase.Scrolling
        target = id
        activeId = id
    }

    /**
     * The jump's scroll finished: take ownership, or release when the target is gone.
     * A target that could not reach the top (near the end of content) stays active while visible.
     *
     * @param sections Ordered sections.
     * @param frames Known frames.
     * @param viewportHeight Viewport height.
     */
    fun settle(sections: List<QuickLinkSection>, frames: Map<String, QuickLinkFrame>, viewportHeight: Float) {
        val id = target
        if (phase != QuickLinkPhase.Scrolling || id == null) return
        val frame = frames[id]
        if (sections.none { it.id == id } || frame == null || !QuickLinks.isVisible(frame, viewportHeight)) {
            release(QuickLinks.naturalActive(sections, frames, activationOffset))
            return
        }
        phase = QuickLinkPhase.Owned
        anchorMinY = frame.minY
        lockWhileVisible = frame.minY > activationOffset + completeThreshold
        activeId = id
    }

    /**
     * Layout changed (scroll, resize, content change).
     *
     * @param sections Ordered sections.
     * @param frames Known frames.
     * @param viewportHeight Viewport height.
     */
    fun update(sections: List<QuickLinkSection>, frames: Map<String, QuickLinkFrame>, viewportHeight: Float) {
        val natural = QuickLinks.naturalActive(sections, frames, activationOffset)
        val id = target
        when (phase) {
            QuickLinkPhase.Scrolling -> if (sections.any { it.id == id }) activeId = id else release(natural)
            QuickLinkPhase.Owned -> {
                val frame = id?.let(frames::get)
                if (sections.none { it.id == id } || frame == null) {
                    release(natural)
                    return
                }
                val visible = QuickLinks.isVisible(frame, viewportHeight)
                val holds = if (lockWhileVisible) {
                    visible
                } else {
                    (visible && abs(frame.minY - anchorMinY) <= completeThreshold) || QuickLinks.isReachable(frame, activationOffset, band)
                }
                if (holds) activeId = id else release(natural)
            }
            QuickLinkPhase.Idle -> activeId = natural
        }
    }

    private fun release(natural: String?) {
        phase = QuickLinkPhase.Idle
        target = null
        activeId = natural
    }
}

// endregion
