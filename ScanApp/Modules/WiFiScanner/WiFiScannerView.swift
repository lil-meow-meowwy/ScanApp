import SwiftUI

struct WiFiScannerView: View {
    var body: some View {
        NavigationStack {
            #if os(macOS)
            WiFiScanList()
            #else
            ContentUnavailableView(
                "Wi-Fi scan unavailable",
                systemImage: "wifi.exclamationmark",
                description: Text("iOS doesn't allow apps to scan for nearby Wi-Fi networks.")
            )
            .navigationTitle("Wi-Fi")
            #endif
        }
    }
}

#if os(macOS)
/// CoreWLAN-backed scanner. Only built for macOS.
private struct WiFiScanList: View {
    @State private var viewModel = WiFiScannerViewModel()

    var body: some View {
        List {
            if case .loaded(let result) = viewModel.state {
                if let network = result.current {
                    Section("Current network") {
                        DeviceRow(title: network.displayName, subtitle: network.details, rssi: network.rssi)
                    }
                }
                if !result.nearby.isEmpty {
                    Section("Nearby networks (\(result.nearby.count))") {
                        ForEach(result.nearby) { network in
                            DeviceRow(title: network.displayName, subtitle: network.details, rssi: network.rssi)
                        }
                    }
                }
            }
        }
        .overlay { emptyState }
        .navigationTitle("Wi-Fi")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Scan") { Task { await viewModel.refresh() } }
                    .disabled(viewModel.state == .loading)
            }
        }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.refresh() }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .loading:
            VStack(spacing: 8) {
                ProgressView()
                Text("Scanning for nearby Wi-Fi networks…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .loaded(let result) where result.current == nil && result.nearby.isEmpty:
            ContentUnavailableView("No networks found", systemImage: "wifi.slash",
                                   description: Text("Make sure Wi-Fi is on and scan again."))
        case .loaded:
            EmptyView()
        case .permissionDenied:
            ContentUnavailableView("Location required", systemImage: "location.slash",
                                   description: Text("Location access is needed to read Wi-Fi network names. Enable it in Settings."))
        case .failed(let message):
            ContentUnavailableView("Scan failed", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        }
    }
}
#endif

#Preview {
    WiFiScannerView()
}
