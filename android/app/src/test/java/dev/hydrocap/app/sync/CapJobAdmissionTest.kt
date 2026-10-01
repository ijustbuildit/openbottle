package dev.hydrocap.app.sync

import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CapJobAdmissionTest {
    @Test fun backgroundPausedBeforeAdmissionCannotStealInitialReservation()=runTest {
        val gate=CapJobAdmission(); val handoff=ConnectionHandoff(backgroundScope,gate)
        val precheck=CompletableDeferred<Unit>(); val continueBackground=CompletableDeferred<Unit>()
        var admitted=false
        val worker=launch { precheck.complete(Unit); continueBackground.await(); admitted=gate.acquire() }
        precheck.await(); assertNotNull(handoff.reserve()); continueBackground.complete(Unit); worker.join()
        assertFalse(admitted); assertTrue(gate.acquire(initial=true)); gate.releaseJob(); gate.releaseInitial()
        assertTrue(gate.acquire()); gate.releaseJob()
    }
    @Test fun runningBackgroundMakesInitialReservationFailWithoutOverlappingLink() {
        val gate=CapJobAdmission(); assertTrue(gate.acquire()); assertFalse(gate.reserveInitial()); gate.releaseJob()
        assertTrue(gate.reserveInitial()); assertFalse(gate.acquire()); assertTrue(gate.acquire(true)); gate.releaseJob(); gate.releaseInitial()
    }
    @Test fun serviceDuplicateStartIdDoesNotStopBlockedInitialOwner() {
        val controller=ServiceJobOwner(); val owner=controller.admit(1)!!
        assertNull(controller.admit(2)); assertTrue(controller.isActive())
        assertEquals(2,controller.finish(owner)); assertFalse(controller.isActive()); assertNull(controller.finish(owner))
        val second=controller.admit(3)!!; assertTrue(controller.isActive()); assertEquals(3,controller.finish(second))
    }
}
