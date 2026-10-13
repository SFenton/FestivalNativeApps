package com.festivalscoretracker.android.presentation

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch

// region Publication reloads

/**
 * Follow generation advances without restarting the route or its view model.
 * The first known generation belongs to the initial load, not a reload.
 *
 * @param scope Owner scope.
 * @param publications Authoritative API publication stream.
 * @param reload Invalidate every started read owned by this consumer.
 * @return Subscription cancelled with the owner.
 */
fun followPublications(scope: CoroutineScope, publications: Flow<Int?>, reload: () -> Unit): Job =
    scope.launch(start = CoroutineStart.UNDISPATCHED) {
        var previous: Int? = null
        publications.filterNotNull().distinctUntilChanged().collect { id ->
            val old = previous
            previous = id
            if (old != null && id > old) reload()
        }
    }

// endregion
