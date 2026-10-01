package dev.hydrocap.app.notify

import dev.hydrocap.app.data.AppSettings
import dev.hydrocap.app.domain.BottleProfile
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class DrinkReminderDeliveryPolicyTest {
    private val zone=ZoneId.of("UTC")
    private val settings=AppSettings("synthetic","synthetic",10,5,false,BottleProfile.DEFAULT.id,null,null,null,emptySet(),false,null,null,0,
        drinkRemindersEnabled=true,drinkReminderFrequencyMinutes=90,ringDeviceId="synthetic",lastRingStartSec=28800,lastRingStopSec=79200)
    private val due=Instant.parse("2026-09-30T21:30:00Z")
    private fun input()=DrinkReminderPlanner.Input(true,due,settings.ringWindow()!!,90,2000.0,0.0,zoneId=zone)
    @Test fun closingWindowWhileReadAwaitedSuppressesRealProductionPredicate() {
        assertTrue(DrinkReminderDeliveryPolicy.eligible(settings,settings,due.epochSecond,"synthetic",input(),Instant.parse("2026-09-30T21:59:59Z"),zone))
        assertFalse(DrinkReminderDeliveryPolicy.eligible(settings,settings,due.epochSecond,"synthetic",input(),Instant.parse("2026-09-30T22:00:00Z"),zone))
    }
    @Test fun midnightRolloverCannotUseYesterdayIntakeSnapshot() {
        assertFalse(DrinkReminderDeliveryPolicy.eligible(settings,settings,due.epochSecond,"synthetic",input(),Instant.parse("2026-10-01T08:00:00Z"),zone))
    }
    @Test fun disableCapChangeTargetChangeAndUnknownIntakeCannotDeliver() {
        assertFalse(DrinkReminderDeliveryPolicy.eligible(settings,settings.copy(drinkRemindersEnabled=false),due.epochSecond,"synthetic",input(),due,zone))
        assertFalse(DrinkReminderDeliveryPolicy.eligible(settings,settings,due.epochSecond,"different-cap",input(),due,zone))
        assertFalse(DrinkReminderDeliveryPolicy.eligible(settings,settings.copy(dailyTargetOverrideMl=3000),due.epochSecond,"synthetic",input(),due,zone))
        assertFalse(DrinkReminderDeliveryPolicy.eligible(settings,settings,due.epochSecond,"synthetic",input().copy(consumedTodayMl=null),due,zone))
    }
}
