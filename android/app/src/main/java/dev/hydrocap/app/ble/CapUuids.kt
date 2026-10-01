package dev.hydrocap.app.ble

import java.util.UUID

/** GATT identifiers from docs/protocol/ble-protocol.md §2. */
object CapUuids {
    val DEVICE_INFORMATION_SERVICE: UUID = UUID.fromString("0000180a-0000-1000-8000-00805f9b34fb")
    val MANUFACTURER_NAME: UUID = UUID.fromString("00002a29-0000-1000-8000-00805f9b34fb")
    val MODEL_NUMBER: UUID = UUID.fromString("00002a24-0000-1000-8000-00805f9b34fb")
    val SERIAL_NUMBER: UUID = UUID.fromString("00002a25-0000-1000-8000-00805f9b34fb")
    val FIRMWARE_REVISION: UUID = UUID.fromString("00002a26-0000-1000-8000-00805f9b34fb")
    val HARDWARE_REVISION: UUID = UUID.fromString("00002a27-0000-1000-8000-00805f9b34fb")
    val SOFTWARE_REVISION: UUID = UUID.fromString("00002a28-0000-1000-8000-00805f9b34fb")

    val BATTERY_SERVICE: UUID = UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb")
    val BATTERY_LEVEL: UUID = UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb")

    val NUS_SERVICE: UUID = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
    /** Phone → cap (write). */
    val NUS_RX: UUID = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    /** Cap → phone (notify). */
    val NUS_TX: UUID = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e")

    val CLIENT_CHARACTERISTIC_CONFIG: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

    /** Secure DFU service: listed only so the code can assert it is never touched. */
    val DFU_SERVICE: UUID = UUID.fromString("0000fe59-0000-1000-8000-00805f9b34fb")

    /** Nordic Semiconductor company identifier used in the cap's manufacturer data. */
    const val MANUFACTURER_ID_NORDIC = 0x0059
    val MANUFACTURER_PREFIX_CAP: ByteArray = "CAP".toByteArray(Charsets.US_ASCII)
}
