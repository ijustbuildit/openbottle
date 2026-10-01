import CoreBluetooth
import Foundation
import Observation

/// One GATT connection to a cap: connect → discover (0x180A / 0x180F / NUS) →
/// enable notify on NUS TX and Battery Level → read DIS strings → ready.
///
/// The cap rotates its resolvable private address, so a connection is always
/// built from a *fresh* scan result; the identifier is a session handle, never
/// a stored identity. CoreBluetooth negotiates the ATT MTU itself — the write
/// limit is read back with `maximumWriteValueLength(for: .withResponse)` and a
/// longer request is an error, because HydroCap never chunks writes.
@MainActor
@Observable
final class CapConnection: NusTransport {
    nonisolated static let tag = "gatt"
    /// 23-byte default ATT MTU minus the 3-byte header.
    nonisolated static let defaultWriteLength = 20
    nonisolated static let connectTimeoutSeconds = 15.0
    nonisolated static let discoverTimeoutSeconds = 10.0
    nonisolated static let operationTimeoutSeconds = 5.0
    /// Hardware session 1: connecting within ~8 s of a disconnect can fail.
    nonisolated static let reconnectDelaySeconds = 8.0

    let peripheralIdentifier: String
    private let central: CapCentral
    private let debugLog: DebugLog

    private(set) var state: ConnectionState = .disconnected
    private(set) var deviceInformation: DeviceInformation?
    private(set) var maximumWriteLength = CapConnection.defaultWriteLength
    private(set) var batteryLevel: Int?
    private(set) var preferredWriteType: CBCharacteristicWriteType = .withResponse

    /// Immutable `Sendable` storage, so it satisfies the nonisolated
    /// `NusTransport` requirement without a hop.
    nonisolated let notifications: AsyncStream<Data>
    private nonisolated let notificationSink: AsyncStream<Data>.Continuation

    private var peripheral: CBPeripheral?
    private var nusRx: CBCharacteristic?
    private var nusTx: CBCharacteristic?
    /// UUID string of the service whose characteristic discovery is in flight.
    private var pendingCharacteristicsService: String?
    private var batteryLevelCharacteristic: CBCharacteristic?

    private var servicesWaiter: AsyncWaiter<Void>?
    private var characteristicsWaiter: AsyncWaiter<Void>?
    private var notificationStateWaiters: [String: AsyncWaiter<Bool>] = [:]
    private var readWaiters: [String: AsyncWaiter<Data>] = [:]
    private var writeWaiter: AsyncWaiter<Void>?

    init(central: CapCentral, debugLog: DebugLog, cap: DiscoveredCap) {
        self.central = central
        self.debugLog = debugLog
        self.peripheralIdentifier = cap.address
        (notifications, notificationSink) = AsyncStream.makeStream(of: Data.self)
    }

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    // MARK: - Connect

    /// Brings the link to `ConnectionState.ready`. `allowReconnectRetry`
    /// implements the hardware-session-1 retry (once, after 8 s) for foreground
    /// jobs; the 25 s background budget runs without it.
    func connect(allowReconnectRetry: Bool) async throws {
        guard peripheral == nil else { throw BleConnectionError("already connected") }
        state = .connecting(address: peripheralIdentifier)
        var attempt = 1
        while true {
            do {
                try await connectOnce()
                return
            } catch {
                let failure = error as? BleConnectionError ?? BleConnectionError("\(error)")
                state = .failed(reason: failure.message)
                // A half-open link (connected, but discovery/notify failed)
                // must be torn down explicitly: iOS would otherwise keep the
                // cap connected in the background and it would stop
                // advertising for every following scan.
                if let peripheral { central.cancelConnection(peripheral) }
                closeQuietly()
                if attempt == 1, allowReconnectRetry {
                    attempt = 2
                    debugLog.log(
                        Self.tag,
                        "connect failed (\(failure.message)); the cap rejects connects shortly after a disconnect, retrying once in \(Int(Self.reconnectDelaySeconds)) s",
                    )
                    try? await Task.sleep(nanoseconds: UInt64(Self.reconnectDelaySeconds * 1_000_000_000))
                    state = .connecting(address: peripheralIdentifier)
                    continue
                }
                debugLog.error(Self.tag, "connect failed", error: error)
                throw failure
            }
        }
    }

