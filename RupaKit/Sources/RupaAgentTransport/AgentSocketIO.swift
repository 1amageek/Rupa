import Darwin
import Foundation
import RupaCoreTypes

enum AgentSocketIO {
    static let maximumFrameByteCount = 16 * 1024 * 1024
    private static let headerByteCount = MemoryLayout<UInt64>.size
    private static let cancellationPollingMilliseconds: Int32 = 50
    private static let asynchronousReadinessDelay = Duration.milliseconds(5)

    static func configure(_ descriptor: Int32) throws {
        var enabled: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout.size(ofValue: enabled))
        ) == 0 else {
            throw socketError(
                code: .agentConnectionFailed,
                operation: "configure agent socket"
            )
        }

        let existingFlags = fcntl(descriptor, F_GETFL)
        guard existingFlags >= 0,
              fcntl(descriptor, F_SETFL, existingFlags | O_NONBLOCK) == 0 else {
            throw socketError(
                code: .agentConnectionFailed,
                operation: "configure nonblocking agent socket I/O"
            )
        }
    }

    static func writeFrame(
        _ data: Data,
        to descriptor: Int32,
        deadline: AgentSocketDeadline
    ) throws {
        guard data.count <= maximumFrameByteCount else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent frame exceeds the \(maximumFrameByteCount)-byte limit."
            )
        }
        let length = UInt64(data.count)
        let header = Data([
            UInt8(truncatingIfNeeded: length >> 56),
            UInt8(truncatingIfNeeded: length >> 48),
            UInt8(truncatingIfNeeded: length >> 40),
            UInt8(truncatingIfNeeded: length >> 32),
            UInt8(truncatingIfNeeded: length >> 24),
            UInt8(truncatingIfNeeded: length >> 16),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: length),
        ])
        try writeAll(header, to: descriptor, deadline: deadline)
        try writeAll(data, to: descriptor, deadline: deadline)
    }

    static func readFrame(
        from descriptor: Int32,
        deadline: AgentSocketDeadline
    ) throws -> Data {
        let header = try readExactly(
            headerByteCount,
            from: descriptor,
            deadline: deadline
        )
        var length: UInt64 = 0
        for byte in header {
            length = (length << 8) | UInt64(byte)
        }
        guard length <= UInt64(maximumFrameByteCount),
              let payloadByteCount = Int(exactly: length) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent frame length is invalid or exceeds the configured limit."
            )
        }
        return try readExactly(
            payloadByteCount,
            from: descriptor,
            deadline: deadline
        )
    }

    static func writeFrameAsynchronously(
        _ data: Data,
        to descriptor: Int32,
        deadline: AgentSocketDeadline
    ) async throws {
        guard data.count <= maximumFrameByteCount else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent frame exceeds the \(maximumFrameByteCount)-byte limit."
            )
        }
        let length = UInt64(data.count)
        let header = Data([
            UInt8(truncatingIfNeeded: length >> 56),
            UInt8(truncatingIfNeeded: length >> 48),
            UInt8(truncatingIfNeeded: length >> 40),
            UInt8(truncatingIfNeeded: length >> 32),
            UInt8(truncatingIfNeeded: length >> 24),
            UInt8(truncatingIfNeeded: length >> 16),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: length),
        ])
        try await writeAllAsynchronously(
            header,
            to: descriptor,
            deadline: deadline
        )
        try await writeAllAsynchronously(
            data,
            to: descriptor,
            deadline: deadline
        )
    }

    static func readFrameAsynchronously(
        from descriptor: Int32,
        deadline: AgentSocketDeadline
    ) async throws -> Data {
        let header = try await readExactlyAsynchronously(
            headerByteCount,
            from: descriptor,
            deadline: deadline
        )
        var length: UInt64 = 0
        for byte in header {
            length = (length << 8) | UInt64(byte)
        }
        guard length <= UInt64(maximumFrameByteCount),
              let payloadByteCount = Int(exactly: length) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Agent frame length is invalid or exceeds the configured limit."
            )
        }
        return try await readExactlyAsynchronously(
            payloadByteCount,
            from: descriptor,
            deadline: deadline
        )
    }

    private static func writeAll(
        _ data: Data,
        to descriptor: Int32,
        deadline: AgentSocketDeadline
    ) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }
            var offset = 0
            while offset < data.count {
                try wait(
                    for: Int16(POLLOUT),
                    on: descriptor,
                    deadline: deadline
                )
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
                    throw socketError(
                        code: .agentConnectionFailed,
                        operation: "write agent frame"
                    )
                }
            }
        }
    }

    private static func readExactly(
        _ byteCount: Int,
        from descriptor: Int32,
        deadline: AgentSocketDeadline
    ) throws -> Data {
        guard byteCount > 0 else {
            return Data()
        }
        var data = Data()
        data.reserveCapacity(byteCount)
        var buffer = [UInt8](repeating: 0, count: min(4096, byteCount))
        while data.count < byteCount {
            try wait(
                for: Int16(POLLIN),
                on: descriptor,
                deadline: deadline
            )
            let requestedCount = min(buffer.count, byteCount - data.count)
            let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(descriptor, rawBuffer.baseAddress, requestedCount)
            }
            if readCount > 0 {
                data.append(buffer, count: readCount)
            } else if readCount == 0 {
                throw EditorError(
                    code: .agentConnectionFailed,
                    message: "Agent socket closed before the complete frame was received."
                )
            } else if errno == EINTR || errno == EAGAIN {
                continue
            } else {
                throw socketError(
                    code: .agentConnectionFailed,
                    operation: "read agent frame"
                )
            }
        }
        return data
    }

    private static func writeAllAsynchronously(
        _ data: Data,
        to descriptor: Int32,
        deadline: AgentSocketDeadline
    ) async throws {
        var offset = 0
        while offset < data.count {
            try await waitAsynchronously(
                for: Int16(POLLOUT),
                on: descriptor,
                deadline: deadline
            )
            let written = data.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    return 0
                }
                return Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )
            }
            if written > 0 {
                offset += written
            } else if written == -1 && (errno == EINTR || errno == EAGAIN) {
                continue
            } else {
                throw socketError(
                    code: .agentConnectionFailed,
                    operation: "write agent frame"
                )
            }
        }
    }

    private static func readExactlyAsynchronously(
        _ byteCount: Int,
        from descriptor: Int32,
        deadline: AgentSocketDeadline
    ) async throws -> Data {
        guard byteCount > 0 else {
            return Data()
        }
        var data = Data()
        data.reserveCapacity(byteCount)
        var buffer = [UInt8](repeating: 0, count: min(4096, byteCount))
        while data.count < byteCount {
            try await waitAsynchronously(
                for: Int16(POLLIN),
                on: descriptor,
                deadline: deadline
            )
            let requestedCount = min(buffer.count, byteCount - data.count)
            let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(descriptor, rawBuffer.baseAddress, requestedCount)
            }
            if readCount > 0 {
                data.append(buffer, count: readCount)
            } else if readCount == 0 {
                throw EditorError(
                    code: .agentConnectionFailed,
                    message: "Agent socket closed before the complete frame was received."
                )
            } else if errno == EINTR || errno == EAGAIN {
                continue
            } else {
                throw socketError(
                    code: .agentConnectionFailed,
                    operation: "read agent frame"
                )
            }
        }
        return data
    }

    private static func waitAsynchronously(
        for events: Int16,
        on descriptor: Int32,
        deadline: AgentSocketDeadline
    ) async throws {
        while true {
            try Task.checkCancellation()
            let remainingMilliseconds = try deadline.remainingMilliseconds()
            var pollDescriptor = pollfd(
                fd: descriptor,
                events: events,
                revents: 0
            )
            let result = Darwin.poll(&pollDescriptor, 1, 0)
            if result > 0 {
                let terminalEvents = Int16(POLLERR | POLLNVAL)
                guard pollDescriptor.revents & terminalEvents == 0 else {
                    throw EditorError(
                        code: .agentConnectionFailed,
                        message: "Agent socket entered an invalid I/O state."
                    )
                }
                return
            }
            if result == 0 {
                let delay = min(
                    asynchronousReadinessDelay,
                    .milliseconds(Int64(remainingMilliseconds))
                )
                try await Task.sleep(for: delay)
                continue
            }
            if errno != EINTR {
                throw socketError(
                    code: .agentConnectionFailed,
                    operation: "poll agent socket"
                )
            }
        }
    }

    static func wait(
        for events: Int16,
        on descriptor: Int32,
        deadline: AgentSocketDeadline
    ) throws {
        while true {
            let remaining = try deadline.remainingMilliseconds()
            var pollDescriptor = pollfd(
                fd: descriptor,
                events: events,
                revents: 0
            )
            let result = Darwin.poll(
                &pollDescriptor,
                1,
                min(remaining, cancellationPollingMilliseconds)
            )
            if result > 0 {
                let terminalEvents = Int16(POLLERR | POLLNVAL)
                guard pollDescriptor.revents & terminalEvents == 0 else {
                    throw EditorError(
                        code: .agentConnectionFailed,
                        message: "Agent socket entered an invalid I/O state."
                    )
                }
                return
            }
            if result == 0 {
                continue
            }
            if errno != EINTR {
                throw socketError(
                    code: .agentConnectionFailed,
                    operation: "poll agent socket"
                )
            }
        }
    }

    private static func socketError(
        code: EditorError.Code,
        operation: String
    ) -> EditorError {
        EditorError(
            code: code,
            message: "Failed to \(operation). errno=\(errno)"
        )
    }
}
