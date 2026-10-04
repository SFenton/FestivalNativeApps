package com.festivalscoretracker.android.core.format

import org.junit.Assert.assertEquals
import org.junit.Test

/** `StarRatingSpec`: the star-rating control's counts and spoken labels (issue #128). */
class StarRatingSpecTest {
    @Test
    fun whiteCountsDrawThatManyStars() {
        (1..5).forEach { stars ->
            assertEquals(StarRatingSpec.Display(stars, gold = false), StarRatingSpec.display(stars))
        }
        assertEquals("1 star", StarRatingSpec.display(1).label)
        assertEquals("5 stars", StarRatingSpec.display(5).label)
    }

    @Test
    fun sixOrMoreIsFiveGoldStars() {
        assertEquals(StarRatingSpec.Display(5, gold = true), StarRatingSpec.display(6))
        assertEquals(StarRatingSpec.Display(5, gold = true), StarRatingSpec.display(9))
        assertEquals("5 gold stars", StarRatingSpec.display(6).label)
    }

    @Test
    fun belowOneStillDrawsOneWhiteStar() {
        assertEquals(StarRatingSpec.Display(1, gold = false), StarRatingSpec.display(0))
        assertEquals(StarRatingSpec.Display(1, gold = false), StarRatingSpec.display(-2))
        assertEquals("1 star", StarRatingSpec.display(0).label)
    }

    @Test
    fun forcedGoldIgnoresTheCount() {
        assertEquals(StarRatingSpec.Display(5, gold = true), StarRatingSpec.display(3, gold = true))
        assertEquals("1 gold star", StarRatingSpec.Display(1, gold = true).label)
    }
}
