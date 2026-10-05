import Foundation
import Synchronization
import SwiftCAD

/// Owns Native output storage; append admission runs outside the short storage lock.
final class DrawingPageByteSink: ByteSink, Sendable {
    private let storage = Mutex(Data())
    private let consumeBytes: @Sendable (Int) throws -> Void
    init(consumeBytes: @escaping @Sendable (Int) throws -> Void) { self.consumeBytes = consumeBytes }
    var bytes: Data { storage.withLock { $0 } }
    func write(_ bytes: UnsafeRawBufferPointer) throws {
        try Task.checkCancellation()
        // The serialized writer payload and retained final output coexist. This is
        // additional output-owner capacity, separate from the writer's own buffers.
        try consumeBytes(bytes.count)
        storage.withLock { $0.append(contentsOf: bytes) }
    }
}
