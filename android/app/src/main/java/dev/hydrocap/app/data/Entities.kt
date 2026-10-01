package dev.hydrocap.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/** Raw ToF log record as pulled from the cap (protocol doc §4, `CapTofLog`). */
@Entity(tableName = "tof_log")
data class TofLogEntry(
    /** Unix seconds; the cap guarantees uniqueness per entry. */
    @PrimaryKey val timestamp: Long,
    val triggerType: Int,
    val distanceMm: Int,
    val kcps: Int,
    val uvLedTempOhm: Float,
)

/** UV activation record (`CapActivationLog`), doubles as battery SoC history. */
@Entity(tableName = "activation_log")
data class ActivationLogEntry(
    @PrimaryKey val timestamp: Long,
    val mode: Int,
    val batterySocPercent: Int,
)

/** A counted drink derived from the ToF log by [dev.hydrocap.app.domain.TofAlgorithm]. */
@Entity(tableName = "drink_event")
data class DrinkEvent(
    /** Unix seconds of the reading that produced the event. */
    @PrimaryKey val timestamp: Long,
    val volumeMl: Double,
    /** Timestamp of the source ToF log entry (== [timestamp] today; kept explicit for Health Connect ids). */
    val sourceLogTimestamp: Long,
    /** Bottle profile id the volume was computed with. */
    val profileId: String,
    /** Incremented when the value changes so Health Connect can detect updates. */
    val version: Long = 1,
)

/**
 * One drink event as written to Health Connect (phase 2). Lets the writer
 * skip unchanged events, re-write bumped versions and delete records for
 * events that no longer exist — without reading Health Connect back.
 */
@Entity(tableName = "health_sync")
data class HealthSyncRecord(
    /** [DrinkEvent.timestamp] the record was written for. */
    @PrimaryKey val timestamp: Long,
    /** The exact `Metadata.clientRecordId` used, so deletes hit the record we wrote even after re-pairing. */
    val clientRecordId: String,
    /** [DrinkEvent.version] at the time of the write (== `clientRecordVersion`). */
    val writtenVersion: Long,
    val writtenAtMs: Long,
)

@Entity(tableName = "battery_sample")
data class BatterySample(
    @PrimaryKey val timestamp: Long,
    val percent: Int,
)

/**
 * The paired cap. The cap uses a rotating resolvable private address, so the
 * identity is the advertised name + decoded serial; [lastAddress] is only the
 * address seen at the most recent scan and must never be used to connect
 * without a fresh scan.
 */
@Entity(tableName = "device")
data class DeviceRecord(
    @PrimaryKey val deviceIdHex: String,
    val name: String,
    val lastAddress: String?,
    val bottleSizeMl: Int?,
    val manufacturer: String?,
    val model: String?,
    val serial: String?,
    val firmwareRevision: String?,
    val hardwareRevision: String?,
    val softwareRevision: String?,
    val lastSeenMs: Long,
)
