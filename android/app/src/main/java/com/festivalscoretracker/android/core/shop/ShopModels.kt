package com.festivalscoretracker.android.core.shop

import com.festivalscoretracker.android.core.model.FestivalApiException
import java.net.URI
import java.text.Collator
import java.util.Locale
import kotlinx.serialization.Serializable

// region Wire

/**
 * One enriched `/api/shop` offer (Apple `ShopSong`).
 *
 * @property songId Catalogue song ID.
 * @property title Title.
 * @property artist Artist.
 * @property year Release year.
 * @property albumArt Artwork reference (resolved like catalogue art).
 * @property shopUrl Official Fortnite Item Shop URL (validated).
 * @property leavingTomorrow Leaves the Shop tomorrow.
 * @property isNew New in this rotation.
 */
@Serializable
data class ShopSong(
    val songId: String,
    val title: String,
    val artist: String,
    val year: Int? = null,
    val albumArt: String? = null,
    val shopUrl: String,
    val leavingTomorrow: Boolean = false,
    val isNew: Boolean = false,
) {
    /** `artist · year`, omitting a missing year. */
    val subtitle: String get() = if (year != null && year != 0) "$artist · $year" else artist
}

/**
 * Complete, publication-scoped `/api/shop` envelope.
 *
 * @property count Declared offer count.
 * @property songs Offers.
 * @property newSongs IDs flagged new (informational).
 * @property lastUpdated Service timestamp.
 */
@Serializable
data class ShopResponse(
    val count: Int,
    val songs: List<ShopSong>,
    val newSongs: List<String>? = null,
    val lastUpdated: String? = null,
) {
    /**
     * Reject contradictory cardinality, duplicate or path-breaking IDs and untrusted outbound links.
     *
     * @throws FestivalApiException.InvalidResponse when invalid.
     */
    fun validate() {
        val ids = HashSet<String>()
        val valid = count in 0..MAX_OFFERS && count == songs.size && songs.all { song ->
            song.songId.isNotEmpty() && '/' !in song.songId && song.title.isNotEmpty() && song.artist.isNotEmpty() &&
                ids.add(song.songId.lowercase()) && isOfficialShopUrl(song.shopUrl)
        }
        if (!valid) throw FestivalApiException.InvalidResponse()
    }

    /**
     * Title-first deterministic order independent of service iteration.
     *
     * @param collator Locale-aware comparison.
     * @return Offers sorted by title, then song ID.
     */
    fun sortedSongs(collator: Collator = Collator.getInstance(Locale.getDefault())): List<ShopSong> =
        songs.sortedWith { a, b -> collator.compare(a.title, b.title).takeIf { it != 0 } ?: a.songId.compareTo(b.songId) }

    companion object {
        /** Upper bound on offers accepted from the wire. */
        const val MAX_OFFERS = 10_000

        /** Largest accepted `/api/shop` body. */
        const val MAX_BYTES = 4_000_000

        private const val PREFIX = "/item-shop/jam-tracks/"

        /**
         * Whether a URL is an official HTTPS `www.fortnite.com/item-shop/jam-tracks/<slug>` link
         * with no credentials, port, query or fragment.
         *
         * @param raw Wire URL.
         * @return True when safe to open.
         */
        fun isOfficialShopUrl(raw: String?): Boolean {
            if (raw.isNullOrEmpty() || raw.length > 2_000 || '@' in raw) return false
            val uri = runCatching { URI(raw) }.getOrNull() ?: return false
            val path = uri.rawPath ?: return false
            return uri.scheme == "https" && uri.host.equals("www.fortnite.com", ignoreCase = true) &&
                uri.port == -1 && uri.rawUserInfo == null && uri.rawQuery == null && uri.rawFragment == null &&
                path.startsWith(PREFIX) && path.length > PREFIX.length
        }
    }
}

// endregion

// region Presentation policy

/**
 * One real Shop availability accent (never a fallback for missing data).
 *
 * @property label Spoken/visible badge text.
 */
enum class ShopHighlight(val label: String) {
    New("New"),
    LeavingTomorrow("Leaving Tomorrow"),
}

/**
 * The pulsing Shop outline on Songs rows, Song Detail and Shop cards (web
 * `shopHighlight*`, changelog 0.1.133: green in the Shop, gold New, red Leaving
 * Tomorrow, matching the instrument chips' colors).
 */
enum class ShopPulse {
    /** In the Shop, not new and not leaving: green. */
    InShop,

    /** New in this rotation: gold. */
    New,

    /** Leaving tomorrow: red. */
    LeavingTomorrow,
}

