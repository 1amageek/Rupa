import Darwin
import Foundation

enum AgentHTTPWire {
    static let maximumBodyByteCount = 16 * 1024 * 1024
    static let maximumHeaderByteCount = 64 * 1024
    static let maximumHeaderCount = 64
    private static let readinessPollMilliseconds: Int32 = 50

    struct Message: Sendable {
        enum Kind: Sendable {
            case request
            case response
        }

        let kind: Kind
        let method: String?
        let path: String?
        let status: Int?
        let headers: [String: String]
        let body: Data
    }

    static func makeRequest(
        method: String,
        path: String,
        headers: [String: String],
        body: Data
    ) throws -> Data {
        guard !method.isEmpty, !path.isEmpty,
              !method.contains(where: { $0 == "\r" || $0 == "\n" }),
              !path.contains(where: { $0 == "\r" || $0 == "\n" }) else {
            throw AgentHTTPError.malformedMessage("The HTTP request line is invalid.")
        }
        return try makeMessage(
            firstLine: "\(method) \(path) HTTP/1.1",
            headers: headers,
            body: body
        )
    }

    static func makeResponse(
        status: Int,
        headers: [String: String],
        body: Data
    ) throws -> Data {
        guard (100...599).contains(status) else {
            throw AgentHTTPError.malformedMessage("The HTTP response status is invalid.")
        }
        return try makeMessage(
            firstLine: "HTTP/1.1 \(status) \(reasonPhrase(for: status))",
            headers: headers,
            body: body
        )
    }

