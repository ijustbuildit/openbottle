package dev.hydrocap.app.sync

import dev.hydrocap.app.domain.CapReminderConfig
import dev.hydrocap.app.domain.DndSettings
import dev.hydrocap.app.domain.ReminderSettings
import dev.hydrocap.app.domain.RingColor
import dev.hydrocap.app.proto.CapColor
import dev.hydrocap.app.proto.CapDoNotDisturbSettings
import dev.hydrocap.app.proto.CapEnumDoNotDisturbState
import dev.hydrocap.app.proto.CapEnumHydroReminderState
import dev.hydrocap.app.proto.CapHydroReminderSettings

/** Wire ↔ domain mapping for the reminder ring and quiet hours. */
object ReminderMapping {

    fun fromProto(settings: CapHydroReminderSettings): ReminderSettings = ReminderSettings(
        mode = settings.stateValue,
        startSec = settings.startTimeInSec,
        stopSec = settings.stopTimeInSec,
        intervalSec = settings.intervalInSec,
        color = if (settings.hasColor()) {
            RingColor(settings.color.red, settings.color.green, settings.color.blue, settings.color.alpha)
        } else {
            RingColor.FIRMWARE_DEFAULT
        },
    )

    fun fromProto(settings: CapDoNotDisturbSettings): DndSettings = DndSettings(
        mode = settings.stateValue,
        startSec = settings.startTimeInSec,
        stopSec = settings.stopTimeInSec,
        snoozeMinutes = settings.snoozeTimeInMinutes,
    )

    fun toProto(settings: ReminderSettings): CapHydroReminderSettings =
        CapHydroReminderSettings.newBuilder()
            .setState(CapEnumHydroReminderState.forNumber(settings.mode) ?: CapEnumHydroReminderState.REMINDER_STATE_OFF)
            .setStartTimeInSec(settings.startSec)
            .setStopTimeInSec(settings.stopSec)
            .setIntervalInSec(settings.intervalSec)
            .setColor(
                CapColor.newBuilder()
                    .setRed(settings.color.red)
                    .setGreen(settings.color.green)
                    .setBlue(settings.color.blue)
                    .setAlpha(settings.color.alpha),
            )
            .build()

    fun toProto(settings: DndSettings): CapDoNotDisturbSettings =
        CapDoNotDisturbSettings.newBuilder()
            .setState(CapEnumDoNotDisturbState.forNumber(settings.mode) ?: CapEnumDoNotDisturbState.DND_STATE_OFF)
            .setStartTimeInSec(settings.startSec)
            .setStopTimeInSec(settings.stopSec)
            .setSnoozeTimeInMinutes(settings.snoozeMinutes)
            .build()

    fun describe(config: CapReminderConfig): String {
        val r = config.reminder
        val d = config.dnd
        return "reminder{mode=${r.mode} start=${r.startSec} stop=${r.stopSec} interval=${r.intervalSec}s " +
            "color=(${r.color.red},${r.color.green},${r.color.blue},${r.color.alpha})} " +
            "dnd{mode=${d.mode} start=${d.startSec} stop=${d.stopSec} snooze=${d.snoozeMinutes}min}"
    }
}
