import SwiftUI

struct NetworkDevicesView: View {
    @State private var viewModel = NetworkDevicesViewModel()

    var body: some View {
        NavigationStack {
            List {
                if let subnet = viewModel.subnet {
                    Section {
                        LabeledContent("Your IP", value: subnet.addressString)
                        LabeledContent("Range", value: subnet.rangeDescription)
                        if case .scanning(let progress) = viewModel.state {
                            ProgressView(value: progress) {
                                Text("Scanning for devices on this network…")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !viewModel.devices.isEmpty {
                    Section {
                        ForEach(viewModel.devices) { device in
                            DeviceRow(title: device.displayName, subtitle: device.details)
                        }
                    } header: {
                        Text("Devices (\(viewModel.devices.count))")
                    } footer: {
                        if viewModel.state == .finished, viewModel.devices.count <= 1 {
                            Text(Self.nothingFoundHint)
                        }
                    }
                }
            }
            .overlay {
                if viewModel.state == .notConnected {
                    ContentUnavailableView("No local network", systemImage: "wifi.slash",
                                           description: Text("Connect to Wi-Fi and scan again."))
                }
            }
            .navigationTitle("Network")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        if viewModel.isScanning { ProgressView().controlSize(.small) }
                        Button(viewModel.isScanning ? "Stop" : "Scan") { viewModel.toggleScan() }
                    }
                }
            }
            .task {
                if viewModel.state == .idle { viewModel.start() }
            }
        }
    }

    #if os(iOS)
    private static let nothingFoundHint = "No other devices responded. If you denied Local Network access, enable it in Settings → Privacy & Security → Local Network, then scan again."
    #else
    private static let nothingFoundHint = "No other devices responded. Check Local Network access in System Settings → Privacy & Security, then scan again."
    #endif
}

#Preview {
    NetworkDevicesView()
}
