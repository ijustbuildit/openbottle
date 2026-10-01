package dev.hydrocap.app.ble

/** Device Information Service strings read once per connection. */
data class DeviceInformation(
    val manufacturer: String?,
    val model: String?,
    val serial: String?,
    val firmwareRevision: String?,
    val hardwareRevision: String?,
    val softwareRevision: String?,
) {
    fun describe(): String =
        "manufacturer=$manufacturer model=$model serial=$serial fw=$firmwareRevision hw=$hardwareRevision sw=$softwareRevision"
}

/** Observable GATT lifecycle, surfaced on the Home status line and in the Debug log. */
sealed class ConnectionState {
    data object Disconnected : ConnectionState()
    data class Connecting(val address: String) : ConnectionState()
    data class Connected(val address: String) : ConnectionState()
    data class Configuring(val address: String, val mtu: Int) : ConnectionState()
    data class Ready(val address: String, val mtu: Int, val info: DeviceInformation) : ConnectionState()
    data class Failed(val reason: String) : ConnectionState()

    val isActive: Boolean get() = this is Connecting || this is Connected || this is Configuring || this is Ready
}

class BleConnectionException(message: String, cause: Throwable? = null) : Exception(message, cause)
