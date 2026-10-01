package dev.hydrocap.app.notify

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BatteryAlertPolicyTest {

    @Test
    fun `fires once per threshold crossing`() {
        val policy = BatteryAlertPolicy(setOf(10, 5))
        assertEquals(emptyList<Int>(), policy.onLevel(50))
        assertEquals(listOf(10), policy.onLevel(10))
        assertEquals(emptyList<Int>(), policy.onLevel(9))
        assertEquals(emptyList<Int>(), policy.onLevel(7))
        assertEquals(listOf(5), policy.onLevel(5))
        assertEquals(emptyList<Int>(), policy.onLevel(3))
    }

    @Test
    fun `a direct drop below both thresholds fires both`() {
        val policy = BatteryAlertPolicy(setOf(10, 5))
        assertEquals(listOf(10, 5), policy.onLevel(4))
    }

    @Test
    fun `re-arms only after rising above threshold plus margin`() {
        val policy = BatteryAlertPolicy(setOf(10, 5))
        policy.onLevel(9)
        assertEquals(emptyList<Int>(), policy.onLevel(14)) // 10 + 5 = 15 not exceeded
        assertEquals(emptyList<Int>(), policy.onLevel(15)) // must be strictly above
        assertEquals(emptyList<Int>(), policy.onLevel(16)) // re-armed, nothing to notify yet
        assertEquals(listOf(10), policy.onLevel(10)) // fires again
    }

    @Test
    fun `state round-trips through persistence`() {
        val first = BatteryAlertPolicy(setOf(10, 5))
        first.onLevel(8)
        val restored = BatteryAlertPolicy(setOf(10, 5), firedThresholds = first.firedThresholds)
        assertEquals(emptyList<Int>(), restored.onLevel(7))
        assertEquals(listOf(5), restored.onLevel(5))
        assertTrue(restored.firedThresholds.containsAll(listOf(10, 5)))
    }

    @Test
    fun `custom thresholds and invalid values`() {
        val policy = BatteryAlertPolicy(setOf(20, 15, 150, -1))
        assertEquals(listOf(20, 15), policy.thresholds)
        assertEquals(listOf(20), policy.onLevel(18))
    }
}
