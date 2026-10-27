import SwiftUI

struct HomeView: View {
    var body: some View {
        TabView {
            BLEScannerView()
                .tabItem { Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right") }

            WiFiScannerView()
                .tabItem { Label("Wi-Fi", systemImage: "wifi") }

            NetworkDevicesView()
                .tabItem { Label("Network", systemImage: "network") }
        }
    }
}

#Preview {
    HomeView()
}
