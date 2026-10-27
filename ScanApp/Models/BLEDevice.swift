import Foundation

struct BLEDevice: Identifiable, Equatable {
    let id: UUID
    let name: String?
    let rssi: Int
    let lastSeen: Date

    var displayName: String { name ?? "Unknown device" }
}
