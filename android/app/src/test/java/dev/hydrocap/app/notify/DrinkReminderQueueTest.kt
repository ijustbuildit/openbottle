package dev.hydrocap.app.notify

import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DrinkReminderQueueTest {
    @Test fun disableWaitsForInflightOsAddAndThenClearsExactSink() = runTest {
        val queue=DrinkReminderQueue(backgroundScope)
        val add=CompletableDeferred<Unit>(); val pending=mutableListOf<String>(); var disabled=false
        val old=queue.submit {lease -> add.await(); pending+="synthetic-inflight-alarm"; if(lease.isCurrent) pending+="must-not-resurrect-rest" }
        runCurrent()
        val disable=queue.submit {pending.clear(); disabled=true}
        runCurrent(); assertFalse(disabled)
        add.complete(Unit); old.join(); disable.join()
        assertTrue(disabled); assertTrue(pending.isEmpty())
    }
    @Test fun latestSettingsSupersedeReadThatDoesNotCooperateWithCancellation() = runTest {
        val queue=DrinkReminderQueue(backgroundScope); val read=CompletableDeferred<Unit>(); val effects=mutableListOf<String>()
        val old=queue.submit {lease -> read.await(); if(lease.isCurrent) effects+="stale-window" }
        runCurrent()
        val latest=queue.submit {effects+="latest-window"}; runCurrent()
        read.complete(Unit); old.join(); latest.join()
        assertEquals(listOf("latest-window"),effects)
    }
    @Test fun callerCancellationDoesNotCancelSerializedReplacement() = runTest {
        val queue=DrinkReminderQueue(backgroundScope); val gate=CompletableDeferred<Unit>(); var completed=false
        val task=queue.submit {gate.await(); completed=true}; val caller=launch {task.join()}
        runCurrent(); caller.cancel(); gate.complete(Unit); task.join(); assertTrue(completed)
    }
    @Test fun supersededQueuedRequestNeverExecutes() = runTest {
        val queue=DrinkReminderQueue(backgroundScope); val gate=CompletableDeferred<Unit>(); val effects=mutableListOf<String>()
        val first=queue.submit {gate.await()}; runCurrent()
        val stale=queue.submit {effects+="stale"}; val latest=queue.submit {effects+="latest"}
        gate.complete(Unit); first.join(); stale.join(); latest.join(); assertEquals(listOf("latest"),effects)
    }
    @Test fun queuedOffCannotBeSkippedByLaterReadonlyReplanOrDelivery() = runTest {
        val queue=DrinkReminderQueue(backgroundScope); val gate=CompletableDeferred<Unit>(); var enabled=true; val pending=mutableListOf("old")
        val old=queue.submit {gate.await()}; runCurrent()
        val off=queue.submitMutation {enabled=false; pending.clear()}
        val replan=queue.submit {if(enabled) pending+="resurrected"}
        gate.complete(Unit); old.join(); off.join(); replan.join()
        assertFalse(enabled); assertTrue(pending.isEmpty())
    }
    @Test fun queuedFrequencyAndBehindMutationsPersistBeforeLaterReadonlyPlan() = runTest {
        val queue=DrinkReminderQueue(backgroundScope); val gate=CompletableDeferred<Unit>(); var frequency=120; var behind=true; var observed=""
        val old=queue.submit {gate.await()}; runCurrent()
        val frequencyWrite=queue.submitMutation {frequency=90}
        val behindWrite=queue.submitMutation {behind=false}
        val read=queue.submit {observed="$frequency/$behind"}
        gate.complete(Unit); old.join(); frequencyWrite.join(); behindWrite.join(); read.join()
        assertEquals("90/false",observed)
    }
    @Test fun readonlyMaintenanceCannotDiscardQueuedDueDeliveryEvent()=runTest {
        val queue=DrinkReminderQueue(backgroundScope); val gate=CompletableDeferred<Unit>(); var notified=false; var consumed=false
        val old=queue.submit {gate.await()}; runCurrent()
        val delivery=queue.submitDelivery {lease -> consumed=true; if(lease.isAuthorized) notified=true}
        val maintenance=queue.submit {}; gate.complete(Unit); old.join(); delivery.join(); maintenance.join()
        assertTrue(consumed); assertTrue(notified)
    }
    @Test fun offMutationInvalidatesQueuedDeliveryAuthorityBeforeItsAwaitResumes()=runTest {
        val queue=DrinkReminderQueue(backgroundScope); val gate=CompletableDeferred<Unit>(); var notified=false; var off=false
        val delivery=queue.submitDelivery {lease -> gate.await(); if(lease.isAuthorized) notified=true}; runCurrent()
        val mutation=queue.submitMutation {off=true}; gate.complete(Unit); delivery.join(); mutation.join()
        assertFalse(notified); assertTrue(off)
    }
}
