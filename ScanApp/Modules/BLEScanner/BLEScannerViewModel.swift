import CoreBluetooth
import Observation

@MainActor
@Observable
final class BLEScannerViewModel {
    /// Devices not heard from for this long are dropped from the list.
    static let staleInterval: Duration = .seconds(10)
    /// How often the visible list is pruned and re-sorted.
    static let refreshInterval: Duration = .seconds(1)

    private(set) var devices: [BLEDevice] = []
    private(set) var isScanning = false
    private(set) var errorMessage: String?

    private let service: BLEScannerService
    /// Raw advertisements land here; the UI only sees `devices`, published once per tick.
    private var devicesByID: [UUID: BLEDevice] = [:]
    private var refreshTask: Task<Void, Never>?

    init(service: BLEScannerService = BLEScannerService()) {
        self.service = service
        service.onDiscover = { [weak self] in self?.handle(device: $0) }
        service.onStateChange = { [weak self] in self?.handle(state: $0) }
    }

    func toggleScan() {
        isScanning ? stop() : start()
    }

    func start() {
        devicesByID.removeAll()
        devices = []
        errorMessage = nil
        isScanning = true
        service.startScan()
        startRefreshing()
    }

    func stop() {
        isScanning = false
        service.stopScan()
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                // Exit if cancelled or the view model is gone, so the loop never outlives it.
                guard !Task.isCancelled, let self else { return }
                self.publishDevices()
            }
        }
    }

    private func publishDevices(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-Self.staleInterval.timeInterval)
        devicesByID = devicesByID.filter { $0.value.lastSeen >= cutoff }
        devices = devicesByID.values.sorted {
            // Tie-break on id so equal RSSI values don't swap places every tick.
            $0.rssi != $1.rssi ? $0.rssi > $1.rssi : $0.id.uuidString < $1.id.uuidString
        }
    }

    private func handle(device: BLEDevice) {
        let isNew = devicesByID[device.id] == nil
        devicesByID[device.id] = device
        // Show brand-new devices right away; updates to known ones wait for the next tick.
        if isNew { publishDevices() }
    }

    private func handle(state: CBManagerState) {
        switch state {
        case .poweredOn: errorMessage = nil
        case .poweredOff: errorMessage = "Bluetooth is turned off."
        case .unauthorized: errorMessage = "Bluetooth access denied. Enable it in Settings."
        case .unsupported: errorMessage = "Bluetooth LE is not supported on this device."
        default: return
        }
        if state != .poweredOn { stop() }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
