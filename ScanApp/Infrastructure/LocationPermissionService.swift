#if os(macOS)
import CoreLocation

/// CoreWLAN only returns Wi-Fi network names when the app has location permission.
final class LocationPermissionService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    /// Everyone waiting for the user's answer. Several callers can pile up
    /// (e.g. `.task` plus pull-to-refresh), and each must be resumed exactly once.
    private var pending: [CheckedContinuation<Bool, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUse() async -> Bool {
        if let granted = Self.decision(for: manager.authorizationStatus) {
            return granted
        }
        return await withCheckedContinuation { continuation in
            pending.append(continuation)
            // Only the first waiter triggers the system prompt.
            if pending.count == 1 {
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let granted = Self.decision(for: manager.authorizationStatus) else { return }
        let waiting = pending
        pending.removeAll()
        waiting.forEach { $0.resume(returning: granted) }
    }

    /// `nil` while the user hasn't decided yet.
    private static func decision(for status: CLAuthorizationStatus) -> Bool? {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways: true
        case .denied, .restricted: false
        case .notDetermined: nil
        @unknown default: false
        }
    }
}
#endif
