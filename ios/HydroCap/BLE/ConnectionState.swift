import Foundation

/// Device Information Service strings read once per connection.
nonisolated struct DeviceInformation: Sendable, Equatable {
    var manufacturer: String?
    var model: String?
    var serial: String?
    var firmwareRevision: String?
    var hardwareRevision: String?
    var softwareRevision: String?

    init(
        manufacturer: String? = nil,
        model: String? = nil,
        serial: String? = nil,
        firmwareRevision: String? = nil,
        hardwareRevision: String? = nil,
        softwareRevision: String? = nil,
    ) {
        self.manufacturer = manufacturer
        self.model = model
        self.serial = serial
        self.firmwareRevision = firmwareRevision
        self.hardwareRevision = hardwareRevision
        self.softwareRevision = softwareRevision
    }

    func describe() -> String {
        "manufacturer=\(manufacturer ?? "?") model=\(model ?? "?") serial=\(serial ?? "?") " +
            "fw=\(firmwareRevision ?? "?") hw=\(hardwareRevision ?? "?") sw=\(softwareRevision ?? "?")"
    }
}

/// Observable GATT lifecycle, surfaced on the Home status line and in the Debug log.
nonisolated enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting(address: String)
    case connected(address: String)
    case configuring(address: String)
    case ready(address: String, maximumWriteLength: Int, info: DeviceInformation)
    case failed(reason: String)

    var isActive: Bool {
        switch self {
        case .connecting, .connected, .configuring, .ready: true
        case .disconnected, .failed: false
        }
    }

    var label: String {
        switch self {
        case .disconnected: "disconnected"
        case .connecting: "connecting"
        case .connected: "connected"
        case .configuring: "configuring"
        case .ready(let address, let maximumWriteLength, _): "ready (\(address), write ≤ \(maximumWriteLength) B)"
        case .failed(let reason): "failed: \(reason)"
        }
    }
}
