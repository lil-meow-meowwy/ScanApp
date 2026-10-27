import Foundation

/// The IPv4 subnet this device is on (usually the Wi-Fi interface, `en0`).
nonisolated struct LocalSubnet: Equatable, Sendable {
    let interfaceName: String
    /// Host byte order.
    let address: UInt32
    /// Host byte order.
    let netmask: UInt32

    var addressString: String { Self.string(from: address) }

    /// Large subnets (e.g. /16) are capped to the /24 around our address to keep the scan fast.
    private var scanMask: UInt32 { max(netmask, 0xFFFF_FF00) }
    private var network: UInt32 { address & scanMask }
    private var broadcast: UInt32 { network | ~scanMask }

    /// Every address to probe, excluding our own.
    var hosts: [UInt32] {
        guard broadcast &- network > 1 else { return [] }
        return ((network + 1)..<broadcast).filter { $0 != address }
    }

    var rangeDescription: String {
        guard broadcast &- network > 1 else { return addressString }
        return "\(Self.string(from: network + 1)) – \(Self.string(from: broadcast - 1))"
    }

    static func string(from address: UInt32) -> String {
        "\((address >> 24) & 0xFF).\((address >> 16) & 0xFF).\((address >> 8) & 0xFF).\(address & 0xFF)"
    }
}

nonisolated struct LANDevice: Identifiable, Equatable, Sendable {
    /// Host byte order.
    let address: UInt32
    var hostname: String?
    var isThisDevice = false

    var id: UInt32 { address }
    var ip: String { LocalSubnet.string(from: address) }
    var displayName: String { hostname ?? ip }

    var details: String? {
        let parts = [hostname == nil ? nil : ip, isThisDevice ? "This device" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