    private func connectOnce() async throws {
        let peripheral = try await central.connect(identifier: peripheralIdentifier, timeoutSeconds: Self.connectTimeoutSeconds)
        peripheral.delegate = central.bleDelegate
        self.peripheral = peripheral
        central.bind(self)
        state = .connected(address: peripheralIdentifier)

        try await discoverServices(peripheral)
        try await discoverCharacteristics(peripheral)
        bindCharacteristics(peripheral)
        state = .configuring(address: peripheralIdentifier)

        guard let nusTx else { throw BleConnectionError("NUS TX characteristic not found") }
        try await enableNotifications(peripheral, characteristic: nusTx)
        if let battery = batteryLevelCharacteristic {
            // Battery notifications are a nice-to-have; a cap without them must
            // not block the sync (the level is polled instead).
            do {
                try await enableNotifications(peripheral, characteristic: battery)
            } catch {
                debugLog.log(Self.tag, "battery notifications unavailable: \(error) (will poll)")
            }
        }
        let info = await readDeviceInformation(peripheral)
        deviceInformation = info
        maximumWriteLength = peripheral.maximumWriteValueLength(for: .withResponse)
        state = .ready(address: peripheralIdentifier, maximumWriteLength: maximumWriteLength, info: info)
        debugLog.log(
            Self.tag,
            "ready maximumWriteValueLength(for: .withResponse)=\(maximumWriteLength) B \(info.describe())",
        )
    }

    private func discoverServices(_ peripheral: CBPeripheral) async throws {
        let waiter = AsyncWaiter<Void>()
        servicesWaiter = waiter
        peripheral.discoverServices([CapUuids.deviceInformationService, CapUuids.batteryService, CapUuids.nusService])
        do {
            try await waiter.wait(timeoutSeconds: Self.discoverTimeoutSeconds) {
                BleConnectionError("service discovery timeout")
            }
        } catch {
            servicesWaiter = nil
            throw error as? BleConnectionError ?? BleConnectionError("service discovery failed")
        }
        servicesWaiter = nil
        let discoveredServices = (peripheral.services ?? []).map { CapUuids.shortName($0.uuid) }
        debugLog.log(Self.tag, "services=\(discoveredServices)")
        if peripheral.services?.contains(where: { $0.uuid == CapUuids.dfuService }) == true {
            debugLog.log(Self.tag, "DFU service present, never touched")
        }
    }

    /// Discovers the characteristics of each service we use **one service at
    /// a time**: CoreBluetooth delivers one `didDiscoverCharacteristicsFor`
    /// per service, in whatever order the peripheral answers. Issuing all
    /// three at once and waiting for the first callback binds NUS before its
    /// characteristics exist ("NUS TX characteristic not found" on device).
    private func discoverCharacteristics(_ peripheral: CBPeripheral) async throws {
        let wanted = [CapUuids.nusService, CapUuids.batteryService, CapUuids.deviceInformationService]
        for service in peripheral.services ?? [] where wanted.contains(service.uuid) {
            let serviceName = CapUuids.shortName(service.uuid)
            let waiter = AsyncWaiter<Void>()
            characteristicsWaiter = waiter
            pendingCharacteristicsService = service.uuid.uuidString
            peripheral.discoverCharacteristics(nil, for: service)
            do {
                try await waiter.wait(timeoutSeconds: Self.discoverTimeoutSeconds) {
                    BleConnectionError("characteristic discovery timeout (\(serviceName))")
                }
            } catch {
                characteristicsWaiter = nil
                pendingCharacteristicsService = nil
                throw error as? BleConnectionError ?? BleConnectionError("characteristic discovery failed")
            }
            debugLog.log(Self.tag, "characteristics \(CapUuids.shortName(service.uuid))=\((service.characteristics ?? []).map { CapUuids.shortName($0.uuid) })")
        }
        characteristicsWaiter = nil
        pendingCharacteristicsService = nil
    }

    private func bindCharacteristics(_ peripheral: CBPeripheral) {
        let nus = peripheral.services?.first { $0.uuid == CapUuids.nusService }
        nusRx = nus?.characteristics?.first { $0.uuid == CapUuids.nusRx }
        nusTx = nus?.characteristics?.first { $0.uuid == CapUuids.nusTx }
        batteryLevelCharacteristic = peripheral.services?
            .first { $0.uuid == CapUuids.batteryService }?
            .characteristics?.first { $0.uuid == CapUuids.batteryLevel }
        debugLog.log(
            Self.tag,
            "NUS RX=\(nusRx != nil) TX=\(nusTx != nil) battery=\(batteryLevelCharacteristic != nil) " +
                "properties RX=\(nusRx?.properties.rawValue ?? 0) TX=\(nusTx?.properties.rawValue ?? 0)",
        )
        guard nusRx != nil else { debugLog.log(Self.tag, "NUS RX characteristic missing") ; return }
    }

