package dev.hydrocap.app.sync

import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ConnectionHandoffTest {
    private val identity=ConnectedCapIdentity("LARQ_synthetic","synthetic-stable")
    @Test fun readinessPublishesBeforeBlockedImportAndViewCancellationCannotCancelOwner() = runTest {
        val owner=CoroutineScope(SupervisorJob()+StandardTestDispatcher(testScheduler))
        val handoff=ConnectionHandoff(owner)
        val permitReady=CompletableDeferred<Unit>(); val permitImport=CompletableDeferred<Unit>()
        val order=mutableListOf<String>()
        val token=handoff.reserve()!!
        val job=handoff.startReserved(token,operation={ ready ->
            order+="connect"; permitReady.await(); ready(identity); order+="first-log-request"; permitImport.await(); ensureActive(); order+="import-finished"
        },onReady={order+="persist+home"},onFinished={order+="cleanup+reconcile"})!!
        runCurrent()
        assertTrue(handoff.isRunning); assertFalse(handoff.state.value.reachedReady)
        assertNull(handoff.reserve())
        permitReady.complete(Unit); runCurrent()
        assertTrue(handoff.state.value.reachedReady); assertEquals(identity,handoff.state.value.identity)
        assertEquals(listOf("connect","persist+home","first-log-request"),order)
        val view=launch { job.join() }; runCurrent(); view.cancel(); runCurrent()
        assertTrue(job.isActive)
        permitImport.complete(Unit); advanceUntilIdle()
        assertFalse(handoff.isRunning); assertEquals(listOf("import-finished","cleanup+reconcile"),order.takeLast(2))
        owner.cancel()
    }
    @Test fun preReadyFailureDoesNotPairAndRetryCanAcquire() = runTest {
        val handoff=ConnectionHandoff(backgroundScope)
        val token=handoff.reserve()!!
        handoff.startReserved(token,{throw IllegalStateException("synthetic connection failure")})!!.join()
        assertFalse(handoff.state.value.reachedReady); assertNull(handoff.state.value.identity); assertFalse(handoff.isRunning)
        assertNotNull(handoff.reserve())
    }
    @Test fun postReadyImportFailureKeepsPairingAndFinishes() = runTest {
        val handoff=ConnectionHandoff(backgroundScope); var finished=false
        handoff.startReserved(handoff.reserve()!!,{ready -> ready(identity); throw IllegalStateException("synthetic import failure")},onFinished={finished=true})!!.join()
        assertTrue(handoff.state.value.reachedReady); assertEquals(identity,handoff.state.value.identity); assertEquals("synthetic import failure",handoff.state.value.error)
        assertTrue(finished); assertFalse(handoff.isRunning)
    }
    @Test fun duplicateDispatchAndReadinessDoNotDuplicateJobOrNotice() = runTest {
        val handoff=ConnectionHandoff(backgroundScope); val gate=CompletableDeferred<Unit>(); var starts=0; var notices=0
        val token=handoff.reserve()!!
        val job=handoff.startReserved(token,{ready -> starts++; ready(identity); ready(identity); gate.await()},onReady={notices++})!!
        runCurrent()
        assertNull(handoff.startReserved(token,{starts++})); assertNull(handoff.reserve())
        assertEquals(1,starts); assertEquals(1,notices)
        gate.complete(Unit); job.join(); assertFalse(handoff.isRunning)
    }
    @Test fun reservationFencesSchedulingGapAndDispatchFailureReleasesIt() = runTest {
        val handoff=ConnectionHandoff(backgroundScope); val token=handoff.reserve()!!
        assertTrue(handoff.isRunning); assertNull(handoff.reserve())
        handoff.failReservation(token,"service refused")
        assertFalse(handoff.isRunning); assertNull(handoff.state.value.identity); assertEquals("service refused",handoff.state.value.error)
    }
    @Test fun cleanupFailureStillReleasesOwner() = runTest {
        val errors=mutableListOf<Throwable>()
        val owner=CoroutineScope(SupervisorJob()+StandardTestDispatcher(testScheduler)+CoroutineExceptionHandler {_,e -> errors+=e})
        val handoff=ConnectionHandoff(owner)
        handoff.startReserved(handoff.reserve()!!,{it(identity)},onFinished={throw IllegalStateException("synthetic cleanup failure")})!!.join()
        assertFalse(handoff.isRunning); assertEquals(1,errors.size); owner.cancel()
    }
    @Test fun identityNeverFallsBackToTransientAddress() {
        assertEquals("advertised",ConnectedCapIdentity.from("LARQ_synthetic","advertised","DIS")!!.deviceIdHex)
        assertEquals("DIS",ConnectedCapIdentity.from(null,null,"DIS")!!.deviceIdHex)
        assertNull(ConnectedCapIdentity.from("","",null))
    }
}
