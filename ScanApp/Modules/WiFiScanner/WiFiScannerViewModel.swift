#if os(macOS)
import Observation
import Foundation

@MainActor
@Observable
final class WiFiScannerViewModel {
    enum State: Equatable {
        case idle
        case loading
        case loaded(WiFiScanResult)
        case permissionDenied
        case failed(String)
    }

    private(set) var state: State = .idle

    private let wifiService: WiFiService
    private let locationService: LocationPermissionService

    init(
        wifiService: WiFiService = WiFiService(),
        locationService: LocationPermissionService = LocationPermissionService()
    ) {
        self.wifiService = wifiService
        self.locationService = locationService
    }

    func refresh() async {
        state = .loading
        guard await locationService.requestWhenInUse() else {
            state = .permissionDenied
            return
        }
        do {
            state = .loaded(try await wifiService.scan())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
#endif
