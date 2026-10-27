#if os(macOS)
import Foundation

nonisolated struct WiFiNetwork: Identifiable, Equatable, Sendable {
    /// `nil` for hidden networks, or when location permission is missing.
    let ssid: String?
    let bssid: String?
    let isSecure: Bool
    var rssi: Int?
    var channel: Int?

    var id: String { bssid ?? "\(ssid ?? "hidden")-\(channel ?? 0)" }
    var displayName: String { ssid ?? "Hidden network" }

    var details: String {
        [bssid, channel.map { "ch \($0)" }, isSecure ? "Secured" : "Open"]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

nonisolated struct WiFiScanResult: Equatable, Sendable {
    /// The network this device is connected to.
    var current: WiFiNetwork?
    /// Networks in range.
    var nearby: [WiFiNetwork] = []
}
#endif
