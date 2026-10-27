import Darwin
import Foundation
import dnssd

/// Finds devices on the local network with a TCP sweep:
/// a device that accepts *or refuses* a connection on any probed port is up.
/// iOS doesn't let apps read MAC addresses, so results are IPs plus mDNS/NetBIOS/DNS names.
nonisolated struct LANScanner {
    func currentSubnet() -> LocalSubnet? {
        LocalSubnetReader.current()
    }

    /// Probes `hosts` in parallel and returns the ones that answered.
    /// Runs on a GCD thread because it blocks in `poll` for up to `timeout`.
    func probe(_ hosts: [UInt32], timeout: TimeInterval = 1) async -> Set<UInt32> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: HostProber.aliveHosts(hosts, timeout: timeout))
            }
        }
    }

    /// Asks the device itself first, in parallel:
    /// - mDNS/Bonjour: Apple devices, Linux, printers, TVs
    /// - NetBIOS: Windows PCs and Samba/NAS boxes
    /// then falls back to the router's DNS.
    func hostname(for address: UInt32) async -> String? {
        async let multicast = MulticastReverseLookup.name(for: address, timeout: 2)
        async let netBIOS = Self.runBlocking { NetBIOSResolver.name(for: address, timeout: 1) }

        if let name = await multicast { return Self.displayName(name) }
        if let name = await netBIOS { return name }
        return await Self.runBlocking { HostnameResolver.name(for: address) }.map(Self.displayName)
    }

    private static func runBlocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: work())
            }
        }
    }

    private static func displayName(_ name: String) -> String {
        var name = name
        if name.hasSuffix(".") { name.removeLast() }
        if name.hasSuffix(".local") { name.removeLast(".local".count) }
        return name
    }
}

// MARK: - Interface

nonisolated private enum LocalSubnetReader {
    static func current() -> LocalSubnet? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        var fallback: LocalSubnet?
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(bitPattern: interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = interface.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let netmask = interface.ifa_netmask
            else { continue }

            let subnet = LocalSubnet(
                interfaceName: String(cString: interface.ifa_name),
                address: ipv4(address),
                netmask: ipv4(netmask)
            )
            // en0 is Wi-Fi on iPhone and on most Macs.
            if subnet.interfaceName == "en0" { return subnet }
            if fallback == nil, subnet.interfaceName.hasPrefix("en") { fallback = subnet }
        }
        return fallback
    }

    private static func ipv4(_ address: UnsafeMutablePointer<sockaddr>) -> UInt32 {
        address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
        }
    }
}

// MARK: - Probing

nonisolated private enum HostProber {
    /// SSH, HTTP, HTTPS, SMB, and 62078 (open on iPhones/iPads).
    static let ports: [UInt16] = [22, 80, 443, 445, 62078]

    static func aliveHosts(_ hosts: [UInt32], timeout: TimeInterval) -> Set<UInt32> {
        var alive = Set<UInt32>()
        var pending: [Int32: UInt32] = [:] // socket -> host
        defer { for fd in pending.keys { close(fd) } }

        for host in hosts {
            for port in ports {
                let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
                guard fd >= 0 else { continue }
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = port.bigEndian
                address.sin_addr.s_addr = host.bigEndian

                let result = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                let error = errno

                if result == 0 || error == ECONNREFUSED {
                    alive.insert(host)
                    close(fd)
                } else if error == EINPROGRESS {
                    pending[fd] = host
                } else {
                    close(fd)
                }
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        while !pending.isEmpty {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }

            var fds = pending.keys.map { pollfd(fd: $0, events: Int16(POLLOUT), revents: 0) }
            let ready = poll(&fds, nfds_t(fds.count), Int32(remaining * 1000))
            if ready < 0, errno == EINTR { continue }
            guard ready > 0 else { break }

            for entry in fds where entry.revents != 0 {
                guard let host = pending.removeValue(forKey: entry.fd) else { continue }
                var socketError: Int32 = 0
                var length = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(entry.fd, SOL_SOCKET, SO_ERROR, &socketError, &length)
                // Connected, or actively refused (RST): either way something is there.
                if socketError == 0 || socketError == ECONNREFUSED {
                    alive.insert(host)
                }
                close(entry.fd)
            }
        }
        return alive
    }
}

// MARK: - Names

nonisolated private enum HostnameResolver {
    static func name(for host: UInt32) -> String? {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = host.bigEndian

        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size),
                            &buffer, socklen_t(buffer.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard result == 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
}

/// NetBIOS Node Status request (UDP 137). Windows answers with its computer name.
nonisolated private enum NetBIOSResolver {
    static func name(for host: UInt32, timeout: TimeInterval) -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(137).bigEndian
        address.sin_addr.s_addr = host.bigEndian

        let id = UInt16.random(in: 1...UInt16.max)
        let request = nodeStatusRequest(id: id)
        let sent = request.withUnsafeBytes { bytes in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == request.count else { return nil }

        var entry = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&entry, 1, Int32(timeout * 1000)) > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: 1024)
        let received = recv(fd, &buffer, buffer.count, 0)
        guard received > 0 else { return nil }
        return parseNodeStatus(Array(buffer[0..<received]), id: id)
    }

    private static func nodeStatusRequest(id: UInt16) -> [UInt8] {
        // Header: id, flags 0, 1 question, no other records.
        var packet: [UInt8] = [UInt8(id >> 8), UInt8(id & 0xFF), 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]
        // Name "*" padded to 16 bytes, NetBIOS-encoded (each nibble + 'A'): "CK" + 30 x "A".
        packet.append(0x20)
        packet += Array("CK".utf8) + Array(repeating: UInt8(ascii: "A"), count: 30)
        packet.append(0)
        // Type NBSTAT (0x21), class IN.
        packet += [0x00, 0x21, 0x00, 0x01]
        return packet
    }

    /// Returns the first unique (non-group) name with suffix 0x00: the workstation name.
    private static func parseNodeStatus(_ bytes: [UInt8], id: UInt16) -> String? {
        guard bytes.count > 12, bytes[0] == UInt8(id >> 8), bytes[1] == UInt8(id & 0xFF) else { return nil }

        // Skip the answer's name: either a compression pointer or length-prefixed labels.
        var offset = 12
        if bytes[offset] & 0xC0 == 0xC0 {
            offset += 2
        } else {
            while offset < bytes.count, bytes[offset] != 0 { offset += Int(bytes[offset]) + 1 }
            offset += 1
        }
        offset += 10 // type, class, TTL, data length
        guard offset < bytes.count else { return nil }

        let count = Int(bytes[offset])
        offset += 1
        // Each entry: 15-byte name, 1-byte suffix, 2-byte flags.
        for _ in 0..<count {
            guard offset + 18 <= bytes.count else { break }
            let suffix = bytes[offset + 15]
            let isGroup = bytes[offset + 16] & 0x80 != 0
            if suffix == 0x00, !isGroup {
                let name = String(decoding: bytes[offset..<(offset + 15)], as: UTF8.self)
                    .trimmingCharacters(in: .whitespaces.union(.controlCharacters))
                if !name.isEmpty { return name }
            }
            offset += 18
        }
        return nil
    }
}

