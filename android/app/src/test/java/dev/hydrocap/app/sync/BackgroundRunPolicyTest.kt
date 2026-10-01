package dev.hydrocap.app.sync

import dev.hydrocap.app.sync.BackgroundRunPolicy.Outcome
import dev.hydrocap.app.sync.BackgroundRunPolicy.SkipReason
import dev.hydrocap.app.sync.BackgroundRunPolicy.Verdict
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BackgroundRunPolicyTest {

    @Test
    fun `runs only when paired, enabled and permitted`() {
        assertNull(BackgroundRunPolicy.skipReason(hasPairedDevice = true, backgroundSyncEnabled = true, hasBlePermissions = true))
        assertEquals(SkipReason.NOT_PAIRED, BackgroundRunPolicy.skipReason(false, true, true))
        assertEquals(SkipReason.DISABLED, BackgroundRunPolicy.skipReason(true, false, true))
        assertEquals(SkipReason.PERMISSIONS_MISSING, BackgroundRunPolicy.skipReason(true, true, false))
        // Not paired wins over everything else: nothing to sync at all.
        assertEquals(SkipReason.NOT_PAIRED, BackgroundRunPolicy.skipReason(false, false, false))
    }

    @Test
    fun `exceptions are classified by type`() {
        assertEquals(Outcome.Busy, BackgroundRunPolicy.classify(CapBusyException()))
        assertEquals(Outcome.CapNotFound, BackgroundRunPolicy.classify(CapNotFoundException("cap 'LARQ_x' not found within 30 s")))
        assertEquals(Outcome.Failed("GATT 133"), BackgroundRunPolicy.classify(SyncException("GATT 133")))
        assertEquals(Outcome.Failed("IllegalStateException"), BackgroundRunPolicy.classify(IllegalStateException()))
    }

    @Test
    fun `a successful sync resets the miss streak`() {
        val eval = BackgroundRunPolicy.evaluate(Outcome.Synced(3, 10, 42), previousMisses = 2)
        assertEquals(Verdict.SUCCESS, eval.verdict)
        assertEquals(0, eval.consecutiveMisses)
        assertFalse(eval.quiet)
    }

    @Test
    fun `cap not found is a success that counts a miss and goes quiet after three`() {
        val first = BackgroundRunPolicy.evaluate(Outcome.CapNotFound, previousMisses = 0)
        assertEquals(Verdict.SUCCESS, first.verdict)
        assertEquals(1, first.consecutiveMisses)
        assertFalse(first.quiet)

        val second = BackgroundRunPolicy.evaluate(Outcome.CapNotFound, previousMisses = first.consecutiveMisses)
        assertFalse(second.quiet)

        val third = BackgroundRunPolicy.evaluate(Outcome.CapNotFound, previousMisses = second.consecutiveMisses)
        assertEquals(3, third.consecutiveMisses)
        assertTrue(third.quiet)
        assertEquals(Verdict.SUCCESS, third.verdict)

        val fourth = BackgroundRunPolicy.evaluate(Outcome.CapNotFound, previousMisses = third.consecutiveMisses)
        assertTrue(fourth.quiet)
        assertEquals(4, fourth.consecutiveMisses)
    }

    @Test
    fun `other failures never retry and do not count as misses`() {
        val eval = BackgroundRunPolicy.evaluate(Outcome.Failed("GATT 133"), previousMisses = 2)
        assertEquals(Verdict.SUCCESS, eval.verdict)
        assertEquals(0, eval.consecutiveMisses)
        assertFalse(eval.quiet)
    }

    @Test
    fun `only a concurrent cap job triggers a retry and keeps the streak`() {
        val eval = BackgroundRunPolicy.evaluate(Outcome.Busy, previousMisses = 2)
        assertEquals(Verdict.RETRY, eval.verdict)
        assertEquals(2, eval.consecutiveMisses)
        assertFalse(eval.quiet)
    }

    @Test
    fun `labels are short and informative`() {
        assertEquals("synced: 3 new readings, 10 drinks, battery 42 %", Outcome.Synced(3, 10, 42).label())
        assertEquals("synced: 0 new readings, 0 drinks, battery n/a", Outcome.Synced(0, 0, null).label())
        assertEquals("cap not found", Outcome.CapNotFound.label())
        assertEquals("failed: boom", Outcome.Failed("boom").label())
    }
}
