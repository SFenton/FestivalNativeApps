package com.festivalscoretracker.android.core.shell

// region List-detail

/**
 * What a list page reports about its current rows, for auto-selection.
 *
 * @property loaded The list finished loading (successfully or not).
 * @property firstId First row's ID, or null when the list is empty (or still loading).
 */
data class ListHead(val loaded: Boolean = false, val firstId: String? = null)

/** How a list-detail page lays out. */
sealed interface ListDetailLayout {
    /** One full-width list; picking a row pushes the detail (compact windows, or nothing to show). */
    data object SingleList : ListDetailLayout

    /**
     * List and detail side by side.
     *
     * @property detailId Row shown in the detail pane, or null while the list is still loading
     *   (the pane shows the spinner, never a "Select a …" prompt).
     */
    data class Split(val detailId: String?) : ListDetailLayout
}

/**
 * Two **populated** columns whenever the window allows two panes (operator 2026-09-28, same rule
 * as Apple Duo/iPad and Windows): the detail shows the last row the user picked, else the list's
 * first row, so there is never an empty "Select a …" pane. A list that loads with no rows
 * collapses to one full-width list, except across a separating hinge, where content must not
 * straddle the fold and the end pane shows the empty state.
 */
object ListDetailPolicy {
    /**
     * Layout for a list-detail page.
     *
     * @param twoPane The window shows two panes (expanded width or a separating vertical hinge).
     * @param hingeSplit A separating vertical hinge splits the window.
     * @param selectedId Last row the user picked, if any.
     * @param head What the list reports about its rows.
     * @return Layout.
     */
    fun layout(twoPane: Boolean, hingeSplit: Boolean, selectedId: String?, head: ListHead): ListDetailLayout = when {
        !twoPane -> ListDetailLayout.SingleList
        selectedId != null -> ListDetailLayout.Split(selectedId)
        head.firstId != null -> ListDetailLayout.Split(head.firstId)
        !head.loaded -> ListDetailLayout.Split(null)
        hingeSplit -> ListDetailLayout.Split(null)
        else -> ListDetailLayout.SingleList
    }
}

// endregion
