package com.festivalscoretracker.android.presentation.firstrun

import com.festivalscoretracker.android.core.firstrun.FirstRunCatalog
import com.festivalscoretracker.android.core.firstrun.FirstRunGateContext
import com.festivalscoretracker.android.core.firstrun.FirstRunMode
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.firstrun.FirstRunSeenStore
import com.festivalscoretracker.android.core.firstrun.FirstRunSlide
import com.festivalscoretracker.android.core.firstrun.FirstRunSlideEvaluator
import com.festivalscoretracker.android.core.settings.AppSettings
import java.time.Instant
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// region Carousel

/**
 * One carousel presentation.
 *
 * @property id Unique presentation ID (keys the pager state).
 * @property page Page.
 * @property slides Slides in display order (never empty).
 * @property isReplay Settings replay rather than a first visit.
 */
data class FirstRunCarousel(val id: Long, val page: FirstRunPageKey, val slides: List<FirstRunSlide>, val isReplay: Boolean) {
    /**
     * TalkBack position text.
     *
     * @param index Zero-based slide.
     * @return "Slide x of y".
     */
    fun position(index: Int): String = "Slide ${index + 1} of ${slides.size}"
}

// endregion

// region Center

/**
 * App-wide first-run arbiter (Apple/Windows `FirstRunCenter`): evaluates a page's
 * unseen gate-passing slides, owns the single active carousel (web
 * `activeCarouselKey`, so a tab root and a pushed route never both present) and
 * persists seen-state when a carousel closes. One per process.
 *
 * @property store Seen-state persistence.
 * @property mode Launch mode (debug defaults to [FirstRunMode.Off]).
 * @property clock Timestamp source for `seenAt`.
 */
class FirstRunCenter(
    val store: FirstRunSeenStore,
    val mode: FirstRunMode = FirstRunMode.Normal,
    private val clock: () -> Instant = Instant::now,
) {
    private val mutex = Mutex()
    private val ids = AtomicLong()
    private val activeFlow = MutableStateFlow<FirstRunCarousel?>(null)

    private val claimFlow = MutableStateFlow<String?>(null)

    /** The carousel currently shown, if any. */
    val active: StateFlow<FirstRunCarousel?> = activeFlow.asStateFlow()

    /**
     * Another one-at-a-time onboarding modal holding the slot (e.g. What's New), if any
     * (web `activeCarouselKey` shared with the changelog; Apple `FirstRunCenter.claim`).
     */
    val claimed: StateFlow<String?> = claimFlow.asStateFlow()

    /**
     * Gate facts for a page. The web Shop page passes
     * `{hasPlayer: false, shopHighlightEnabled: true}` regardless of settings (`ShopPage.tsx:141`).
     *
     * @param page Page.
     * @param settings Current settings.
     * @return Context.
     */
    fun context(page: FirstRunPageKey, settings: AppSettings): FirstRunGateContext = if (page == FirstRunPageKey.Shop) {
        FirstRunGateContext(hasPlayer = false, shopHighlightEnabled = true, alwaysShow = mode == FirstRunMode.Force)
    } else {
        FirstRunGateContext(
            hasPlayer = settings.selectedPlayer != null,
            shopHighlightEnabled = settings.shopHighlightEnabled,
            experimentalRanksEnabled = settings.experimentalRanks,
            alwaysShow = mode == FirstRunMode.Force,
        )
    }

    /**
     * Slides a page visit would show now (nothing while [FirstRunMode.Off]).
     *
     * @param page Page.
     * @param settings Current settings.
     * @param compact Compact window width.
     * @return Unseen gate-passing slides.
     */
    suspend fun pendingSlides(page: FirstRunPageKey, settings: AppSettings, compact: Boolean): List<FirstRunSlide> =
        if (mode == FirstRunMode.Off) emptyList()
        else FirstRunSlideEvaluator.unseenSlides(FirstRunCatalog.slides(page, compact), context(page, settings), store.load())

    /**
     * Claim the single carousel slot for a page visit.
     *
     * @param page Visible page.
     * @param settings Current settings.
     * @param compact Compact window width.
     * @return The carousel to present, or null when nothing is pending or another carousel is showing.
     */
    suspend fun tryBegin(page: FirstRunPageKey, settings: AppSettings, compact: Boolean): FirstRunCarousel? = mutex.withLock {
        if (activeFlow.value != null || claimFlow.value != null) return null
        val slides = pendingSlides(page, settings, compact)
        if (slides.isEmpty()) return null
        FirstRunCarousel(ids.incrementAndGet(), page, slides, isReplay = false).also { activeFlow.value = it }
    }

    /**
     * Settings "Show": reset the page and show every slide, ignoring gates and
     * seen-state (web `useFirstRunReplay.open` + `getAllSlides`).
     *
     * @param page Page to replay.
     * @param compact Compact window width.
     * @return The replay carousel, or null while another carousel is showing.
     */
    suspend fun beginReplay(page: FirstRunPageKey, compact: Boolean): FirstRunCarousel? = mutex.withLock {
        if (activeFlow.value != null || claimFlow.value != null) return null
        val slides = FirstRunSlideEvaluator.allSlides(FirstRunCatalog.slides(page, compact))
        store.resetPage(slides.map { it.id })
        FirstRunCarousel(ids.incrementAndGet(), page, slides, isReplay = true).also { activeFlow.value = it }
    }

    /**
     * Claim the single onboarding slot for a non-carousel modal (What's New).
     *
     * @param key Claimant key.
     * @return True when claimed (or already held by [key]); false while a carousel or another claimant holds it.
     */
    suspend fun claim(key: String): Boolean = mutex.withLock {
        val holder = claimFlow.value
        if (activeFlow.value != null || (holder != null && holder != key)) return false
        claimFlow.value = key
        true
    }

    /**
     * Free the slot claimed by [key]; a no-op for any other holder.
     *
     * @param key Claimant key.
     */
    suspend fun release(key: String) = mutex.withLock {
        if (claimFlow.value == key) claimFlow.value = null
    }

    /**
     * Close (close button, Skip, Done, back or a tap outside alike): mark only the slides the
     * user actually displayed as seen (operator batch 6.7 — unseen slides show on the next
     * visit) and free the slot. Completing a stale carousel is a no-op.
     *
     * @param carousel Closing carousel.
     * @param viewedCount Slides displayed, counted from the first (the pager only moves one
     *   page at a time, so the seen slides are always a prefix); defaults to all of them.
     */
    suspend fun complete(carousel: FirstRunCarousel, viewedCount: Int = carousel.slides.size) = mutex.withLock {
        if (activeFlow.value?.id != carousel.id) return
        store.markSeen(carousel.slides.take(viewedCount.coerceIn(1, carousel.slides.size)), clock())
        activeFlow.value = null
    }
}

// endregion
