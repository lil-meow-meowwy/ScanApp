import CoreBluetooth

/// Thin wrapper around CBCentralManager. All callbacks are delivered on the main queue.
final class BLEScannerService: NSObject {
    var onStateChange: (@MainActor (CBManagerState) -> Void)?
    var onDiscover: (@MainActor (BLEDevice) -> Void)?

    private var central: CBCentralManager?
    private var wantsToScan = false

    func startScan() {
        wantsToScan = true
        guard let central else {
            // Creating the manager triggers the Bluetooth permission prompt.
            // Scanning starts in `centralManagerDidUpdateState` once powered on.
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        if central.state == .poweredOn { scan() }
    }

    func stopScan() {
        wantsToScan = false
        central?.stopScan()
    }

    private func scan() {
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }
}

extension BLEScannerService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, wantsToScan { scan() }
        let state = central.state
        MainActor.assumeIsolated { onStateChange?(state) }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let device = BLEDevice(
            id: peripheral.identifier,
            name: peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
            rssi: RSSI.intValue,
            lastSeen: .now
        )
        MainActor.assumeIsolated { onDiscover?(device) }
    }
}
