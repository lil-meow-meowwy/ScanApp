import SwiftUI

struct SignalBarsView: View {
    let rssi: Int

    private var level: Int {
        switch rssi {
        case (-60)...: 4
        case (-70)...: 3
        case (-80)...: 2
        case (-90)...: 1
        default: 0
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...4, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= level ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(bar) * 4)
            }
        }
        .accessibilityLabel("Signal \(level) of 4")
    }
}
