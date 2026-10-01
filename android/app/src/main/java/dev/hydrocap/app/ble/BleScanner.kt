package dev.hydrocap.app.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import dev.hydrocap.app.debug.DebugLog
import dev.hydrocap.app.domain.DeviceName
import dev.hydrocap.app.protocol.Hex
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull

class BleScanException(message: String) : Exception(message)

/**
 * Filtered BLE scan for LARQ-family caps. Hardware filters: Device Information
 * service 0x180A OR Nordic manufacturer data starting with "CAP"; results are
 * then matched in software by name ("larq", case-insensitive) or the
 * manufacturer prefix. Every matching advertisement is logged with its raw
 * bytes so the first hardware session can see exactly what the cap sends.
 *
 * The cap rotates its address, so callers must always connect to the address
 * of a fresh scan result — never to a stored one.
 */
class BleScanner(private val context: Context, private val debugLog: DebugLog) {

    private val adapter: BluetoothAdapter?
        get() = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    val isBluetoothEnabled: Boolean get() = adapter?.isEnabled == true

    /**
     * Emits the growing set of discovered caps (deduplicated by address, latest
     * RSSI wins) until the collector cancels.
     */
    @SuppressLint("MissingPermission")
    fun scan(): Flow<List<DiscoveredCap>> = callbackFlow {
        val adapter = adapter ?: throw BleScanException("Bluetooth adapter unavailable")
        if (!adapter.isEnabled) throw BleScanException("Bluetooth is disabled")
        val scanner = adapter.bluetoothLeScanner ?: throw BleScanException("BLE scanner unavailable")

        val found = LinkedHashMap<String, DiscoveredCap>()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                handle(result)
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                results.forEach(::handle)
            }

            override fun onScanFailed(errorCode: Int) {
                debugLog.log(TAG, "scan failed errorCode=$errorCode")
                close(BleScanException("BLE scan failed (error $errorCode)"))
            }

            private fun handle(result: ScanResult) {
                val cap = toDiscoveredCap(result) ?: return
                val previous = found[cap.address]
                found[cap.address] = cap
                if (previous == null) {
                    debugLog.log(
                        TAG,
                        "found name=${cap.name} addr=${cap.address} rssi=${cap.rssi} id=${cap.deviceIdHex} " +
                            "byName=${cap.matchedByName} byMfg=${cap.matchedByManufacturerData} adv=${cap.rawAdvertisementHex}",
                    )
                }
                trySend(found.values.toList())
            }
        }

        val filters = listOf(
            ScanFilter.Builder().setServiceUuid(ParcelUuid(CapUuids.DEVICE_INFORMATION_SERVICE)).build(),
            ScanFilter.Builder()
                .setManufacturerData(
                    CapUuids.MANUFACTURER_ID_NORDIC,
                    CapUuids.MANUFACTURER_PREFIX_CAP,
                    byteArrayOf(0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte()),
                )
                .build(),
        )
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .build()

        debugLog.log(TAG, "scan start filters=[service 0x180A, mfg 0x0059 'CAP']")
        scanner.startScan(filters, settings, callback)
        trySend(emptyList())
        awaitClose {
            try {
                scanner.stopScan(callback)
            } catch (e: Exception) {
                debugLog.log(TAG, "stopScan failed: ${e.message}")
            }
            debugLog.log(TAG, "scan stop, ${found.size} cap(s) seen")
        }
    }

    /** Scans for [timeoutMs] and returns everything seen. */
    suspend fun scanFor(timeoutMs: Long): List<DiscoveredCap> {
        var latest: List<DiscoveredCap> = emptyList()
        withTimeoutOrNull(timeoutMs) {
            scan().collect { latest = it }
        }
        return latest
    }

    /** Returns the first cap matching [predicate] or null after [timeoutMs]. */
    suspend fun findCap(timeoutMs: Long, predicate: (DiscoveredCap) -> Boolean): DiscoveredCap? =
        withTimeoutOrNull(timeoutMs) {
            scan().first { list -> list.any(predicate) }.first(predicate)
        }

    private fun toDiscoveredCap(result: ScanResult): DiscoveredCap? {
        val record = result.scanRecord
        val name = record?.deviceName
        val manufacturerData = record?.getManufacturerSpecificData(CapUuids.MANUFACTURER_ID_NORDIC)
        val byName = CapAdvertisementMatcher.matchesName(name)
        val byManufacturer = CapAdvertisementMatcher.matchesManufacturerData(manufacturerData)
        if (!byName && !byManufacturer) return null
        return DiscoveredCap(
            name = name,
            address = result.device.address,
            rssi = result.rssi,
            deviceIdHex = DeviceName.decodeDeviceId(name),
            rawAdvertisementHex = record?.bytes?.let(Hex::encode),
            matchedByName = byName,
            matchedByManufacturerData = byManufacturer,
            seenAtMs = System.currentTimeMillis(),
        )
    }

    companion object {
        const val TAG = "scan"
        const val DEFAULT_SCAN_MS = 20_000L
        const val CONNECT_SCAN_MS = 30_000L
    }
}
