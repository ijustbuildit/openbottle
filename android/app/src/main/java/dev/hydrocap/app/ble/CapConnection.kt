package dev.hydrocap.app.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.content.Context
import android.os.Build
import dev.hydrocap.app.debug.DebugLog
import dev.hydrocap.app.protocol.Hex
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID

/**
 * One GATT connection to a cap: connect → requestMtu(247) → discover →
 * enable NUS TX + Battery Level notifications → read DIS strings → ready.
 *
 * GATT allows a single outstanding operation, so every operation goes through
 * [gattMutex] and completes via a [CompletableDeferred] filled by the callback.
 * Raw notifications are re-published on [nusNotifications]; the request/response
 * protocol lives in [NusChannel].
 */
@SuppressLint("MissingPermission")
class CapConnection(
    private val context: Context,
    private val debugLog: DebugLog,
) {
    private val _state = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
    val state: StateFlow<ConnectionState> = _state

    private val _nusNotifications = MutableSharedFlow<ByteArray>(extraBufferCapacity = 64)
    val nusNotifications: SharedFlow<ByteArray> = _nusNotifications

    private val _batteryLevel = MutableStateFlow<Int?>(null)
    val batteryLevel: StateFlow<Int?> = _batteryLevel

    private val gattMutex = Mutex()
    private var gatt: BluetoothGatt? = null
    private var nusRx: BluetoothGattCharacteristic? = null
    private var nusTx: BluetoothGattCharacteristic? = null
    private var batteryLevelCharacteristic: BluetoothGattCharacteristic? = null

    private var connectDeferred: CompletableDeferred<Int>? = null
    private var mtuDeferred: CompletableDeferred<Int>? = null
    private var discoverDeferred: CompletableDeferred<Int>? = null
    private var descriptorWriteDeferred: CompletableDeferred<Int>? = null
    private var characteristicReadDeferred: CompletableDeferred<Pair<Int, ByteArray?>>? = null
    private var characteristicWriteDeferred: CompletableDeferred<Int>? = null

    var negotiatedMtu: Int = DEFAULT_MTU
        private set
    var deviceInformation: DeviceInformation? = null
        private set

    /** Write type that worked on this connection; starts with WRITE_TYPE_DEFAULT per the protocol doc. */
    var preferredWriteType: Int = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        private set

    val isReady: Boolean get() = _state.value is ConnectionState.Ready

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            debugLog.log(TAG, "onConnectionStateChange status=$status newState=${newState.stateName()}")
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> connectDeferred?.complete(status)
                BluetoothProfile.STATE_DISCONNECTED -> {
                    connectDeferred?.complete(if (status == BluetoothGatt.GATT_SUCCESS) GATT_DISCONNECTED_DURING_CONNECT else status)
                    failPending("disconnected (status $status)")
                    _state.value = if (_state.value is ConnectionState.Connecting) {
                        ConnectionState.Failed("connect failed, GATT status $status")
                    } else {
                        ConnectionState.Disconnected
                    }
                    g.close()
                    if (gatt === g) gatt = null
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            debugLog.log(TAG, "onMtuChanged mtu=$mtu status=$status")
            if (status == BluetoothGatt.GATT_SUCCESS) negotiatedMtu = mtu
            mtuDeferred?.complete(status)
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            debugLog.log(TAG, "onServicesDiscovered status=$status services=${g.services.map { it.uuid.short() }}")
            discoverDeferred?.complete(status)
        }

        override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            debugLog.log(TAG, "onDescriptorWrite char=${descriptor.characteristic.uuid.short()} status=$status")
            descriptorWriteDeferred?.complete(status)
        }

        @Deprecated("Pre-API 33 callback")
        override fun onCharacteristicRead(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            @Suppress("DEPRECATION")
            handleRead(characteristic, characteristic.value, status)
        }

        override fun onCharacteristicRead(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            handleRead(characteristic, value, status)
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            debugLog.log(TAG, "onCharacteristicWrite char=${characteristic.uuid.short()} status=$status")
            characteristicWriteDeferred?.complete(status)
        }

        @Deprecated("Pre-API 33 callback")
        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            @Suppress("DEPRECATION")
            handleChanged(characteristic, characteristic.value ?: ByteArray(0))
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            handleChanged(characteristic, value)
        }

        private fun handleRead(characteristic: BluetoothGattCharacteristic, value: ByteArray?, status: Int) {
            debugLog.log(TAG, "onCharacteristicRead char=${characteristic.uuid.short()} status=$status len=${value?.size ?: 0} hex=${value?.let(Hex::encode)}")
            characteristicReadDeferred?.complete(status to value)
        }

        private fun handleChanged(characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            when (characteristic.uuid) {
                CapUuids.NUS_TX -> {
                    debugLog.log(TAG, "notify NUS TX len=${value.size} hex=${Hex.encode(value)}")
                    if (!_nusNotifications.tryEmit(value)) debugLog.log(TAG, "notification buffer full, dropped ${value.size} bytes")
                }
                CapUuids.BATTERY_LEVEL -> {
                    val level = value.firstOrNull()?.toInt()?.and(0xff)
                    debugLog.log(TAG, "notify Battery Level=$level")
                    _batteryLevel.value = level
                }
                else -> debugLog.log(TAG, "notify ${characteristic.uuid.short()} len=${value.size} hex=${Hex.encode(value)}")
            }
        }
    }

    /**
     * Connects to [address] (which must come from a scan result taken moments
     * ago — the cap rotates its address) and brings the link to [ConnectionState.Ready].
     */
    suspend fun connect(address: String) {
        check(gatt == null) { "already connected" }
        val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            ?: throw BleConnectionException("Bluetooth adapter unavailable")
        if (!adapter.isEnabled) throw BleConnectionException("Bluetooth is disabled")
        if (!BluetoothAdapter.checkBluetoothAddress(address)) throw BleConnectionException("invalid address $address")

        _state.value = ConnectionState.Connecting(address)
        try {
            val device = adapter.getRemoteDevice(address)
            connectGatt(device, address)
            _state.value = ConnectionState.Connected(address)

            requestMtu(REQUESTED_MTU)
            _state.value = ConnectionState.Configuring(address, negotiatedMtu)

            discoverServices()
            bindCharacteristics()
            enableNotifications(nusTx!!)
            batteryLevelCharacteristic?.let { battery ->
                // Battery notifications are a nice-to-have; a cap without a CCCD there must not block the sync.
                try {
                    enableNotifications(battery)
                } catch (e: BleConnectionException) {
                    debugLog.log(TAG, "battery notifications unavailable: ${e.message} (will poll)")
                }
            }
            val info = readDeviceInformation()
            deviceInformation = info
            _state.value = ConnectionState.Ready(address, negotiatedMtu, info)
            debugLog.log(TAG, "ready mtu=$negotiatedMtu ${info.describe()}")
        } catch (e: Exception) {
            debugLog.error(TAG, "connect failed", e)
            _state.value = ConnectionState.Failed(e.message ?: e.javaClass.simpleName)
            closeQuietly()
            throw if (e is BleConnectionException) e else BleConnectionException(e.message ?: "connect failed", e)
        }
    }

    private suspend fun connectGatt(device: BluetoothDevice, address: String) {
        val deferred = CompletableDeferred<Int>()
        connectDeferred = deferred
        debugLog.log(TAG, "connectGatt $address transport=LE autoConnect=false")
        gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
            ?: throw BleConnectionException("connectGatt returned null")
        val status = withTimeoutOrNull(CONNECT_TIMEOUT_MS) { deferred.await() }
        connectDeferred = null
        when {
            status == null -> throw BleConnectionException("connect timeout after ${CONNECT_TIMEOUT_MS / 1000} s")
            status != BluetoothGatt.GATT_SUCCESS -> throw BleConnectionException("connect failed, GATT status $status")
        }
    }

    private suspend fun requestMtu(mtu: Int) = gattMutex.withLock {
        val g = gatt ?: throw BleConnectionException("not connected")
        val deferred = CompletableDeferred<Int>()
        mtuDeferred = deferred
        debugLog.log(TAG, "requestMtu($mtu)")
        if (!g.requestMtu(mtu)) {
            mtuDeferred = null
            debugLog.log(TAG, "requestMtu rejected by stack, continuing with default $negotiatedMtu")
            return@withLock
        }
        val status = withTimeoutOrNull(OPERATION_TIMEOUT_MS) { deferred.await() }
        mtuDeferred = null
        if (status == null) debugLog.log(TAG, "requestMtu timed out, continuing with $negotiatedMtu")
        debugLog.log(TAG, "negotiated MTU=$negotiatedMtu (max notification payload ${negotiatedMtu - 3})")
    }

    private suspend fun discoverServices() = gattMutex.withLock {
        val g = gatt ?: throw BleConnectionException("not connected")
        val deferred = CompletableDeferred<Int>()
        discoverDeferred = deferred
        if (!g.discoverServices()) throw BleConnectionException("discoverServices rejected")
        val status = withTimeoutOrNull(DISCOVER_TIMEOUT_MS) { deferred.await() }
        discoverDeferred = null
        if (status == null) throw BleConnectionException("service discovery timeout")
        if (status != BluetoothGatt.GATT_SUCCESS) throw BleConnectionException("service discovery failed, status $status")
    }

    private fun bindCharacteristics() {
        val g = gatt ?: throw BleConnectionException("not connected")
        val nus = g.getService(CapUuids.NUS_SERVICE) ?: throw BleConnectionException("NUS service not found")
        nusRx = nus.getCharacteristic(CapUuids.NUS_RX) ?: throw BleConnectionException("NUS RX characteristic not found")
        nusTx = nus.getCharacteristic(CapUuids.NUS_TX) ?: throw BleConnectionException("NUS TX characteristic not found")
        batteryLevelCharacteristic = g.getService(CapUuids.BATTERY_SERVICE)?.getCharacteristic(CapUuids.BATTERY_LEVEL)
        debugLog.log(
            TAG,
            "NUS RX props=0x${Integer.toHexString(nusRx!!.properties)} TX props=0x${Integer.toHexString(nusTx!!.properties)} " +
                "battery=${batteryLevelCharacteristic != null} dfuPresent=${g.getService(CapUuids.DFU_SERVICE) != null} (never touched)",
        )
    }

    private suspend fun enableNotifications(characteristic: BluetoothGattCharacteristic) = gattMutex.withLock {
        val g = gatt ?: throw BleConnectionException("not connected")
        if (!g.setCharacteristicNotification(characteristic, true)) {
            throw BleConnectionException("setCharacteristicNotification failed for ${characteristic.uuid.short()}")
        }
        val cccd = characteristic.getDescriptor(CapUuids.CLIENT_CHARACTERISTIC_CONFIG)
            ?: throw BleConnectionException("CCCD missing on ${characteristic.uuid.short()}")
        val deferred = CompletableDeferred<Int>()
        descriptorWriteDeferred = deferred
        val issued = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val rc = g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
            if (rc != BluetoothStatusCodes.SUCCESS) debugLog.log(TAG, "writeDescriptor rejected rc=$rc")
            rc == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            run {
                cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                g.writeDescriptor(cccd)
            }
        }
        debugLog.log(TAG, "write CCCD 0x2902=0x0100 on ${characteristic.uuid.short()} issued=$issued")
        if (!issued) throw BleConnectionException("CCCD write rejected for ${characteristic.uuid.short()}")
        val status = withTimeoutOrNull(OPERATION_TIMEOUT_MS) { deferred.await() }
        descriptorWriteDeferred = null
        if (status == null) throw BleConnectionException("CCCD write timeout for ${characteristic.uuid.short()}")
        if (status != BluetoothGatt.GATT_SUCCESS) throw BleConnectionException("CCCD write failed, status $status")
    }

    private suspend fun readDeviceInformation(): DeviceInformation {
        val g = gatt ?: throw BleConnectionException("not connected")
        val dis = g.getService(CapUuids.DEVICE_INFORMATION_SERVICE)
        if (dis == null) {
            throw BleConnectionException("Device Information service missing")
        }
        suspend fun readString(uuid: UUID): String? {
            val characteristic = dis.getCharacteristic(uuid) ?: return null
            return readCharacteristic(characteristic)?.toString(Charsets.UTF_8)?.trimEnd('\u0000')
        }
        return DeviceInformation(
            manufacturer = readString(CapUuids.MANUFACTURER_NAME),
            model = readString(CapUuids.MODEL_NUMBER),
            serial = readString(CapUuids.SERIAL_NUMBER),
            firmwareRevision = readString(CapUuids.FIRMWARE_REVISION),
            hardwareRevision = readString(CapUuids.HARDWARE_REVISION),
            softwareRevision = readString(CapUuids.SOFTWARE_REVISION),
        )
    }

    /** Reads Battery Level (0x2A19) and updates [batteryLevel]. */
    suspend fun readBatteryLevel(): Int? {
        val characteristic = batteryLevelCharacteristic ?: return null
        val level = readCharacteristic(characteristic)?.firstOrNull()?.toInt()?.and(0xff)
        debugLog.log(TAG, "battery level read=$level")
        if (level != null) _batteryLevel.value = level
        return level
    }

    private suspend fun readCharacteristic(characteristic: BluetoothGattCharacteristic): ByteArray? = gattMutex.withLock {
        val g = gatt ?: throw BleConnectionException("not connected")
        val deferred = CompletableDeferred<Pair<Int, ByteArray?>>()
        characteristicReadDeferred = deferred
        if (!g.readCharacteristic(characteristic)) {
            characteristicReadDeferred = null
            debugLog.log(TAG, "readCharacteristic rejected for ${characteristic.uuid.short()}")
            return@withLock null
        }
        val result = withTimeoutOrNull(OPERATION_TIMEOUT_MS) { deferred.await() }
        characteristicReadDeferred = null
        if (result == null) throw BleConnectionException("read timeout for ${characteristic.uuid.short()}")
        if (result.first != BluetoothGatt.GATT_SUCCESS) return@withLock null
        result.second
    }

    /**
     * Writes one request to NUS RX. Starts with WRITE_TYPE_DEFAULT; if the
     * stack or the cap rejects it, retries once with WRITE_TYPE_NO_RESPONSE and
     * remembers whichever worked for the rest of the connection.
     */
    suspend fun writeNusRx(bytes: ByteArray) {
        val first = preferredWriteType
        val status = writeCharacteristic(bytes, first)
        if (status == BluetoothGatt.GATT_SUCCESS) return
        val fallback = if (first == BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        }
        debugLog.log(TAG, "write with ${first.writeTypeName()} failed (status $status), retrying with ${fallback.writeTypeName()}")
        val retryStatus = writeCharacteristic(bytes, fallback)
        if (retryStatus == BluetoothGatt.GATT_SUCCESS) {
            preferredWriteType = fallback
            debugLog.log(TAG, "write type ${fallback.writeTypeName()} works, using it from now on")
            return
        }
        throw BleConnectionException("NUS RX write failed with both write types (status $status / $retryStatus)")
    }

    private suspend fun writeCharacteristic(bytes: ByteArray, writeType: Int): Int = gattMutex.withLock {
        val g = gatt ?: throw BleConnectionException("not connected")
        val characteristic = nusRx ?: throw BleConnectionException("NUS RX not bound")
        val deferred = CompletableDeferred<Int>()
        characteristicWriteDeferred = deferred
        val issued: Boolean
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val rc = g.writeCharacteristic(characteristic, bytes, writeType)
            issued = rc == BluetoothStatusCodes.SUCCESS
            if (!issued) debugLog.log(TAG, "writeCharacteristic rejected rc=$rc (BluetoothStatusCodes)")
        } else {
            @Suppress("DEPRECATION")
            run {
                characteristic.writeType = writeType
                characteristic.value = bytes
                issued = g.writeCharacteristic(characteristic)
            }
        }
        debugLog.log(TAG, "write NUS RX type=${writeType.writeTypeName()} len=${bytes.size} issued=$issued")
        if (!issued) {
            characteristicWriteDeferred = null
            return@withLock GATT_WRITE_REJECTED
        }
        val status = withTimeoutOrNull(OPERATION_TIMEOUT_MS) { deferred.await() }
        characteristicWriteDeferred = null
        status ?: run {
            debugLog.log(TAG, "write ack timeout")
            GATT_WRITE_TIMEOUT
        }
    }

    suspend fun disconnect() {
        val g = gatt ?: return
        debugLog.log(TAG, "disconnect")
        try {
            g.disconnect()
        } catch (e: Exception) {
            debugLog.log(TAG, "disconnect threw ${e.message}")
        }
        closeQuietly()
        _state.value = ConnectionState.Disconnected
    }

    private fun failPending(reason: String) {
        val error = BleConnectionException(reason)
        mtuDeferred?.completeExceptionally(error)
        discoverDeferred?.completeExceptionally(error)
        descriptorWriteDeferred?.completeExceptionally(error)
        characteristicReadDeferred?.completeExceptionally(error)
        characteristicWriteDeferred?.completeExceptionally(error)
    }

    private fun closeQuietly() {
        try {
            gatt?.close()
        } catch (_: Exception) {
        }
        gatt = null
        nusRx = null
        nusTx = null
        batteryLevelCharacteristic = null
    }

    private fun Int.stateName(): String = when (this) {
        BluetoothProfile.STATE_CONNECTED -> "CONNECTED"
        BluetoothProfile.STATE_DISCONNECTED -> "DISCONNECTED"
        BluetoothProfile.STATE_CONNECTING -> "CONNECTING"
        BluetoothProfile.STATE_DISCONNECTING -> "DISCONNECTING"
        else -> toString()
    }

    private fun UUID.short(): String {
        val s = toString()
        return if (s.endsWith("-0000-1000-8000-00805f9b34fb")) "0x" + s.substring(4, 8).uppercase() else s
    }

    companion object {
        const val TAG = "gatt"
        const val REQUESTED_MTU = 247
        const val DEFAULT_MTU = 23
        const val CONNECT_TIMEOUT_MS = 15_000L
        const val DISCOVER_TIMEOUT_MS = 10_000L
        const val OPERATION_TIMEOUT_MS = 5_000L
        private const val GATT_DISCONNECTED_DURING_CONNECT = -1
        private const val GATT_WRITE_REJECTED = -2
        private const val GATT_WRITE_TIMEOUT = -3

        fun Int.writeTypeName(): String = when (this) {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT -> "WRITE_TYPE_DEFAULT"
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE -> "WRITE_TYPE_NO_RESPONSE"
            else -> "writeType=$this"
        }
    }
}
