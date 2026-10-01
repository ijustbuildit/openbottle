import CoreBluetooth
import Foundation
import Observation

/// Events the nonisolated CoreBluetooth delegate funnels onto the MainActor.
/// Data crosses the boundary as `Sendable` values only; the `CBPeripheral`
/// objects themselves live in `PeripheralRegistry`, never in an event.
nonisolated enum BleEvent: Sendable {
    case centralStateChanged(stateRawValue: Int)
    case willRestore(peripheralIdentifiers: [String])
    case discovered(
        identifier: String,
        name: String?,
        rssi: Int,
        manufacturerData: Data?,
        advertisementServices: [String],
        connectable: Bool,
    )
    case connected(identifier: String, error: String?)
    case disconnected(identifier: String, error: String?)
    case servicesDiscovered(identifier: String, error: String?)
    case characteristicsDiscovered(identifier: String, service: String, error: String?)
    case valueUpdated(identifier: String, characteristic: String, value: Data, error: String?)
    case notificationStateUpdated(identifier: String, characteristic: String, isNotifying: Bool, error: String?)
    case writeFinished(identifier: String, characteristic: String, error: String?)
}

/// Thread-safe hand-off for the routing closure (the delegate is created before
/// `CapCentral` finishes initialising).
nonisolated final class BleEventRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (BleEvent) -> Void)?

    func setHandler(_ handler: @escaping @Sendable (BleEvent) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func send(_ event: BleEvent) {
        lock.lock()
        let handler = handler
        lock.unlock()
        handler?(event)
    }
}

/// `CBPeripheral` handles handed over from the delegate queue to the MainActor.
/// `CBPeripheral` is not `Sendable`, so the reference travels through this
/// lock-protected registry instead of through an event payload.
nonisolated final class PeripheralRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var peripherals: [String: CBPeripheral] = [:]

    func store(_ peripheral: CBPeripheral) {
        lock.lock()
        peripherals[peripheral.identifier.uuidString] = peripheral
        lock.unlock()
    }

    func peripheral(identifier: String) -> CBPeripheral? {
        lock.lock()
        defer { lock.unlock() }
        return peripherals[identifier]
    }

    func remove(identifier: String) {
        lock.lock()
        peripherals.removeValue(forKey: identifier)
        lock.unlock()
    }
}

/// CBCentralManagerDelegate + CBPeripheralDelegate. Everything arrives on the
/// dedicated serial queue (`CapCentral.queueLabel`) and is routed to the
/// MainActor as `BleEvent`s.
nonisolated final class CapBleDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    private let router: BleEventRouter
    private let registry: PeripheralRegistry

    init(router: BleEventRouter, registry: PeripheralRegistry) {
        self.router = router
        self.registry = registry
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        router.send(.centralStateChanged(stateRawValue: central.state.rawValue))
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in peripherals { registry.store(peripheral) }
        router.send(.willRestore(peripheralIdentifiers: peripherals.map { $0.identifier.uuidString }))
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber,
    ) {
        registry.store(peripheral)
        router.send(.discovered(
            identifier: peripheral.identifier.uuidString,
            name: advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            rssi: RSSI.intValue,
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            advertisementServices: (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map { $0.uuidString },
            connectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? true,
        ))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        registry.store(peripheral)
        router.send(.connected(identifier: peripheral.identifier.uuidString, error: nil))
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        router.send(.connected(identifier: peripheral.identifier.uuidString, error: Self.describe(error)))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        router.send(.disconnected(identifier: peripheral.identifier.uuidString, error: Self.describe(error)))
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        router.send(.servicesDiscovered(identifier: peripheral.identifier.uuidString, error: Self.describe(error)))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        router.send(.characteristicsDiscovered(
            identifier: peripheral.identifier.uuidString,
            service: service.uuid.uuidString,
            error: Self.describe(error),
        ))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        router.send(.valueUpdated(
            identifier: peripheral.identifier.uuidString,
            characteristic: characteristic.uuid.uuidString,
            value: characteristic.value ?? Data(),
            error: Self.describe(error),
        ))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        router.send(.notificationStateUpdated(
            identifier: peripheral.identifier.uuidString,
            characteristic: characteristic.uuid.uuidString,
            isNotifying: characteristic.isNotifying,
            error: Self.describe(error),
        ))
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        router.send(.writeFinished(
            identifier: peripheral.identifier.uuidString,
            characteristic: characteristic.uuid.uuidString,
            error: Self.describe(error),
        ))
    }

    private static func describe(_ error: Error?) -> String? {
        guard let error else { return nil }
        let nsError = error as NSError
        return "\(nsError.localizedDescription) (code \(nsError.code))"
    }
}

/// The app's single `CBCentralManager`: state restoration, scanning (foreground
/// with duplicates / background without) and connection bookkeeping. Results are
/// delivered on the MainActor; the delegate callbacks arrive on a dedicated
/// serial queue.
@MainActor
@Observable
final class CapCentral {
    /// Stable restore identifier: iOS relaunches the app into the background
    /// for Bluetooth events and hands the previous central manager back.
    static let restoreIdentifier = "dev.hydrocap.central"
    static let queueLabel = "dev.hydrocap.central.queue"
    nonisolated static let tag = "gatt"

