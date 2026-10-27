import Foundation
import Observation

@MainActor
@Observable
final class NetworkDevicesViewModel {
    enum State: Equatable {
        case idle
        case scanning(progress: Double)
        case finished
        case notConnected
    }

    /// Hosts probed at once. Each uses one socket per port, so keep it well under the fd limit (256).
    static let batchSize = 32

    private(set) var state: State = .idle
    private(set) var subnet: LocalSubnet?
    private(set) var devices: [LANDevice] = []

    private let scanner: LANScanner
    private var scanTask: Task<Void, Never>?

    init(scanner: LANScanner = LANScanner()) {
        self.scanner = scanner
    }

    var isScanning: Bool {
        switch state {
        case .scanning: true
        default: false
        }
    }

    func toggleScan() {
        isScanning ? stop() : start()
    }

    func start() {
        scanTask?.cancel()
        scanTask = Task { await scan() }
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        if isScanning { state = .finished }
    }

    private func scan() async {
        guard let subnet = scanner.currentSubnet() else {
            self.subnet = nil
            devices = []
            state = .notConnected
            return
        }
        self.subnet = subnet
        devices = []
        add(subnet.address, isThisDevice: true)

        let hosts = subnet.hosts
        state = .scanning(progress: 0)

        for start in stride(from: 0, to: hosts.count, by: Self.batchSize) {
            let batch = Array(hosts[start..<min(start + Self.batchSize, hosts.count)])
            let alive = await scanner.probe(batch)
            guard !Task.isCancelled else { return }

            alive.sorted().forEach { add($0) }
            state = .scanning(progress: Double(start + batch.count) / Double(hosts.count))
        }
        state = .finished
    }

    private func add(_ address: UInt32, isThisDevice: Bool = false) {
        guard !devices.contains(where: { $0.address == address }) else { return }
        devices.append(LANDevice(address: address, isThisDevice: isThisDevice))
        devices.sort { $0.address < $1.address }

        // Names arrive later and fill in as they resolve, without slowing the sweep.
        Task {
            guard let name = await scanner.hostname(for: address),
                  let index = devices.firstIndex(where: { $0.address == address })
            else { return }
            devices[index].hostname = name
        }
    }
}
