import Darwin
import Foundation
import RupaCore

enum AgentSocketIO {
    static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }

            var offset = 0
            while offset < data.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )
                if written > 0 {
                    offset += written
                } else if written == -1 && errno == EINTR {
                    continue
                } else {
                    throw RupaError(
                        code: .agentConnectionFailed,
                        message: "Failed to write agent data. errno=\(errno)"
                    )
                }
            }
        }
    }

    static func readAll(from descriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
            }

            if readCount > 0 {
                data.append(buffer, count: readCount)
            } else if readCount == 0 {
                return data
            } else if errno == EINTR {
                continue
            } else {
                throw RupaError(
                    code: .agentConnectionFailed,
                    message: "Failed to read agent data. errno=\(errno)"
                )
            }
        }
    }
}
