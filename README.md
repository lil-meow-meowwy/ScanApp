# ScanApp

A SwiftUI app for iPhone and Mac that finds what's around you: nearby Bluetooth devices, Wi-Fi networks, and other devices on your local network.

## Features

| Tab | What it does | Platforms |
|-----|--------------|-----------|
| **Bluetooth** | Live scan of nearby Bluetooth Low Energy devices, showing name, identifier and signal strength. Devices not heard from for 10 seconds drop off the list. | iOS, macOS |
| **Wi-Fi** | Shows the network you're on and the networks in range, with BSSID, channel, security and signal strength (via CoreWLAN). | macOS only |
| **Network** | Scans your local subnet for devices and shows each one's IP and hostname. | iOS, macOS |

iOS has no public API for scanning Wi-Fi networks, so on iPhone the Wi-Fi tab only shows a short explanation.

### How the network scan works

- Reads your Wi-Fi interface's IPv4 address and subnet mask. Large subnets are capped to the /24 around your address so the scan stays fast.
- Probes each host on TCP ports 22, 80, 443, 445 and 62078, 32 hosts at a time. A host that accepts *or refuses* a connection counts as up.
- Looks up names using mDNS/Bonjour first, then NetBIOS, then the router's reverse DNS.
- MAC addresses aren't available to apps on iOS, so results show IPs and hostnames only.

## Requirements

- Xcode 27 or later
- iOS 27 / macOS 27 deployment target
- A physical device for Bluetooth and network scanning (the Simulator has no Bluetooth radio)

## Getting started

1. Open `ScanApp.xcodeproj` in Xcode.
2. Under **Signing & Capabilities**, choose your own development team and, if needed, change the bundle identifier.
3. Pick an iPhone or "My Mac" as the run destination and press **Run**.

## Permissions

The app asks for these at runtime:

| Permission | Why |
|------------|-----|
| Bluetooth | To find nearby BLE devices |
| Local Network | To scan for devices on your Wi-Fi |
| Location (macOS) | macOS only shows Wi-Fi network names to apps with location access |

On macOS, the app sandbox has Bluetooth, location, and incoming and outgoing network access turned on.

## Project structure

ScanApp/
├── ScannerApp.swift        # App entry point
├── Components/             # Reusable views (DeviceRow, SignalBarsView)
├── Models/                 # BLEDevice, WiFiNetwork, LANDevice / LocalSubnet
├── Infrastructure/         # System-facing services
│   ├── BLEScannerService.swift          # CoreBluetooth wrapper
│   ├── WiFiService.swift                # CoreWLAN scan (macOS)
│   ├── LocationPermissionService.swift  # Location prompt (macOS)
│   └── LANScanner.swift                 # TCP sweep + hostname lookup
└── Modules/                # One folder per screen (View + ViewModel)
    ├── Home/
    ├── BLEScanner/
    ├── WiFiScanner/
    └── NetworkDevices/

Each screen follows MVVM: an `@Observable` view model running on the main actor wraps one infrastructure service, and its SwiftUI view renders the result.