/** Effective hide/highlight policy shared by Shop, Songs and Detail (Apple `ShopPresentationPolicy`). */
object ShopPresentationPolicy {
    /**
     * Outline pulse for an offer: Leaving Tomorrow, then New, then In Shop; nothing when
     * hidden, highlighting is off or there is no validated same-publication offer.
     *
     * @param offer Validated same-publication offer.
     * @param hidden Hide Item Shop setting.
     * @param highlightingDisabled Disable Shop highlighting setting.
     * @return The pulse, or null.
     */
    fun pulse(offer: ShopSong?, hidden: Boolean, highlightingDisabled: Boolean): ShopPulse? = when {
        hidden || highlightingDisabled || offer == null -> null
        offer.leavingTomorrow -> ShopPulse.LeavingTomorrow
        offer.isNew -> ShopPulse.New
        else -> ShopPulse.InShop
    }

    /**
     * Leaving Tomorrow, then New; nothing when hidden, highlighting is off or there is no offer.
     *
     * @param offer Validated same-publication offer.
     * @param hidden Hide Item Shop setting.
     * @param highlightingDisabled Disable Shop highlighting setting.
     * @return The accent, or null.
     */
    fun highlight(offer: ShopSong?, hidden: Boolean, highlightingDisabled: Boolean): ShopHighlight? = when {
        hidden || highlightingDisabled || offer == null -> null
        offer.leavingTomorrow -> ShopHighlight.LeavingTomorrow
        offer.isNew -> ShopHighlight.New
        else -> null
    }
}

/**
 * Item Shop page filter (issues #19, #376): three include switches, one per group of
 * offers, that start **on** like the Songs Item Shop and Double Bass switches. **Available**
 * is the offers that are neither New nor Leaving Tomorrow. An offer shows when it is in any
 * group whose switch is on, so turning a switch off hides that group (an offer flagged both
 * New and Leaving Tomorrow hides only when both are off); with every switch off, nothing
 * shows. Uses the wire flags, so it still works while Shop highlighting is off.
 *
 * @property new Show New offers.
 * @property available Show offers that are neither New nor Leaving Tomorrow.
 * @property leavingTomorrow Show offers leaving tomorrow.
 */
data class ShopOfferFilter(val new: Boolean = true, val available: Boolean = true, val leavingTomorrow: Boolean = true) {
    /** Whether any switch is off (gold Filter icon); the default shows every offer. */
    val isActive: Boolean get() = !(new && available && leavingTomorrow)

    /**
     * Spoken state of the Filter button (issue #145), so TalkBack hears what the gold tint
     * shows: "No filters", or "Filters on: hiding " and the switches that are off, in sheet order.
     */
    val stateDescription: String
        get() = if (!isActive) {
            "No filters"
        } else {
            "Filters on: hiding " + listOfNotNull(
                "New".takeUnless { new },
                "Available".takeUnless { available },
                "Leaving Tomorrow".takeUnless { leavingTomorrow },
            ).joinToString(", ")
        }

    /**
     * Whether an offer passes the filter.
     *
     * @param offer Validated offer.
     * @return True when every switch is on or the offer is in a group whose switch is on.
     */
    fun matches(offer: ShopSong): Boolean = !isActive ||
        (new && offer.isNew) ||
        (leavingTomorrow && offer.leavingTomorrow) ||
        (available && !offer.isNew && !offer.leavingTomorrow)

    /**
     * Offers that pass, in their given order.
     *
     * @param offers Offers.
     * @return Matching offers.
     */
    fun apply(offers: List<ShopSong>): List<ShopSong> = if (isActive) offers.filter(::matches) else offers
}

/** One observed publication must own catalogue rows and their related data (Apple `SongRelatedPublicationPolicy`). */
object SongRelatedPublicationPolicy {
    /**
     * True only when catalogue, related data and the session observed the same generation.
     *
     * @param catalogue Generation observed for the catalogue.
     * @param related Generation observed for Shop offers or player scores.
     * @param current Latest generation observed by the app.
     * @return Whether related data may decorate the catalogue rows.
     */
    fun matches(catalogue: Int?, related: Int?, current: Int?): Boolean =
        catalogue != null && related != null && current != null && catalogue == current && related == current
}

/**
 * Validated Shop data plus the generation it was observed in.
 *
 * @property shop Envelope.
 * @property sortedSongs Title-sorted offers.
 * @property publicationId Header-verified publication, or null when headerless.
 * @property observedPublicationId Generation observed by the client.
 */
data class ShopPayload(
    val shop: ShopResponse,
    val sortedSongs: List<ShopSong>,
    val publicationId: Int?,
    val observedPublicationId: Int,
) {
    /** Offers by song ID. */
    val offersById: Map<String, ShopSong> by lazy { shop.songs.associateBy { it.songId } }
}

// endregion