/// Reverse lookup (`4.3.2.1.in-addr.arpa` PTR) sent as multicast DNS through the system's
/// mDNSResponder, so devices on the network answer with their own names.
nonisolated private final class MulticastReverseLookup: @unchecked Sendable {
    // Everything below is only touched on `queue`.
    private let queue = DispatchQueue(label: "ScanApp.MulticastReverseLookup")
    private var serviceRef: DNSServiceRef?
    private var continuation: CheckedContinuation<String?, Never>?

    static func name(for address: UInt32, timeout: TimeInterval) async -> String? {
        let lookup = MulticastReverseLookup()
        return await withCheckedContinuation { continuation in
            lookup.start(address: address, timeout: timeout, continuation: continuation)
        }
    }

    private func start(address: UInt32, timeout: TimeInterval, continuation: CheckedContinuation<String?, Never>) {
        queue.async { [self] in
            self.continuation = continuation
            let query = "\(address & 0xFF).\((address >> 8) & 0xFF).\((address >> 16) & 0xFF).\(address >> 24).in-addr.arpa."

            // Balanced by the release in `finish` once the query is torn down.
            let context = Unmanaged.passRetained(self).toOpaque()
            var ref: DNSServiceRef?
            let error = DNSServiceQueryRecord(
                &ref,
                DNSServiceFlags(kDNSServiceFlagsForceMulticast),
                0, // any interface
                query,
                UInt16(kDNSServiceType_PTR),
                UInt16(kDNSServiceClass_IN),
                { _, _, _, errorCode, _, _, _, length, data, _, context in
                    guard let context else { return }
                    let lookup = Unmanaged<MulticastReverseLookup>.fromOpaque(context).takeUnretainedValue()
                    guard errorCode == DNSServiceErrorType(kDNSServiceErr_NoError), let data else { return }
                    lookup.finish(MulticastReverseLookup.parseName(data, length: Int(length)))
                },
                context
            )
            guard error == DNSServiceErrorType(kDNSServiceErr_NoError), let ref else {
                Unmanaged<MulticastReverseLookup>.fromOpaque(context).release()
                finish(nil)
                return
            }
            serviceRef = ref
            // Callbacks are delivered on `queue`, same as `finish` and the timeout.
            DNSServiceSetDispatchQueue(ref, queue)
            queue.asyncAfter(deadline: .now() + timeout) { [self] in finish(nil) }
        }
    }

    /// Resumes the caller exactly once and stops the query. Runs on `queue`.
    private func finish(_ name: String?) {
        guard let continuation else { return }
        self.continuation = nil
        if let serviceRef {
            DNSServiceRefDeallocate(serviceRef)
            self.serviceRef = nil
            Unmanaged.passUnretained(self).release()
        }
        continuation.resume(returning: name)
    }

    /// PTR record data is a DNS wire-format name: length-prefixed labels ending with 0.
    private static func parseName(_ data: UnsafeRawPointer, length: Int) -> String? {
        let bytes = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: length)
        var labels: [String] = []
        var index = 0
        while index < bytes.count {
            let labelLength = Int(bytes[index])
            index += 1
            if labelLength == 0 { break }
            guard labelLength < 64, index + labelLength <= bytes.count else { return nil }
            labels.append(String(decoding: bytes[index..<(index + labelLength)], as: UTF8.self))
            index += labelLength
        }
        return labels.isEmpty ? nil : labels.joined(separator: ".")
    }
}