    private func enableNotifications(_ peripheral: CBPeripheral, characteristic: CBCharacteristic) async throws {
        let characteristicName = CapUuids.shortName(characteristic.uuid)
        let waiter = AsyncWaiter<Bool>()
        notificationStateWaiters[characteristic.uuid.uuidString] = waiter
        peripheral.setNotifyValue(true, for: characteristic)
        do {
            let isNotifying = try await waiter.wait(timeoutSeconds: Self.operationTimeoutSeconds) {
                BleConnectionError("notification enable timeout for \(characteristicName)")
            }
            debugLog.log(Self.tag, "setNotifyValue(true) on \(CapUuids.shortName(characteristic.uuid)) isNotifying=\(isNotifying)")
            guard isNotifying else {
                throw BleConnectionError("notifications not enabled for \(CapUuids.shortName(characteristic.uuid))")
            }
        } catch {
            notificationStateWaiters[characteristic.uuid.uuidString] = nil
            throw error as? BleConnectionError ?? BleConnectionError("notification enable failed")
        }
        notificationStateWaiters[characteristic.uuid.uuidString] = nil
    }

    private func readDeviceInformation(_ peripheral: CBPeripheral) async -> DeviceInformation {
        guard let dis = peripheral.services?.first(where: { $0.uuid == CapUuids.deviceInformationService }) else {
            debugLog.log(Self.tag, "Device Information service missing")
            return DeviceInformation()
        }
        func characteristic(_ uuid: CBUUID) -> CBCharacteristic? {
            dis.characteristics?.first { $0.uuid == uuid }
        }
        func readString(_ uuid: CBUUID) async -> String? {
            guard let characteristic = characteristic(uuid) else { return nil }
            guard let data = await readValue(peripheral, characteristic: characteristic) else { return nil }
            return String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\0", with: "")
        }
        return DeviceInformation(
            manufacturer: await readString(CapUuids.manufacturerName),
            model: await readString(CapUuids.modelNumber),
            serial: await readString(CapUuids.serialNumber),
            firmwareRevision: await readString(CapUuids.firmwareRevision),
            hardwareRevision: await readString(CapUuids.hardwareRevision),
            softwareRevision: await readString(CapUuids.softwareRevision),
        )
    }

    // MARK: - Characteristic operations

    /// Reads Battery Level (0x2A19) and updates `batteryLevel`.
    func readBatteryLevel() async -> Int? {
        guard let peripheral, let characteristic = batteryLevelCharacteristic else { return nil }
        let data = await readValue(peripheral, characteristic: characteristic)
        let level = data?.first.map { Int($0) }
        debugLog.log(Self.tag, "battery level read=\(level.map(String.init) ?? "n/a")")
        if let level { batteryLevel = level }
        return level
    }

    private func readValue(_ peripheral: CBPeripheral, characteristic: CBCharacteristic) async -> Data? {
        let characteristicName = CapUuids.shortName(characteristic.uuid)
        let waiter = AsyncWaiter<Data>()
        readWaiters[characteristic.uuid.uuidString] = waiter
        peripheral.readValue(for: characteristic)
        let data = try? await waiter.wait(timeoutSeconds: Self.operationTimeoutSeconds) {
            BleConnectionError("read timeout for \(characteristicName)")
        }
        readWaiters[characteristic.uuid.uuidString] = nil
        return data
    }

    /// Writes one request to NUS RX (the nonisolated `NusTransport` witness;
    /// the work itself runs on the MainActor). Starts with write-with-response;
    /// if the cap or the stack rejects it, retries once without response and
    /// remembers whichever worked for the rest of the connection.
    nonisolated func write(_ bytes: Data) async throws {
        try await writeRequest(bytes)
    }

    private func writeRequest(_ bytes: Data) async throws {
        guard let peripheral, let nusRx else { throw BleConnectionError("not connected") }
        guard bytes.count <= maximumWriteLength else {
            throw BleConnectionError(
                "request of \(bytes.count) B exceeds the negotiated write length \(maximumWriteLength) B; OpenBottle never chunks writes",
            )
        }
        let first = preferredWriteType
        do {
            try await writeOnce(peripheral, characteristic: nusRx, bytes: bytes, type: first)
            return
        } catch {
            let fallback: CBCharacteristicWriteType = first == .withResponse ? .withoutResponse : .withResponse
            debugLog.log(Self.tag, "write with \(Self.writeTypeName(first)) failed (\(error)); retrying with \(Self.writeTypeName(fallback))")
            try await writeOnce(peripheral, characteristic: nusRx, bytes: bytes, type: fallback)
            preferredWriteType = fallback
            debugLog.log(Self.tag, "write type \(Self.writeTypeName(fallback)) works, using it from now on")
        }
    }

