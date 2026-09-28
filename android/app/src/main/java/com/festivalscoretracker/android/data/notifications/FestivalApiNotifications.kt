package com.festivalscoretracker.android.data.notifications

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.notifications.NotificationsEnvelope
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ServiceEndpoint

// region Notifications read

/** Default notification page size (the service clamps to 1–200). */
const val DEFAULT_NOTIFICATION_LIMIT = 50

/** Largest notification page size. */
const val MAX_NOTIFICATION_LIMIT = 200

/**
 * The selected player's improvement feed: `GET /api/player/{accountId}/notifications?limit=`.
 *
 * A pure, keyless, publication-classified read — one `SELECT` over
 * `player_improvement_events` for this account `UNION ALL service_notifications`
 * (`FSTService/Api/ImprovementNotificationEndpoints.cs:10-31`,
 * `ImprovementNotificationService.GetPlayerNotifications`), verified by the
 * iPhone and Windows lanes. An unknown account gets an empty envelope, not a 404.
 * Never sends selected-profile headers (the gate rejects them).
 *
 * @param accountId Validated account.
 * @param limit Rows, 1–200.
 * @return Validated envelope.
 * @throws FestivalApiException for invalid parameters, transport or wire failures.
 */
suspend fun FestivalApi.playerNotifications(accountId: String, limit: Int = DEFAULT_NOTIFICATION_LIMIT): NotificationsEnvelope {
    if (!ProfileSearchText.isValidAccountId(accountId) || limit !in 1..MAX_NOTIFICATION_LIMIT) throw FestivalApiException.InvalidResource()
    val endpoint = ServiceEndpoint.Feature(listOf("player", accountId, "notifications"), listOf("limit" to limit.toString()))
    val envelope = decode(NotificationsEnvelope.serializer(), readPinned(endpoint).first)
    envelope.validate(limit)
    return envelope
}

// endregion
