package com.festivalscoretracker.android.notifications

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.notifications.ImprovementNotification
import com.festivalscoretracker.android.core.notifications.NotificationEventPayload
import com.festivalscoretracker.android.core.notifications.NotificationFlagGroup
import com.festivalscoretracker.android.core.notifications.NotificationFlagKind
import com.festivalscoretracker.android.core.notifications.NotificationPayload
import com.festivalscoretracker.android.core.notifications.NotificationPresentation
import com.festivalscoretracker.android.core.notifications.NotificationText
import com.festivalscoretracker.android.core.notifications.NotificationTextEngine
import com.festivalscoretracker.android.core.notifications.NotificationsEnvelope
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.presentation.notifications.NotificationRow
import kotlinx.serialization.encodeToString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The ported web copy engine (issue #180) against the live coalesced feed shapes
 * (`GET /api/player/{id}/notifications`, 2026-10-06) and synthetic edge cases.
 */
class NotificationTextEngineTest {
    private fun decode(items: String): List<ImprovementNotification> =
        FestivalApi.JSON.decodeFromString<NotificationsEnvelope>("""{"items":[$items]}""").items.orEmpty()

    private fun bold(presentation: NotificationPresentation): List<String> = presentation.messageParts.filter { it.emphasis }.map { it.text }

    private fun item(
        kind: String, instrument: String? = "Solo_Guitar", song: String? = "s-x", payload: NotificationPayload? = null,
        newNumeric: Double? = null, oldNumeric: Double? = null, oldRank: Int? = null, newRank: Int? = null,
    ) = ImprovementNotification(
        eventId = 1, notificationGuid = "g", eventKind = kind, songId = song, instrument = instrument,
        oldNumeric = oldNumeric, newNumeric = newNumeric, oldRank = oldRank, newRank = newRank, payload = payload,
    )

    // region Live shapes

    @Test
    fun liveFirstScoreWithFullComboAndGoldStarsListsEveryResult() {
        val row = decode(
            """{"eventId":72844,"notificationGuid":"0628","eventKind":"player_first_score","songId":"f01f","instrument":"Solo_Bass","metric":"score",
            "newNumeric":562148,"newRank":25,"payload":{"newRank":25,"newStars":6,"newFullCombo":true,"oldFullCombo":null,
            "coalescedEvents":[
              {"metric":"score","newRank":25,"oldRank":null,"eventKind":"player_first_score","instrument":"Solo_Bass","newNumeric":562148,"oldNumeric":null},
              {"metric":"full_combo","newRank":null,"oldRank":null,"eventKind":"player_fc_achieved","instrument":"Solo_Bass","newNumeric":null,"oldNumeric":null},
              {"metric":"stars","newRank":null,"oldRank":null,"eventKind":"player_gold_stars_achieved","instrument":"Solo_Bass","newNumeric":6,"oldNumeric":null}],
            "coalescedInstruments":["Solo_Bass"]}}""",
        ).single()
        val p = NotificationText.format(row, "Ego Death")
        assertEquals("Ego Death · Bass", p.title)
        assertEquals("Your first Bass play on Ego Death scored 562,148 points, started at #25, got a Full Combo, and earned gold stars.", p.message)
        assertEquals(listOf(NotificationFlagKind.FirstPlay, NotificationFlagKind.FullCombo, NotificationFlagKind.GoldStars), p.flags)
        assertTrue(p.flagGroups.isEmpty())
        assertEquals(listOf("Bass", "Ego Death", "562,148", "#25", "Full Combo", "gold stars"), bold(p))
        assertEquals(p.message, p.messageParts.joinToString("") { it.text })
        assertEquals("First Play, Full Combo, Gold Stars", p.spokenFlags)
    }

    @Test
    fun liveInstrumentAggregateReadsAsStatements() {
        val row = decode(
            """{"eventId":72856,"notificationGuid":"0899","eventKind":"player_total_score_improved","instrument":"Solo_Bass","metric":"total_score",
            "oldNumeric":93293770,"newNumeric":93855918,"payload":{"coalescedGroup":"instrumentAggregate","coalescedEvents":[
              {"metric":"total_score","newRank":null,"oldRank":null,"eventKind":"player_total_score_improved","newNumeric":93855918,"oldNumeric":93293770},
              {"metric":"total_score_rank","newRank":6,"oldRank":10,"eventKind":"player_total_score_rank_improved","newNumeric":null,"oldNumeric":null},
              {"metric":"weighted_rank","newRank":10,"oldRank":11,"eventKind":"player_weighted_rank_improved","newNumeric":null,"oldNumeric":null},
              {"metric":"full_combo_count","newRank":null,"oldRank":null,"eventKind":"player_fc_count_improved","newNumeric":731,"oldNumeric":730}]}}""",
        ).single()
        val p = NotificationText.format(row, null)
        assertEquals("Bass · Improvements", p.title)
        assertEquals(
            "Your total score increased to 93,855,918 points and your total score rank moved up from #10 to #6.\n\n" +
                "Your Full Combo count increased to 731.\n\n" +
                "Your percentile rank, weighted by number of entries, moved up from #11 to #10.",
            p.message,
        )
        assertEquals(listOf(NotificationFlagKind.Progress, NotificationFlagKind.RankUp), p.flags)
        assertEquals(
            listOf("93,855,918", "total score rank", "#10", "#6", "731", "percentile rank, weighted by number of entries", "#11", "#10"),
            bold(p),
        )
        val spoken = NotificationRow(p, unread = true, timeText = "2 days ago").accessibleText
        assertEquals(
            "Unread. Bass, Improvements. Your total score increased to 93,855,918 points and your total score rank moved up from #10 to #6. " +
                "Your Full Combo count increased to 731. Your percentile rank, weighted by number of entries, moved up from #11 to #10. " +
                "Progress, Rank Up. 2 days ago",
            spoken,
        )
    }

    @Test
    fun liveFullComboCountAndRateRankShareOneStatement() {
        val row = decode(
            """{"eventId":72651,"notificationGuid":"2988","eventKind":"player_total_score_improved","instrument":"Solo_Vocals","metric":"total_score",
            "payload":{"coalescedEvents":[
              {"metric":"total_score","eventKind":"player_total_score_improved","newNumeric":101120591,"oldNumeric":100940998},
              {"metric":"weighted_rank","newRank":31,"oldRank":32,"eventKind":"player_weighted_rank_improved"},
              {"metric":"full_combo_count","eventKind":"player_fc_count_improved","newNumeric":731,"oldNumeric":729},
              {"metric":"fc_rate_rank","newRank":1,"oldRank":3,"eventKind":"player_fc_rate_rank_improved"}]}}""",
        ).single()
        val p = NotificationText.format(row, null)
        assertEquals("Tap Vocals · Improvements", p.title)
        assertEquals(
            "Your total score increased to 101,120,591 points.\n\n" +
                "Your Full Combo count increased to 731 and your Full Combo percentage rank moved up from #3 to #1.\n\n" +
                "Your percentile rank, weighted by number of entries, moved up from #32 to #31.",
            p.message,
        )
    }

    @Test
    fun liveMultipleRankUpdatesUseRankUpdateStatements() {
        val row = decode(
            """{"eventId":73165,"notificationGuid":"b4c0","eventKind":"player_skill_rank_improved","instrument":"Solo_PeripheralVocals",
            "metric":"adjusted_skill_rank","oldRank":44025,"newRank":44021,"payload":{"coalescedGroup":"aggregateRank","coalescedEvents":[
              {"metric":"adjusted_skill_rank","newRank":44021,"oldRank":44025,"eventKind":"player_skill_rank_improved","newNumeric":null,"oldNumeric":null},
              {"metric":"weighted_rank","newRank":42341,"oldRank":42342,"eventKind":"player_weighted_rank_improved","newNumeric":null,"oldNumeric":null}]}}""",
        ).single()
        val p = NotificationText.format(row, null)
        assertEquals("Rank Updates · Karaoke", p.title)
        assertEquals(
            "For Adjusted Percentile Rank, moved from #44,025 to #44,021.\n\nFor Weighted Percentile Rank, moved from #42,342 to #42,341.",
            p.message,
        )
        assertEquals(listOf(NotificationFlagKind.RankUp), p.flags)
        assertEquals(listOf("Adjusted Percentile Rank", "#44,025", "#44,021", "Weighted Percentile Rank", "#42,342", "#42,341"), bold(p))
    }

    @Test
    fun liveSingleRankUsesThePrimarySentence() {
        val row = decode(
            """{"eventId":73127,"notificationGuid":"8b9d","eventKind":"player_weighted_rank_improved","instrument":"Solo_PeripheralGuitar",
            "metric":"weighted_rank","oldRank":373,"newRank":372,"payload":{"coalescedEvents":[
              {"metric":"weighted_rank","newRank":372,"oldRank":373,"eventKind":"player_weighted_rank_improved","newNumeric":null,"oldNumeric":null}]}}""",
        ).single()
        val p = NotificationText.format(row, null)
        assertEquals("Weighted Percentile Rank Improved", p.title)
        assertEquals("You moved up from #373 to #372 in Pro Lead percentile rankings, weighted by number of entries.", p.message)
        assertEquals(listOf("#373", "#372", "Pro Lead"), bold(p))
    }

    // endregion

    // region Derived results, ordering and groups

    @Test
    fun scoreResultsAreDerivedFromThePayloadOrTheEvent() {
        val fromPayload = NotificationText.format(
            item("player_score_pb", newNumeric = 1000.0, payload = NotificationPayload(newFullCombo = true, newStars = 6.0)), "Song",
        )
        assertEquals("You set a new personal best on Lead for Song with 1,000 points, got a Full Combo, and earned gold stars.", fromPayload.message)
        assertEquals(listOf(NotificationFlagKind.NewHighScore, NotificationFlagKind.FullCombo, NotificationFlagKind.GoldStars), fromPayload.flags)

        val fromEvent = NotificationText.format(
            item(
                "player_score_pb",
                payload = NotificationPayload(coalescedEvents = listOf(NotificationEventPayload("player_score_pb", newNumeric = 5.0, newFullCombo = true, newStars = 5.0))),
            ),
            "Song",
        )
        assertEquals("You set a new personal best on Lead for Song with 5 points and got a Full Combo.", fromEvent.message)

        // Non-gold stars and a false Full Combo derive nothing.
        val plain = NotificationText.format(item("player_score_pb", newNumeric = 7.0, payload = NotificationPayload(newFullCombo = false, newStars = 5.0)), "Song")
        assertEquals(listOf(NotificationFlagKind.NewHighScore), plain.flags)

        // A payload state belongs to the row's own score event, not to a second score event on another chart.
        val other = NotificationText.format(
            item(
                "player_score_pb", newNumeric = 1.0,
                payload = NotificationPayload(
                    newFullCombo = true,
                    coalescedEvents = listOf(
                        NotificationEventPayload("player_score_pb", "Solo_Guitar", newNumeric = 1.0),
                        NotificationEventPayload("player_first_score", "Solo_Bass", newNumeric = 2.0),
                    ),
                ),
            ),
            "Song",
        )
        assertEquals(
            listOf(NotificationFlagGroup(Instrument.Lead, "Lead", listOf(NotificationFlagKind.NewHighScore, NotificationFlagKind.FullCombo)), NotificationFlagGroup(Instrument.Bass, "Bass", listOf(NotificationFlagKind.FirstPlay))),
            other.flagGroups,
        )
    }

    @Test
    fun goldStarsReplaceTheStarsImprovedEventAndOrderFollowsPriority() {
        val p = NotificationText.format(
            item(
                "player_stars_improved",
                payload = NotificationPayload(
                    coalescedEvents = listOf(
                        NotificationEventPayload("player_song_rank_improved", oldRank = 9.0, newRank = 4.0),
                        NotificationEventPayload("player_stars_improved", oldNumeric = 5.0, newNumeric = 6.0),
                        NotificationEventPayload("player_gold_stars_achieved", newNumeric = 6.0),
                        NotificationEventPayload("player_difficulty_bumped", oldLabel = " Hard ", newLabel = "Expert"),
                    ),
                ),
            ),
            "Song",
        )
        assertEquals("You earned gold stars on Lead for Song, climbed from #9 to #4, and improved difficulty from Hard to Expert.", p.message)
        assertEquals(listOf(NotificationFlagKind.GoldStars, NotificationFlagKind.RankUp, NotificationFlagKind.DifficultyUp), p.flags)
        assertTrue("Hard" in bold(p) && "Expert" in bold(p) && "gold stars" in bold(p))
    }

    @Test
    fun multiInstrumentSongRowsGroupStatementsAndFlagsPerChart() {
        val p = NotificationText.format(
            item(
                "player_score_pb",
                payload = NotificationPayload(
                    coalescedEvents = listOf(
                        NotificationEventPayload("player_fc_achieved", "Solo_Bass"),
                        NotificationEventPayload("player_stars_improved", "Solo_Guitar", oldNumeric = 4.0, newNumeric = 5.0),
                        NotificationEventPayload("player_score_pb", "Solo_Guitar", newNumeric = 100.0),
                    ),
                ),
            ),
            "Song",
        )
        assertEquals("Song", p.title)
        assertEquals("For Lead, your play set a new personal best with 100 points and improved from 4 to 5 stars.\n\nFor Bass, got a Full Combo.", p.message)
        assertEquals(listOf(NotificationFlagKind.NewHighScore, NotificationFlagKind.FullCombo, NotificationFlagKind.StarsUp), p.flags)
        assertEquals(
            listOf(
                NotificationFlagGroup(Instrument.Lead, "Lead", listOf(NotificationFlagKind.NewHighScore, NotificationFlagKind.StarsUp)),
                NotificationFlagGroup(Instrument.Bass, "Bass", listOf(NotificationFlagKind.FullCombo)),
            ),
            p.flagGroups,
        )
        assertEquals("Lead: New High Score, Stars Up. Bass: Full Combo.", p.spokenFlags)
        assertEquals(listOf("Lead", "100", "4 to 5 stars", "Bass", "Full Combo"), bold(p))
        assertEquals(
            "Song. For Lead, your play set a new personal best with 100 points and improved from 4 to 5 stars. For Bass, got a Full Combo. " +
                "Lead: New High Score, Stars Up. Bass: Full Combo. Just now",
            NotificationRow(p, unread = false, timeText = "Just now").accessibleText,
        )
    }

    // endregion

    // region Aggregate variants and titles

    @Test
    fun aggregateRankOnlyStatementsAndScopelessTitles() {
        val ranks = NotificationText.format(
            item(
                "player_fc_count_improved", song = null, instrument = "Solo_Drums",
                payload = NotificationPayload(
                    coalescedEvents = listOf(
                        NotificationEventPayload("player_max_score_rank_improved", oldRank = 8.0, newRank = 7.0),
                        NotificationEventPayload("player_skill_rank_improved", oldRank = 6.0, newRank = 5.0),
                        NotificationEventPayload("player_total_score_rank_improved", oldRank = 4.0, newRank = 3.0),
                        NotificationEventPayload("player_fc_count_improved", newNumeric = 12.0),
                    ),
                ),
            ),
            null,
        )
        assertEquals("Drums · Improvements", ranks.title)
        assertEquals(
            "Your total score rank moved up from #4 to #3.\n\nYour Full Combo count increased to 12.\n\n" +
                "Your adjusted percentile rank moved up from #6 to #5.\n\nYour max score rank moved up from #8 to #7.",
            ranks.message,
        )

        val fcRank = NotificationText.format(
            item(
                "player_total_score_improved", song = null, instrument = null,
                payload = NotificationPayload(
                    coalescedEvents = listOf(
                        NotificationEventPayload("player_total_score_improved", newNumeric = 10.0),
                        NotificationEventPayload("player_fc_rate_rank_improved", oldRank = 2.0, newRank = 1.0),
                    ),
                ),
            ),
            null,
        )
        assertEquals("Instrument Updates", fcRank.title)
        assertEquals("Your total score increased to 10 points.\n\nYour Full Combo percentage rank moved up from #2 to #1.", fcRank.message)

        val scopeless = NotificationText.format(
            item(
                "player_skill_rank_improved", song = null, instrument = null,
                payload = NotificationPayload(
                    coalescedEvents = listOf(
                        NotificationEventPayload("player_skill_rank_improved"),
                        NotificationEventPayload("player_max_score_rank_improved", oldRank = 3.0, newRank = 2.0),
                    ),
                ),
            ),
            null,
        )
        assertEquals("Rank Updates", scopeless.title)
        assertEquals("For Adjusted Percentile Rank, moved from your new rank to your new rank.\n\nFor Max Score % Rank, moved from #3 to #2.", scopeless.message)
        assertTrue("your new rank" !in bold(scopeless))
    }

    @Test
    fun unknownAndUnresolvedRowsKeepTheirFallbacks() {
        val unknown = NotificationText.format(item("mystery", song = null, instrument = "Solo_Bass"), null)
        // Web: a song-less row titles itself with its chart.
        assertEquals("Bass", unknown.title)
        assertEquals("New improvement detected.", unknown.message)
        assertEquals(listOf(NotificationFlagKind.Improvement), unknown.flags)
        // Never the raw song ID (deliberate deviation from the web's songId fallback title).
        val unresolved = NotificationText.format(item("player_fc_achieved", song = "raw-song-id"), null)
        assertEquals("Notification", unresolved.title)
        assertEquals("You got a Full Combo on Lead for this song.", unresolved.message)
        // Blank coalesced kinds are ignored, so the row itself is the event.
        val blank = NotificationText.format(
            item("player_fc_achieved", payload = NotificationPayload(coalescedEvents = listOf(NotificationEventPayload(" ")))), "Song",
        )
        assertEquals("You got a Full Combo on Lead for Song.", blank.message)
    }

    @Test
    fun emphasisFiltersFallbacksAndPrefersLongerTerms() {
        assertEquals(listOf("abc", "ab"), NotificationTextEngine.filterEmphasis(listOf(" ab ", "abc", "ab", null, "", "this combo", "these rankings")))
        assertEquals(
            listOf("x ", "abc", " ", "ab"),
            NotificationTextEngine.emphasize("x abc ab", listOf("ab", "abc")).map { it.text },
        )
    }

    // endregion

    // region Wire

    @Test
    fun malformedEventFieldsDecodeLeniently() {
        val row = decode(
            """{"notificationGuid":"g","eventKind":"player_score_pb","songId":"s","instrument":"Solo_Guitar",
            "payload":{"newFullCombo":"TRUE","newStars":"6","oldStars":{"x":1},"coalescedEvents":[
              {"eventKind":"player_score_pb","instrument":5,"newNumeric":"1234","oldNumeric":"NaN","newRank":"abc","oldLabel":7,"newFullCombo":"maybe"},
              {"eventKind":12}]}}""",
        ).single()
        val event = row.payload!!.coalescedEvents!!.first()
        assertEquals(1234.0, event.newNumeric)
        assertNull(event.oldNumeric)
        assertNull(event.newRank)
        assertNull(event.instrument)
        assertNull(event.oldLabel)
        assertNull(event.newFullCombo)
        assertNull(row.payload!!.coalescedEvents!![1].eventKind)
        assertEquals(true, row.payload!!.newFullCombo)
        assertEquals(6.0, row.payload!!.newStars)
        assertNull(row.payload!!.oldStars)
        val p = NotificationText.format(row, "Song")
        assertEquals("You set a new personal best on Lead for Song with 1,234 points, got a Full Combo, and earned gold stars.", p.message)
        // Round trip (cached envelopes re-encode).
        val encoded = FestivalApi.JSON.encodeToString(row.payload!!.coalescedEvents!!.first())
        assertEquals(event, FestivalApi.JSON.decodeFromString<NotificationEventPayload>(encoded))
        assertEquals(false, FestivalApi.JSON.decodeFromString<NotificationPayload>("""{"newFullCombo":"false"}""").newFullCombo)
    }

    // endregion
}
