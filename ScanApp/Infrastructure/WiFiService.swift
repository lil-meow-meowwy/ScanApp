#if os(macOS)
import CoreWLAN
import Foundation

nonisolated enum WiFiServiceError: LocalizedError {
    case noWiFiInterface

    var errorDescription: String? {
        switch self {
        case .noWiFiInterface: "This Mac has no Wi-Fi interface."
        }
    }
}

/// Scans for nearby Wi-Fi networks with CoreWLAN.
/// Needs location permission, otherwise SSIDs and BSSIDs come back as `nil`.
/// iOS has no public API for this, so the service only exists in the macOS build.
struct WiFiService {
    func scan() async throws -> WiFiScanResult {
        // `scanForNetworks` blocks for a few seconds, so keep it off the main actor.
        try await Task.detached(priority: .userInitiated) {
            try Self.scanWithCoreWLAN()
        }.value
    }

    nonisolated private static func scanWithCoreWLAN() throws -> WiFiScanResult {
        guard let interface = CWWiFiClient.shared().interface() else {
            throw WiFiServiceError.noWiFiInterface
        }

        var current: WiFiNetwork?
        if interface.ssid() != nil || interface.bssid() != nil {
            current = WiFiNetwork(
                ssid: interface.ssid(),
                bssid: interface.bssid(),
                isSecure: interface.security() != .none,
                rssi: interface.rssiValue(),
                channel: interface.wlanChannel()?.channelNumber
            )
        }

        let nearby = try interface.scanForNetworks(withSSID: nil)
            .map { network in
                WiFiNetwork(
                    ssid: network.ssid,
                    bssid: network.bssid,
                    isSecure: !network.supportsSecurity(.none),
                    rssi: network.rssiValue,
                    channel: network.wlanChannel?.channelNumber
                )
            }
            .filter { $0.id != current?.id }
            .sorted { ($0.rssi ?? .min) > ($1.rssi ?? .min) }

        return WiFiScanResult(current: current, nearby: nearby)
    }
}
#endif
