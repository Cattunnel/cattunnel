package com.adguard.trusttunnel.vpn_plugin

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The engine's ping record (1.5.9.5, item 13), see [PingRecord]. */
internal class PingRecordTest {
    @Test
    fun readsTheMillisecondsOfAPingRecord() {
        assertEquals(87, PingRecord.parse("""{"cattunnel_ping_ms":87}"""))
        assertEquals(0, PingRecord.parse("""{"cattunnel_ping_ms": 0}"""))
        assertEquals(60000, PingRecord.parse("""{"cattunnel_ping_ms":60000}"""))
    }

    @Test
    fun anythingElseIsNoPing() {
        assertNull(PingRecord.parse("""{"cattunnel_ping_ms":60001}"""))
        assertNull(PingRecord.parse("""{"cattunnel_ping_ms":"87"}"""))
        assertNull(PingRecord.parse("""{"cattunnel_failure":"tls_reset"}"""))
        assertNull(PingRecord.parse("""{"domain":"example.org"}"""))
    }

    @Test
    fun aPingRecordOutOfRangeIsStillNotAQueryLogRow() {
        assertTrue(PingRecord.isPingRecord("""{"cattunnel_ping_ms":60001}"""))
        assertFalse(PingRecord.isPingRecord("""{"cattunnel_failure":"x"}"""))
    }
}
