package com.festivalscoretracker.android.data

import java.net.URI

/** Network boundary reserved for a verified public GET wire contract; it performs no requests. */
class TransportPolicy(private val origin: URI, private val fixtureOnly: Boolean) {
    init {
        require(origin.userInfo == null && origin.query == null && origin.fragment == null)
        require(origin.path == "/")
        if (fixtureOnly) {
            require(origin.scheme == "http" && origin.host == "10.0.2.2" && origin.port == 8080) {
                "Debug transport must point to the local fixture server"
            }
        } else {
            require(origin.scheme == "https" && origin.host == "festivalscoretracker.com" && origin.port == -1) {
                "Release transport must use the public HTTPS origin"
            }
        }
    }

    /** The validated origin; no endpoint is fetched until its public wire format is verified. */
    fun origin(): URI = origin
}