    static func readMessage(
        from descriptor: Int32,
        pending: inout Data,
        deadline: AgentHTTPDeadline
    ) throws -> Message {
        let marker = Data([13, 10, 13, 10])
        let headerEnd: Range<Data.Index>
        while true {
            if let range = pending.range(of: marker) {
                guard range.upperBound <= maximumHeaderByteCount else {
                    throw AgentHTTPError.malformedMessage("The HTTP headers exceed the configured limit.")
                }
                headerEnd = range
                break
            }
            guard pending.count < maximumHeaderByteCount else {
                throw AgentHTTPError.malformedMessage("The HTTP headers exceed the configured limit.")
            }
            try readChunk(from: descriptor, into: &pending, deadline: deadline)
        }

        let headerData = pending.subdata(in: pending.startIndex..<headerEnd.lowerBound)
        pending.removeSubrange(pending.startIndex..<headerEnd.upperBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw AgentHTTPError.malformedMessage("The HTTP headers are not valid UTF-8.")
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let firstLine = lines.first, !firstLine.isEmpty else {
            throw AgentHTTPError.malformedMessage("The HTTP start line is missing.")
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                throw AgentHTTPError.malformedMessage("The HTTP header line is invalid.")
            }
            let name = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                .lowercased()
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(where: { $0 == "\r" || $0 == "\n" }),
                  !value.contains(where: { $0 == "\r" || $0 == "\n" }),
                  headers[name] == nil else {
                throw AgentHTTPError.malformedMessage("The HTTP headers contain a duplicate or invalid field.")
            }
            headers[name] = value
            guard headers.count <= maximumHeaderCount else {
                throw AgentHTTPError.malformedMessage("The HTTP header count exceeds the configured limit.")
            }
        }

        guard let contentLengthValue = headers["content-length"],
              let contentLength = parseContentLength(contentLengthValue) else {
            throw AgentHTTPError.missingContentLength
        }
        guard headers["transfer-encoding"] == nil else {
            throw AgentHTTPError.malformedMessage("Transfer-Encoding is not supported.")
        }
        guard contentLength <= maximumBodyByteCount else {
            throw AgentHTTPError.bodyTooLarge(contentLength)
        }
        let body = try readExactly(
            contentLength,
            from: descriptor,
            pending: &pending,
            deadline: deadline
        )

        if firstLine.hasPrefix("HTTP/") {
            let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let status = Int(parts[1]),
                  parts[0] == "HTTP/1.1" else {
                throw AgentHTTPError.malformedMessage("The HTTP response line is invalid.")
            }
            return Message(
                kind: .response,
                method: nil,
                path: nil,
                status: status,
                headers: headers,
                body: body
            )
        }

        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2] == "HTTP/1.1" else {
            throw AgentHTTPError.malformedMessage("The HTTP request line is invalid.")
        }
        return Message(
            kind: .request,
            method: String(parts[0]),
            path: String(parts[1]),
            status: nil,
            headers: headers,
            body: body
        )
    }

    static func configure(_ descriptor: Int32) throws {
        var enabled: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout.size(ofValue: enabled))
        ) == 0 else {
            throw AgentHTTPError.connectionFailed("Failed to configure the agent connection.")
        }
        let existingFlags = fcntl(descriptor, F_GETFL)
        guard existingFlags >= 0,
              fcntl(descriptor, F_SETFL, existingFlags | O_NONBLOCK) == 0 else {
            throw AgentHTTPError.connectionFailed("Failed to configure non-blocking agent I/O.")
        }
    }

    static func isJSONContentType(_ value: String) -> Bool {
        let mediaType = value.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return mediaType == "application/json"
    }

    static func connect(
        to endpoint: AgentHTTPEndpoint,
        deadline: AgentHTTPDeadline
    ) throws -> Int32 {
        let descriptor = try makeConnectionDescriptor()
        do {
            try connect(descriptor, to: endpoint, deadline: deadline)
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func makeConnectionDescriptor() throws -> Int32 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw AgentHTTPError.connectionFailed("Failed to create the agent connection.")
        }
        do {
            try configure(descriptor)
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func connect(
        _ descriptor: Int32,
        to endpoint: AgentHTTPEndpoint,
        deadline: AgentHTTPDeadline
    ) throws {
        try withLoopbackAddress(port: endpoint.port) { address, length in
            let result = Darwin.connect(descriptor, address, length)
            if result != 0 && errno != EISCONN {
                guard errno == EINPROGRESS || errno == EALREADY || errno == EAGAIN else {
                    throw AgentHTTPError.connectionFailed("Failed to connect to the Rupa agent.")
                }
                try wait(for: Int16(POLLOUT), on: descriptor, deadline: deadline)
                var connectionError: Int32 = 0
                var connectionErrorLength = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(
                    descriptor,
                    SOL_SOCKET,
                    SO_ERROR,
                    &connectionError,
                    &connectionErrorLength
                ) == 0, connectionError == 0 else {
                    throw AgentHTTPError.connectionFailed("The Rupa agent connection was refused.")
                }
            }
        }
    }

    static func makeListener(
        requestedPort: UInt16
    ) throws -> (descriptor: Int32, endpoint: AgentHTTPEndpoint) {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw AgentHTTPError.listenerFailed("Failed to create the Rupa agent listener.")
        }
        do {
            try configure(descriptor)
            var reuseAddress: Int32 = 1
            guard setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_REUSEADDR,
                &reuseAddress,
                socklen_t(MemoryLayout.size(ofValue: reuseAddress))
            ) == 0 else {
                throw AgentHTTPError.listenerFailed("Failed to configure the Rupa agent listener.")
            }
            try withLoopbackAddress(port: requestedPort) { address, length in
                guard Darwin.bind(descriptor, address, length) == 0 else {
                    throw AgentHTTPError.listenerFailed("Failed to bind the Rupa agent listener.")
                }
            }
            guard Darwin.listen(descriptor, 32) == 0 else {
                throw AgentHTTPError.listenerFailed("Failed to listen for Rupa agent connections.")
            }
            var address = sockaddr_in()
            var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let result = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.getsockname(descriptor, $0, &addressLength)
                }
            }
            guard result == 0 else {
                throw AgentHTTPError.listenerFailed("Failed to resolve the Rupa agent listener port.")
            }
            let port = UInt16(bigEndian: address.sin_port)
            let endpoint = try AgentHTTPEndpoint(port: port)
            return (descriptor, endpoint)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    static func writeAll(
        _ data: Data,
        to descriptor: Int32,
        deadline: AgentHTTPDeadline
    ) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                try wait(for: Int16(POLLOUT), on: descriptor, deadline: deadline)
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )
                if written > 0 {
                    offset += written
                } else if written == -1 && (errno == EINTR || errno == EAGAIN) {
                    continue
                } else {
                    throw AgentHTTPError.connectionFailed("Failed to write the agent HTTP message.")
                }
            }
        }
    }

    static func wait(
        for events: Int16,
        on descriptor: Int32,
        deadline: AgentHTTPDeadline
    ) throws {
        while true {
            let remaining = try deadline.remainingMilliseconds()
            var pollDescriptor = pollfd(fd: descriptor, events: events, revents: 0)
            let result = Darwin.poll(
                &pollDescriptor,
                1,
                min(remaining, readinessPollMilliseconds)
            )
            if result > 0 {
                let terminalEvents = Int16(POLLERR | POLLNVAL)
                guard pollDescriptor.revents & terminalEvents == 0 else {
                    throw AgentHTTPError.connectionFailed("The agent connection entered an invalid I/O state.")
                }
                return
            }
            if result == 0 { continue }
            guard errno == EINTR else {
                throw AgentHTTPError.connectionFailed("Failed to poll the agent connection.")
            }
        }
    }

    private static func makeMessage(
        firstLine: String,
        headers: [String: String],
        body: Data
    ) throws -> Data {
        guard body.count <= maximumBodyByteCount else {
            throw AgentHTTPError.bodyTooLarge(body.count)
        }
        var bytes = Data(firstLine.utf8)
        bytes.append(contentsOf: [13, 10])
        for (name, value) in headers {
            let lowerName = name.lowercased()
            guard lowerName != "content-length",
                  lowerName != "transfer-encoding",
                  !name.isEmpty,
                  !name.contains(where: { $0 == "\r" || $0 == "\n" }),
                  !value.contains(where: { $0 == "\r" || $0 == "\n" }) else {
                throw AgentHTTPError.malformedMessage("The HTTP header is invalid.")
            }
            bytes.append(contentsOf: Data("\(name): \(value)\r\n".utf8))
        }
        bytes.append(contentsOf: Data("Content-Length: \(body.count)\r\n\r\n".utf8))
        bytes.append(body)
        return bytes
    }

    private static func readChunk(
        from descriptor: Int32,
        into pending: inout Data,
        deadline: AgentHTTPDeadline
    ) throws {
        try wait(for: Int16(POLLIN), on: descriptor, deadline: deadline)
        var chunk = [UInt8](repeating: 0, count: 8 * 1024)
        let count = chunk.withUnsafeMutableBytes { buffer in
            Darwin.read(descriptor, buffer.baseAddress, buffer.count)
        }
        if count > 0 {
            pending.append(contentsOf: chunk.prefix(count))
        } else if count == 0 {
            throw AgentHTTPError.connectionFailed("The agent connection closed before a complete HTTP message.")
        } else if errno != EINTR && errno != EAGAIN {
            throw AgentHTTPError.connectionFailed("Failed to read the agent HTTP message.")
        }
    }

    private static func readExactly(
        _ count: Int,
        from descriptor: Int32,
        pending: inout Data,
        deadline: AgentHTTPDeadline
    ) throws -> Data {
        guard count > 0 else { return Data() }
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            if !pending.isEmpty {
                let amount = min(count - result.count, pending.count)
                result.append(pending.prefix(amount))
                pending.removeSubrange(pending.startIndex..<pending.index(pending.startIndex, offsetBy: amount))
                continue
            }
            try readChunk(from: descriptor, into: &pending, deadline: deadline)
        }
        return result
    }

    private static func parseContentLength(_ value: String) -> Int? {
        guard !value.isEmpty, value.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(value)
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 413: return "Payload Too Large"
        case 503: return "Service Unavailable"
        default: return "Error"
        }
    }

    private static func withLoopbackAddress<Result>(
        port: UInt16,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result
    ) throws -> Result {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(AgentHTTPEndpoint.loopbackHost))
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
}
