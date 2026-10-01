package dev.hydrocap.app.domain

import dev.hydrocap.app.proto.CapColor
import dev.hydrocap.app.proto.CapDoNotDisturbSettings
import dev.hydrocap.app.proto.CapEnumDoNotDisturbState
import dev.hydrocap.app.proto.CapEnumHydroReminderState
import dev.hydrocap.app.proto.CapHydroReminderSettings
import dev.hydrocap.app.sync.ReminderMapping
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReminderRulesTest {

    /** Interoperability settings observed during read-only hardware validation. */
    private val factory = CapReminderConfig(
        reminder = ReminderSettings(ReminderSettings.MODE_ADAPTIVE, 28_800, 78_300, 1_800, RingColor.FIRMWARE_DEFAULT),
        dnd = DndSettings(DndSettings.MODE_AUTO, 78_300, 28_800, 0),
    )

    @Test
    fun `factory values validate`() {
        assertNull(ReminderRules.validate(factory))
    }

    @Test
    fun `empty patch reproduces the cap values`() {
        assertEquals(factory, ReminderRules.resolve(factory, ReminderPatch(ReminderValues(), DndValues())))
    }

    @Test
    fun `auto quiet hours mirror the reminder window`() {
        val resolved = ReminderRules.resolve(
            factory,
            ReminderPatch(reminder = ReminderValues(startSec = 25_200, stopSec = 79_200), dnd = DndValues(mode = DndSettings.MODE_AUTO)),
        )
        assertEquals(25_200, resolved.reminder.startSec)
        assertEquals(79_200, resolved.dnd.startSec)
        assertEquals(25_200, resolved.dnd.stopSec)
        assertEquals(DndSettings.MODE_AUTO, resolved.dnd.mode)
    }

    @Test
    fun `custom quiet hours keep their own window and the snooze value`() {
        val current = factory.copy(dnd = factory.dnd.copy(snoozeMinutes = 15))
        val resolved = ReminderRules.resolve(current, ReminderPatch(dnd = DndValues(mode = DndSettings.MODE_CUSTOM, startSec = 80_000, stopSec = 21_600)))
        assertEquals(DndSettings(DndSettings.MODE_CUSTOM, 80_000, 21_600, 15), resolved.dnd)
        assertEquals(factory.reminder, resolved.reminder)
    }

    @Test
    fun `validation rejects bad intervals hours and colours`() {
        val on = factory.reminder
        assertNotNull(ReminderRules.validate(factory.copy(reminder = on.copy(intervalSec = 0))))
        assertNotNull(ReminderRules.validate(factory.copy(reminder = on.copy(startSec = 0))))
        assertNotNull(ReminderRules.validate(factory.copy(reminder = on.copy(stopSec = 86_401))))
        assertNotNull(ReminderRules.validate(factory.copy(reminder = on.copy(startSec = 3_600, stopSec = 3_600))))
        assertNotNull(ReminderRules.validate(factory.copy(reminder = on.copy(color = RingColor(1.2f, 0f, 0f)))))
        assertNotNull(ReminderRules.validate(factory.copy(reminder = on.copy(mode = 7))))
        val custom = factory.copy(dnd = DndSettings(DndSettings.MODE_CUSTOM, 100, 100, 0))
        assertNotNull(ReminderRules.validate(custom))
        assertNotNull(ReminderRules.validate(factory.copy(dnd = factory.dnd.copy(mode = 9))))
    }

    @Test
    fun `off mode ignores interval and hours but still writes wire-safe values`() {
        val resolved = ReminderRules.resolve(
            factory.copy(reminder = factory.reminder.copy(startSec = 0, stopSec = 0, intervalSec = 0)),
            ReminderPatch(reminder = ReminderValues(mode = ReminderSettings.MODE_OFF)),
        )
        assertNull(ReminderRules.validate(resolved))
        assertEquals(86_400, resolved.reminder.startSec)
        assertEquals(86_400, resolved.reminder.stopSec)
        assertEquals(0, resolved.reminder.intervalSec)
    }

    @Test
    fun `seconds of day round trip with midnight as 86400`() {
        assertEquals(86_400, ReminderRules.secOfDay(0, 0))
        assertEquals(28_800, ReminderRules.secOfDay(8, 0))
        assertEquals(78_300, ReminderRules.secOfDay(21, 45))
        assertEquals(0, ReminderRules.hourOf(86_400))
        assertEquals(21, ReminderRules.hourOf(78_300))
        assertEquals(45, ReminderRules.minuteOf(78_300))
        assertEquals("21:45", ReminderRules.formatSecOfDay(78_300))
        assertEquals("00:00", ReminderRules.formatSecOfDay(86_400))
    }

    @Test
    fun `colour conversion`() {
        val c = RingColor.fromRgb255(255, 128, 0)
        assertEquals(1f, c.red, 0f)
        assertEquals(128, c.green255())
        assertEquals(0, c.blue255())
        assertEquals(1f, c.alpha, 0f)
        assertTrue(RingColor.FIRMWARE_DEFAULT.isFirmwareDefault)
        assertFalse(c.isFirmwareDefault)
        assertEquals(6, RingColor.PRESETS.size)
    }

    @Test
    fun `proto mapping round trips and always sends alpha 1`() {
        val proto = ReminderMapping.toProto(ReminderSettings(ReminderSettings.MODE_FIXED, 28_800, 79_200, 3_600, RingColor(1f, 0.5f, 0.25f)))
        assertEquals(CapEnumHydroReminderState.REMINDER_STATE_INTERVAL_FIXED, proto.state)
        assertEquals(1f, proto.color.alpha, 0f)
        assertEquals(0.5f, proto.color.green, 0f)
        assertEquals(ReminderSettings(ReminderSettings.MODE_FIXED, 28_800, 79_200, 3_600, RingColor(1f, 0.5f, 0.25f)), ReminderMapping.fromProto(proto))

        val dnd = ReminderMapping.toProto(DndSettings(DndSettings.MODE_AUTO, 78_300, 28_800, 5))
        assertEquals(CapEnumDoNotDisturbState.DND_STATE_AUTO, dnd.state)
        assertEquals(5, dnd.snoozeTimeInMinutes)
        assertEquals(DndSettings(DndSettings.MODE_AUTO, 78_300, 28_800, 5), ReminderMapping.fromProto(dnd))

        // The hardware session 1 reading: colour present with alpha only.
        val capReminder = CapHydroReminderSettings.newBuilder()
            .setState(CapEnumHydroReminderState.REMINDER_STATE_INTERVAL_ADAPTIVE)
            .setStartTimeInSec(28_800).setStopTimeInSec(78_300).setIntervalInSec(1_800)
            .setColor(CapColor.newBuilder().setAlpha(1f))
            .build()
        assertEquals(factory.reminder, ReminderMapping.fromProto(capReminder))
        val capDnd = CapDoNotDisturbSettings.newBuilder()
            .setState(CapEnumDoNotDisturbState.DND_STATE_AUTO).setStartTimeInSec(78_300).setStopTimeInSec(28_800)
            .build()
        assertEquals(factory.dnd, ReminderMapping.fromProto(capDnd))
    }
}