    private(set) var state: CBManagerState = .unknown
    private(set) var discovered: [DiscoveredCap] = []
    private(set) var lastScanError: String?
    private(set) var restoredPeripheralIdentifiers: [String] = []
    private var pendingRestoredCancels: [String] = []
    private var deferredScan: (allowDuplicates: Bool, purpose: String)?

    /// Cancels connections iOS restored for us; safe to call repeatedly
    /// (waits for `.poweredOn`, the only state in which cancel is allowed).
    private func cancelRestoredConnectionsIfReady() {
        guard state == .poweredOn, let central, !pendingRestoredCancels.isEmpty else { return }
        for identifier in pendingRestoredCancels {
            if let peripheral = registry.peripheral(identifier: identifier) {
                debugLog.log(CapCentral.tag, "cancelling restored connection \(identifier) (state \(peripheral.state.rawValue))")
                central.cancelPeripheralConnection(peripheral)
            }
        }
        pendingRestoredCancels = []
    }
    private(set) var isScanning = false

    let debugLog: DebugLog
    private let queue = DispatchQueue(label: CapCentral.queueLabel)
    private let registry = PeripheralRegistry()
    private var delegate: CapBleDelegate?
    private var central: CBCentralManager?
    private var connectWaiter: AsyncWaiter<String>?
    private var pendingConnectIdentifier: String?

    /// The connection that currently owns the (single) peripheral.
    weak var activeConnection: CapConnection?

    /// The single delegate object; `CapConnection` installs it as the
    /// peripheral's delegate so peripheral events keep arriving on the
    /// dedicated serial queue.
    var bleDelegate: CapBleDelegate? { delegate }

    init(debugLog: DebugLog) {
        self.debugLog = debugLog
        let router = BleEventRouter()
        let registry = self.registry
        self.delegate = CapBleDelegate(router: router, registry: registry)
        router.setHandler { [weak self] event in
            guard let controller = self else { return }
            Task { @MainActor in
                controller.handle(event)
            }
        }
    }

    /// Creates the central manager (this is what triggers the Bluetooth
    /// permission prompt) and restores state if iOS relaunched the app.
    func start() {
        guard central == nil, let delegate else { return }
        debugLog.log(
            CapCentral.tag,
            "CBCentralManager(delegate:) restoreIdentifier=\(CapCentral.restoreIdentifier) queue=\(CapCentral.queueLabel)",
        )
        central = CBCentralManager(
            delegate: delegate,
            queue: queue,
            options: [CBCentralManagerOptionRestoreIdentifierKey: CapCentral.restoreIdentifier],
        )
    }

    var isPoweredOn: Bool { state == .poweredOn }

    var stateDescription: String {
        switch state {
        case .unknown: "unknown"
        case .resetting: "resetting"
        case .unsupported: "unsupported"
        case .unauthorized: "unauthorized (Bluetooth permission denied)"
        case .poweredOff: "Bluetooth is turned off"
        case .poweredOn: "ready"
        @unknown default: "state \(state.rawValue)"
        }
    }

    // MARK: - Scanning

