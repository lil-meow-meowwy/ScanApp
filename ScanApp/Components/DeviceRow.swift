import SwiftUI

struct DeviceRow: View {
    let title: String
    var subtitle: String?
    var rssi: Int?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let rssi {
                SignalBarsView(rssi: rssi)
                Text("\(rssi)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
        }
    }
}

#Preview {
    List {
        DeviceRow(title: "AirPods", subtitle: UUID().uuidString, rssi: -52)
        DeviceRow(title: "Home Wi-Fi", subtitle: "aa:bb:cc:dd:ee:ff")
    }
}
