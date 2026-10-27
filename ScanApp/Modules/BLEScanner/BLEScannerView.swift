import SwiftUI

struct BLEScannerView: View {
    @State private var viewModel = BLEScannerViewModel()

    var body: some View {
        NavigationStack {
            List(viewModel.devices) { device in
                DeviceRow(title: device.displayName, subtitle: device.id.uuidString, rssi: device.rssi)
            }
            .overlay { emptyState }
            .navigationTitle("Bluetooth")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        if viewModel.isScanning { ProgressView().controlSize(.small) }
                        Button(viewModel.isScanning ? "Stop" : "Scan") { viewModel.toggleScan() }
                    }
                }
            }
            .onDisappear { viewModel.stop() }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let error = viewModel.errorMessage {
            ContentUnavailableView("Unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if viewModel.devices.isEmpty {
            ContentUnavailableView(
                viewModel.isScanning ? "Scanning…" : "No devices",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text(viewModel.isScanning ? "Looking for nearby BLE devices." : "Tap Scan to start.")
            )
        }
    }
}

#Preview {
    BLEScannerView()
}