    /// `allowDuplicates` is true for the foreground list (live RSSI) and false
    /// for the background service-filtered scan.
    func startScan(allowDuplicates: Bool, purpose: String) {
        start()
        guard let central else {
            lastScanError = "Bluetooth is not available"
            return
        }
        guard state == .poweredOn else {
            if state == .unknown || state == .resetting {
                // Bluetooth is still coming up (typical right after launch):
                // remember the request and start it from the state callback.
                deferredScan = (allowDuplicates, purpose)
                debugLog.log(CapCentral.tag, "scan '\(purpose)' deferred until Bluetooth is ready (\(stateDescription))")
                return
            }
            lastScanError = stateDescription
            debugLog.log(CapCentral.tag, "scan '\(purpose)' refused: \(stateDescription)")
            return
        }
        lastScanError = nil
        discovered = []
        isScanning = true
        debugLog.log(CapCentral.tag, "scan start filters=[service 0x180A] allowDuplicates=\(allowDuplicates) purpose=\(purpose)")
        central.scanForPeripherals(
            withServices: CapUuids.scanServices,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates],
        )
    }

    func stopScan() {
        guard let central, isScanning else { return }
        central.stopScan()
        isScanning = false
        debugLog.log(CapCentral.tag, "scan stop, \(discovered.count) cap(s) seen")
    }

    var discoveredSorted: [DiscoveredCap] {
        discovered.sorted { $0.rssi > $1.rssi }
    }

    // MARK: - Connecting

    /// Connects to the peripheral of a *fresh* scan result. The cap rotates its
    /// address, so the caller must never reuse an identifier from an earlier
    /// session (hardware session 1).
    func connect(identifier: String, timeoutSeconds: Double) async throws -> CBPeripheral {
        guard let central else { throw BleConnectionError("Bluetooth is not available") }
        guard let peripheral = registry.peripheral(identifier: identifier) else {
            throw BleConnectionError("peripheral \(identifier) is not a scan result of this session")
        }
        connectWaiter?.fail(BleConnectionError("another connect is in flight"))
        let waiter = AsyncWaiter<String>()
        connectWaiter = waiter
        pendingConnectIdentifier = identifier
        debugLog.log(
            CapCentral.tag,
            "connect \(identifier) transport=LE (iOS negotiates the ATT MTU itself; write length is read back after connect)",
        )
        central.connect(peripheral, options: nil)
        do {
            _ = try await waiter.wait(timeoutSeconds: timeoutSeconds) {
                BleConnectionError("connect timeout after \(Int(timeoutSeconds)) s")
            }
        } catch {
            central.cancelPeripheralConnection(peripheral)
            connectWaiter = nil
            pendingConnectIdentifier = nil
            throw error
        }
        connectWaiter = nil
        pendingConnectIdentifier = nil
        return peripheral
    }

    func cancelConnection(_ peripheral: CBPeripheral) {
        central?.cancelPeripheralConnection(peripheral)
    }

    func peripheral(identifier: String) -> CBPeripheral? {
        registry.peripheral(identifier: identifier)
    }

    func forget(identifier: String) {
        registry.remove(identifier: identifier)
    }

    /// Called by `CapConnection.connect` so peripheral events reach the session.
    func bind(_ connection: CapConnection) {
        activeConnection = connection
    }

    // MARK: - Delegate routing

    private func handle(_ event: BleEvent) {
        switch event {
        case .centralStateChanged(let rawValue):
            let newState = CBManagerState(rawValue: rawValue) ?? .unknown
            state = newState
            debugLog.log(CapCentral.tag, "central state=\(stateDescription)")
            if newState == .poweredOff { activeConnection?.handleCentralPoweredOff() }
            if newState == .poweredOn {
                cancelRestoredConnectionsIfReady()
                // A scan requested before Bluetooth was ready (app launch) is
                // started now instead of being silently dropped.
                if let deferred = deferredScan {
                    deferredScan = nil
                    startScan(allowDuplicates: deferred.allowDuplicates, purpose: deferred.purpose)
                }
            }

        case .willRestore(let identifiers):
            restoredPeripheralIdentifiers = identifiers
            debugLog.log(CapCentral.tag, "willRestoreState peripherals=\(identifiers.count) from identifier=\(CapCentral.restoreIdentifier)")
            // A restored peripheral is one iOS kept connected (or connecting)
            // on our behalf while the app was gone. HydroCap never keeps a
            // link between jobs, and a cap that is still connected does not
            // advertise — every scan would come back empty. Drop them all;
            // the next job scans and connects fresh.
            pendingRestoredCancels = identifiers
            cancelRestoredConnectionsIfReady()

        case .discovered(let identifier, let name, let rssi, let manufacturerData, let services, let connectable):
            let byName = CapAdvertisementMatcher.matchesName(name)
            let byManufacturer = CapAdvertisementMatcher.matchesManufacturerData(manufacturerData)
            // The service filter (0x180A) already limits the scan. A named
            // result that is clearly not a cap is rejected; a nameless result
            // (possible in background scans, where the scan response may be
            // missing) is kept as a candidate and verified against the DIS
            // serial after connecting.
            let isCandidate = byName || byManufacturer
                || (name == nil && services.contains(CapUuids.deviceInformationService.uuidString))
            guard isCandidate else { return }
            let cap = DiscoveredCap(
                name: name,
                address: identifier,
                rssi: rssi,
                deviceIdHex: DeviceName.decodeDeviceId(name),
                rawAdvertisementHex: manufacturerData.map { Hex.encode($0) },
                matchedByName: byName,
                matchedByManufacturerData: byManufacturer,
                seenAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            )
            if let previous = discovered.firstIndex(where: { $0.address == identifier }) {
                discovered[previous] = cap
            } else {
                discovered.append(cap)
                debugLog.log(
                    CapCentral.tag,
                    "found name=\(cap.name ?? "?") id=\(identifier) rssi=\(rssi) serial=\(cap.deviceIdHex ?? "?") " +
                        "byName=\(byName) byMfg=\(byManufacturer) connectable=\(connectable)",
                )
            }

        case .connected(let identifier, let error):
            guard pendingConnectIdentifier == identifier else { return }
            if let error {
                debugLog.log(CapCentral.tag, "didFailToConnect \(identifier): \(error)")
                connectWaiter?.fail(BleConnectionError("connect failed: \(error)"))
            } else {
                debugLog.log(CapCentral.tag, "didConnect \(identifier)")
                connectWaiter?.complete(identifier)
            }

        case .disconnected(let identifier, let error):
            debugLog.log(CapCentral.tag, "didDisconnectPeripheral \(identifier)\(error.map { " error: \($0)" } ?? "")")
            if pendingConnectIdentifier == identifier {
                connectWaiter?.fail(BleConnectionError(error ?? "disconnected during connect"))
            }
            activeConnection?.handleDisconnected(identifier: identifier, error: error)

        default:
            activeConnection?.handle(event)
        }
    }
}