    private func writeOnce(
        _ peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        bytes: Data,
        type: CBCharacteristicWriteType,
    ) async throws {
        guard type == .withResponse else {
            // Without a response there is no completion callback; the stack
            // reports failures through the peripheral's didWriteValueFor only
            // for acknowledged writes.
            peripheral.writeValue(bytes, for: characteristic, type: .withoutResponse)
            debugLog.log(Self.tag, "write NUS RX type=\(Self.writeTypeName(type)) len=\(bytes.count) issued")
            return
        }
        let waiter = AsyncWaiter<Void>()
        writeWaiter = waiter
        peripheral.writeValue(bytes, for: characteristic, type: type)
        debugLog.log(Self.tag, "write NUS RX type=\(Self.writeTypeName(type)) len=\(bytes.count) issued")
        do {
            try await waiter.wait(timeoutSeconds: Self.operationTimeoutSeconds) {
                BleConnectionError("write ack timeout")
            }
        } catch {
            writeWaiter = nil
            throw error as? BleConnectionError ?? BleConnectionError("write failed")
        }
        writeWaiter = nil
    }

    func disconnect() {
        if let peripheral {
            debugLog.log(Self.tag, "disconnect \(peripheralIdentifier)")
            central.cancelConnection(peripheral)
        }
        closeQuietly()
        state = .disconnected
    }

    private func closeQuietly() {
        peripheral?.delegate = nil
        peripheral = nil
        nusRx = nil
        nusTx = nil
        batteryLevelCharacteristic = nil
        servicesWaiter?.fail(BleConnectionError("disconnected"))
        characteristicsWaiter?.fail(BleConnectionError("disconnected"))
        for waiter in notificationStateWaiters.values { waiter.fail(BleConnectionError("disconnected")) }
        notificationStateWaiters.removeAll()
        for waiter in readWaiters.values { waiter.fail(BleConnectionError("disconnected")) }
        readWaiters.removeAll()
        writeWaiter?.fail(BleConnectionError("disconnected"))
        writeWaiter = nil
    }

    // MARK: - Delegate events (routed by `CapCentral`)

    func handle(_ event: BleEvent) {
        switch event {
        case .servicesDiscovered(let identifier, let error):
            guard identifier == peripheralIdentifier else { return }
            if let error {
                servicesWaiter?.fail(BleConnectionError("service discovery failed: \(error)"))
            } else {
                servicesWaiter?.complete(())
            }

        case .characteristicsDiscovered(let identifier, let service, let error):
            guard identifier == peripheralIdentifier else { return }
            // Only the service we are currently waiting for completes the waiter.
            if let pending = pendingCharacteristicsService, pending.caseInsensitiveCompare(service) != .orderedSame { return }
            if let error {
                characteristicsWaiter?.fail(BleConnectionError("characteristic discovery failed: \(error)"))
            } else {
                characteristicsWaiter?.complete(())
            }

        case .valueUpdated(let identifier, let characteristic, let value, let error):
            guard identifier == peripheralIdentifier else { return }
            if characteristic == CapUuids.nusTx.uuidString {
                debugLog.log(Self.tag, "notify NUS TX len=\(value.count) hex=\(Hex.encode(value))")
                notificationSink.yield(value)
            } else if characteristic == CapUuids.batteryLevel.uuidString {
                let level = value.first.map { Int($0) }
                if error == nil {
                    debugLog.log(Self.tag, "notify Battery Level=\(level.map(String.init) ?? "n/a")")
                    batteryLevel = level
                }
            } else if let waiter = readWaiters.removeValue(forKey: characteristic) {
                if let error {
                    debugLog.log(Self.tag, "read \(characteristic) failed: \(error)")
                    waiter.fail(BleConnectionError("read failed: \(error)"))
                } else {
                    debugLog.log(Self.tag, "read \(characteristic) len=\(value.count) hex=\(Hex.encode(value))")
                    waiter.complete(value)
                }
            }

        case .notificationStateUpdated(let identifier, let characteristic, let isNotifying, let error):
            guard identifier == peripheralIdentifier else { return }
            if let waiter = notificationStateWaiters.removeValue(forKey: characteristic) {
                if let error {
                    waiter.fail(BleConnectionError("notification state failed: \(error)"))
                } else {
                    waiter.complete(isNotifying)
                }
            }

        case .writeFinished(let identifier, let characteristic, let error):
            guard identifier == peripheralIdentifier, characteristic == CapUuids.nusRx.uuidString else { return }
            if let error {
                writeWaiter?.fail(BleConnectionError("write failed: \(error)"))
            } else {
                writeWaiter?.complete(())
            }

        default:
            break
        }
    }

    func handleDisconnected(identifier: String, error: String?) {
        guard identifier == peripheralIdentifier else { return }
        closeQuietly()
        state = if error == nil || error?.contains("code 0") == true {
            .disconnected
        } else {
            .failed(reason: "disconnected: \(error ?? "unknown")")
        }
    }

    func handleCentralPoweredOff() {
        closeQuietly()
        state = .failed(reason: "Bluetooth was turned off")
    }

    nonisolated static func writeTypeName(_ type: CBCharacteristicWriteType) -> String {
        type == .withResponse ? "withResponse" : "withoutResponse"
    }
}
