package com.adguard.trusttunnel.vpn_plugin

/**
 * The engine's ping of the endpoint it picked (item 13, 1.5.9.5): after the
 * endpoint is chosen it sends {"cattunnel_ping_ms":N} through onConnectionInfo,
 * next to the failure and diagnostic records. No probe of its own: the value is
 * what the engine measured while choosing.
 */
internal object PingRecord {
    /** Above this the number is not a ping (the engine gives up much earlier). */
    const val MAX_MS = 60_000

    private val RECORD = Regex("""\{\s*"cattunnel_ping_ms"\s*:\s*(\d{1,6})\s*\}""")

    /** The milliseconds of a ping record, or null for any other record. */
    fun parse(info: String): Int? =
        RECORD.matchEntire(info)?.groupValues?.get(1)?.toIntOrNull()?.takeIf { it <= MAX_MS }

    /** A record of the ping kind, even with a number out of range: not a query log row. */
    fun isPingRecord(info: String): Boolean = info.contains("\"cattunnel_ping_ms\"")
}
