package dev.hydrocap.app.notify

import dev.hydrocap.app.data.AppSettings
import dev.hydrocap.app.domain.BottleProfile
import org.junit.Assert.*
import org.junit.Test
import java.time.Clock
import java.time.Instant
import java.time.ZoneId

class AndroidReminderPlanReconcilerTest {
    private val zone=ZoneId.of("UTC")
    private val settings=AppSettings("synthetic","synthetic",10,5,false,BottleProfile.DEFAULT.id,null,null,null,emptySet(),false,null,null,0,
        drinkRemindersEnabled=true,drinkReminderFrequencyMinutes=60,ringDeviceId="synthetic",lastRingStartSec=28800,lastRingStopSec=79200)
    private fun time(value:String)=Instant.parse("2026-09-30T${value}:00Z")
    private fun input(now:Instant)=DrinkReminderPlanner.Input(true,now,settings.ringWindow()!!,60,2000.0,0.0,zoneId=zone)
    private fun signature()=AndroidReminderPlanReconciler.signature(settings,settings.ringWindow()!!)
    @Test fun nineOclockRegisteredThenMaintenanceNineFifteenThenDeliveryNineThirtyIsPreserved() {
        var clock=Clock.fixed(time("08:15"),zone)
        val original=DrinkReminderPlanner.plan(input(Instant.now(clock)))
        val registered=original.map {AndroidReminderPlanReconciler.Registered(it.fireAt.epochSecond,"synthetic")}
        val nine=registered.first {it.epoch==time("09:00").epochSecond}
        clock=Clock.fixed(time("09:15"),zone)
        val now=Instant.now(clock); val value=input(now)
        val delta=AndroidReminderPlanReconciler.reconcile(registered,signature(),settings,value,DrinkReminderPlanner.plan(value),now,zone)
        assertTrue(delta.keep.contains(nine)); assertFalse(delta.cancel.contains(nine)); assertFalse(delta.add.any {it.fireAt.epochSecond==nine.epoch})
        clock=Clock.fixed(time("09:30"),zone)
        assertTrue(DrinkReminderDeliveryPolicy.eligible(settings,settings,nine.epoch,"synthetic",input(Instant.now(clock)),Instant.now(clock),zone))
    }
    @Test fun unchangedFutureRegistrationIsNotCanceledAndReadded() {
        val now=time("08:15"); val value=input(now); val proposed=DrinkReminderPlanner.plan(value)
        val existing=proposed.map {AndroidReminderPlanReconciler.Registered(it.fireAt.epochSecond,"synthetic")}
        val delta=AndroidReminderPlanReconciler.reconcile(existing,signature(),settings,value,proposed,now,zone)
        assertEquals(existing.toSet(),delta.keep.toSet()); assertTrue(delta.cancel.isEmpty()); assertTrue(delta.add.isEmpty())
    }
    @Test fun offAndCapChangeCancelOverdueRegisteredSlot() {
        val registered=listOf(AndroidReminderPlanReconciler.Registered(time("09:00").epochSecond,"synthetic"))
        val now=time("09:15"); val value=input(now)
        val off=AndroidReminderPlanReconciler.reconcile(registered,signature(),settings.copy(drinkRemindersEnabled=false),value,emptyList(),now,zone)
        assertEquals(registered,off.cancel); assertTrue(off.keep.isEmpty())
        val cap=AndroidReminderPlanReconciler.reconcile(registered,signature(),settings.copy(pairedDeviceIdHex="other",ringDeviceId="other"),value,emptyList(),now,zone)
        assertEquals(registered,cap.cancel); assertTrue(cap.keep.isEmpty())
    }
    @Test fun frequencyWindowChangeAndClosedWindowInvalidateOverdue() {
        val registered=listOf(AndroidReminderPlanReconciler.Registered(time("09:00").epochSecond,"synthetic"))
        val now=time("09:15"); val value=input(now)
        listOf(settings.copy(drinkReminderFrequencyMinutes=90),settings.copy(lastRingStartSec=32400)).forEach { changed ->
            val delta=AndroidReminderPlanReconciler.reconcile(registered,signature(),changed,value,emptyList(),now,zone)
            assertEquals(registered,delta.cancel); assertTrue(delta.keep.isEmpty())
        }
        val closed=AndroidReminderPlanReconciler.reconcile(registered,signature(),settings,input(time("22:01")),emptyList(),time("22:01"),zone)
        assertEquals(registered,closed.cancel)
    }
    @Test fun overduePlusNewSlotsNeverExceedEightAndUnknownIntakeDoesNotMeanZero() {
        val due=listOf(AndroidReminderPlanReconciler.Registered(time("09:00").epochSecond,"synthetic"))
        val now=time("09:15"); val value=input(now)
        val delta=AndroidReminderPlanReconciler.reconcile(due,signature(),settings,value,DrinkReminderPlanner.plan(value),now,zone)
        assertEquals(8,delta.keep.size+delta.add.size)
        val unknown=AndroidReminderPlanReconciler.reconcile(due,signature(),settings,value.copy(consumedTodayMl=null),emptyList(),now,zone)
        assertEquals(due,unknown.cancel); assertTrue(unknown.keep.isEmpty())
    }
    @Test fun consumedRegistrationIsNotResurrectedByFutureOnlyReplan() {
        val now=time("09:30"); val value=input(now)
        val delta=AndroidReminderPlanReconciler.reconcile(emptyList(),signature(),settings,value,DrinkReminderPlanner.plan(value),now,zone)
        assertTrue(delta.add.none {it.fireAt<=now}); assertFalse(delta.add.any {it.fireAt==time("09:00")})
    }
}
