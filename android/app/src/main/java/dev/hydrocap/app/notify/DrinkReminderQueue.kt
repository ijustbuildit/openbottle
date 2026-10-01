package dev.hydrocap.app.notify

import kotlinx.coroutines.*
import java.util.concurrent.atomic.AtomicLong

/** Read plans supersede plans, but cannot discard mutations or consume a queued delivery event. */
class DrinkReminderQueue(private val scope: CoroutineScope) {
    class Lease internal constructor(private val generation: Long, private val latest: AtomicLong,
        private val authority: Long, private val latestMutation: AtomicLong) {
        val isCurrent: Boolean get() = latest.get()==generation
        /** Read-only maintenance cannot invalidate a due delivery; OFF/settings changes can. */
        val isAuthorized: Boolean get() = latestMutation.get()==authority
    }
    private val latest=AtomicLong()
    private val mutations=AtomicLong()
    private var tail: Job?=null
    fun submitMutation(operation:suspend(Lease)->Unit):Job=enqueue(true,true,operation)
    fun submitDelivery(operation:suspend(Lease)->Unit):Job=enqueue(false,true,operation)
    fun submit(operation:suspend(Lease)->Unit):Job=enqueue(false,false,operation)
    @Synchronized private fun enqueue(mutation:Boolean,durable:Boolean,operation:suspend(Lease)->Unit):Job {
        val authority=if(mutation) mutations.incrementAndGet() else mutations.get()
        val lease=Lease(latest.incrementAndGet(),latest,authority,mutations)
        val previous=tail
        val task=scope.launch(start=CoroutineStart.LAZY) { previous?.join(); if(durable || lease.isCurrent) operation(lease) }
        tail=task; task.start(); return task
    }
}
