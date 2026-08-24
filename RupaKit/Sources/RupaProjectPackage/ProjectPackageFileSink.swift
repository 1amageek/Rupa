import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

struct ProjectPackageFileSink: ProjectPackageByteSink {
    private let fileDescriptor: Int32
    private(set) var writtenByteCount: UInt64 = 0
    private(set) var maximumWrittenChunkByteCount = 0

    init(fileHandle: FileHandle) {
        fileDescriptor = fileHandle.fileDescriptor
    }

    mutating func write(_ bytes: borrowing Span<UInt8>) throws {
        guard bytes.count > 0 else {
            return
        }
        do {
            try bytes.withUnsafeBytes { rawBytes in
                // FileHandle retains ownership of the descriptor and closes it exactly
                // once in ProjectPackageStore. The borrowed pointer is valid only for
                // this synchronous loop, never escapes, and each offset stays in range.
                guard let baseAddress = rawBytes.baseAddress else {
                    return
                }
                var offset = 0
                while offset < rawBytes.count {
                    let result = systemWrite(
                        fileDescriptor,
                        baseAddress.advanced(by: offset),
                        rawBytes.count - offset
                    )
                    if result < 0, systemWriteWasInterrupted() {
                        continue
                    }
                    guard result > 0 else {
                        throw ProjectPackageError(
                            code: .ioFailure,
                            message: "Project package file write failed."
                        )
                    }
                    offset += result
                }
            }
        } catch let error as ProjectPackageError {
            throw error
        } catch {
            throw ProjectPackageError(
                code: .ioFailure,
                message: "Project package file write failed: \(error)."
            )
        }
        let addition = writtenByteCount.addingReportingOverflow(UInt64(bytes.count))
        guard !addition.overflow else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project package output size overflowed UInt64."
            )
        }
        writtenByteCount = addition.partialValue
        maximumWrittenChunkByteCount = max(maximumWrittenChunkByteCount, bytes.count)
    }

    private func systemWrite(
        _ descriptor: Int32,
        _ bytes: UnsafeRawPointer,
        _ count: Int
    ) -> Int {
        #if canImport(Darwin)
        Darwin.write(descriptor, bytes, count)
        #elseif canImport(Glibc)
        Glibc.write(descriptor, bytes, count)
        #elseif canImport(WASILibc)
        WASILibc.write(descriptor, bytes, count)
        #else
        -1
        #endif
    }

    private func systemWriteWasInterrupted() -> Bool {
        #if canImport(Darwin)
        Darwin.errno == Darwin.EINTR
        #elseif canImport(Glibc)
        Glibc.errno == Glibc.EINTR
        #elseif canImport(WASILibc)
        WASILibc.errno == WASILibc.EINTR
        #else
        false
        #endif
    }
}
