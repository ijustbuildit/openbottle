package dev.hydrocap.app.sync

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** Identity is never a transient BLE address. Published only after real notify + DIS readiness. */
data class ConnectedCapIdentity(val name: String, val deviceIdHex: String) {
    companion object {
        fun from(name: String?, advertisedId: String?, serial: String?): ConnectedCapIdentity? {
            val usableName = name?.takeIf { it.isNotEmpty() }
            val id = advertisedId?.takeIf { it.isNotEmpty() } ?: serial?.takeIf { it.isNotEmpty() } ?: usableName ?: return null
            return ConnectedCapIdentity(usableName ?: id, id)
        }
    }
}

data class HandoffState(val generation: Long = 0, val isRunning: Boolean = false, val reachedReady: Boolean = false, val identity: ConnectedCapIdentity? = null, val error: String? = null)

/** Production initial-sync owner: reservation also fences the service scheduling gap. */
class ConnectionHandoff(private val scope: CoroutineScope, private val admission: CapJobAdmission = CapJobAdmission()) {
    private val mutable = MutableStateFlow(HandoffState())
    val state: StateFlow<HandoffState> = mutable
    val isRunning: Boolean get() = mutable.value.isRunning
    private var activeJob: Job? = null

    @Synchronized fun reserve(): Long? {
        if (isRunning || !admission.reserveInitial()) return null
        val generation = mutable.value.generation + 1
        mutable.value = HandoffState(generation = generation, isRunning = true)
        return generation
    }

    @Synchronized fun failReservation(token: Long, reason: String) {
        if (mutable.value.generation == token && activeJob == null) {
            mutable.value = mutable.value.copy(isRunning = false, error = reason)
            admission.releaseInitial()
        }
    }

    @Synchronized fun startReserved(token: Long,
        operation: suspend (suspend (ConnectedCapIdentity) -> Unit) -> Unit,
        onReady: suspend (ConnectedCapIdentity) -> Unit = {},
        onFinished: suspend () -> Unit = {},
    ): Job? {
        if (!isRunning || mutable.value.generation != token || activeJob != null) return null
        // LAZY avoids a synchronous dispatcher completing before activeJob is assigned.
        val job = scope.launch(start = kotlinx.coroutines.CoroutineStart.LAZY) {
            try {
                operation { identity ->
                    if (!mutable.value.reachedReady) {
                        onReady(identity)
                        mutable.value = mutable.value.copy(reachedReady = true, identity = identity)
                    }
                }
            } catch (e: Exception) {
                mutable.value = mutable.value.copy(error = e.message ?: e.javaClass.simpleName)
            } finally {
                try { onFinished() } finally {
                    synchronized(this@ConnectionHandoff) {
                        mutable.value = mutable.value.copy(isRunning = false)
                        activeJob = null
                        admission.releaseInitial()
                    }
                }
            }
        }
        activeJob = job
        job.start()
        return job
    }
}
